//! Bluetooth discovery diagnostics provider (`BluetoothDiagnosticsProvider`).
//!
//! Debug-only helpers for the Bluetooth bar module: a system-bus D-Bus monitor
//! that resolves which client issued `Adapter1.StartDiscovery`, a synchronous
//! procfs scan for processes that might be holding discovery open, and a
//! session-bus probe for the librepods `StatusNotifierItem` tooltip.
//!
//! The `extern "C"` surface is an opaque handle plus threaded callbacks; the C++
//! `QsNativeBluetooth` `QObject` owns the properties and marshals worker updates
//! back onto the Qt thread. Worker threads deliver a partial JSON snapshot
//! (only the keys they touch); C++ applies each present key and emits the
//! matching per-property change signal.

use std::fs;
use std::os::raw::{c_char, c_void};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use std::thread;
use std::time::Duration;

use futures_util::StreamExt;
use procfs::process::{all_processes, Process};
use zbus::names::BusName;
use zbus::zvariant::Type;
use zbus::{
    fdo::{DBusProxy, MonitoringProxy},
    message::Type as MessageType,
    Connection, MatchRule, MessageStream, Proxy,
};

use crate::ffi::{emit_snapshot, into_c_string, QsNativeUpdateFn};

const HOLDER_KEYWORDS: &[&str] = &[
    "btmgmt",
    "bluetoothctl",
    "blueman",
    "blueberry",
    "kdeconnectd",
    "librepods",
];

#[derive(Debug, Clone, PartialEq, Eq)]
struct DiscoveryCaller {
    sender: String,
    pid: i32,
    process: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Type, serde::Deserialize)]
struct StatusNotifierTooltip(String, Vec<(i32, i32, Vec<u8>)>, String, String);

impl TryFrom<zbus::zvariant::OwnedValue> for StatusNotifierTooltip {
    type Error = zbus::zvariant::Error;

    fn try_from(value: zbus::zvariant::OwnedValue) -> Result<Self, Self::Error> {
        let (icon, image, title, body) = value.try_into()?;
        Ok(Self(icon, image, title, body))
    }
}

/// A running discovery-monitor worker: its stop flag and join handle.
struct MonitorThread {
    stop: Arc<AtomicBool>,
    join: thread::JoinHandle<()>,
}

/// Opaque per-instance handle owned by the C++ `QsNativeBluetooth` `QObject`.
///
/// Holds the currently-running discovery monitor (if any). All access is from
/// the Qt thread, but the worker join happens under the lock so `_Delete`
/// during an in-flight monitor is safe.
pub struct BluetoothHandle {
    monitor: Mutex<Option<MonitorThread>>,
}

#[no_mangle]
pub extern "C" fn QsNative_Bluetooth_New() -> *mut BluetoothHandle {
    Box::into_raw(Box::new(BluetoothHandle {
        monitor: Mutex::new(None),
    }))
}

/// # Panics
/// Panics if the monitor mutex is poisoned (a worker thread panicked while holding it).
///
/// # Safety
/// `handle` must be null or a pointer from `QsNative_Bluetooth_New` not yet freed.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Bluetooth_Delete(handle: *mut BluetoothHandle) {
    if handle.is_null() {
        return;
    }
    let handle = Box::from_raw(handle);
    // Release the mutex guard (a temporary) before `handle` is dropped at the
    // end of the block, otherwise its borrow outlives the owner.
    let monitor = handle.monitor.lock().expect("bt monitor poisoned").take();
    if let Some(monitor) = monitor {
        monitor.stop.store(true, Ordering::Relaxed);
        let _ = monitor.join.join();
    }
}

/// Spawns the system-bus discovery monitor. Each resolved caller is delivered as
/// a partial snapshot; when the monitor thread exits it delivers `monitoring =
/// false` (plus `error` on failure). Re-entrancy is guarded on the C++ side via
/// the `monitoring` property, so any previously-finished thread is joined and
/// replaced here.
///
/// # Panics
/// Panics if the monitor mutex is poisoned (a worker thread panicked while holding it).
///
/// # Safety
/// `handle` must be valid; `ctx`/`cb` must remain valid until the worker exits
/// (the C++ side joins it in `_Delete`).
#[no_mangle]
pub unsafe extern "C" fn QsNative_Bluetooth_StartDiscoveryMonitor(
    handle: *mut BluetoothHandle,
    ctx: *mut c_void,
    cb: QsNativeUpdateFn,
) {
    if handle.is_null() {
        return;
    }
    let mut guard = (*handle).monitor.lock().expect("bt monitor poisoned");
    if let Some(old) = guard.take() {
        old.stop.store(true, Ordering::Relaxed);
        let _ = old.join.join();
    }

    let stop = Arc::new(AtomicBool::new(false));
    let thread_stop = stop.clone();
    let ctx = ctx as usize;
    let join = thread::spawn(move || {
        let mut last_sender = String::new();
        let result = run_discovery_monitor(thread_stop, |caller| {
            if caller.sender == last_sender {
                return;
            }
            last_sender.clone_from(&caller.sender);
            unsafe { emit_snapshot(cb, ctx as *mut c_void, caller_json(&caller)) };
        });
        let json = match result {
            Ok(()) => stopped_json(None),
            Err(error) => stopped_json(Some(error)),
        };
        unsafe { emit_snapshot(cb, ctx as *mut c_void, json) };
    });

    *guard = Some(MonitorThread { stop, join });
}

/// Signals the running discovery monitor to stop. The worker notices the flag,
/// exits, and delivers `monitoring = false`.
///
/// # Panics
/// Panics if the monitor mutex is poisoned (a worker thread panicked while holding it).
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Bluetooth_StopDiscoveryMonitor(handle: *mut BluetoothHandle) {
    if handle.is_null() {
        return;
    }
    if let Some(monitor) = (*handle).monitor.lock().expect("bt monitor poisoned").as_ref() {
        monitor.stop.store(true, Ordering::Relaxed);
    }
}

/// Scans procfs for processes matching `HOLDER_KEYWORDS`, returning the
/// newline-joined table. Runs synchronously on the caller (Qt) thread. The
/// returned pointer must be released with `QsNative_Free`.
#[no_mangle]
pub extern "C" fn QsNative_Bluetooth_ScanHolders() -> *mut c_char {
    into_c_string(scan_holder_processes())
}

/// Spawns a session-bus probe for the librepods `StatusNotifierItem` tooltip.
/// Delivers `librepods_tooltip` + `error` (error cleared on success).
///
/// # Safety
/// `ctx`/`cb` must remain valid until the worker fires.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Bluetooth_ProbeLibrepodsTooltip(
    ctx: *mut c_void,
    cb: QsNativeUpdateFn,
) {
    let ctx = ctx as usize;
    thread::spawn(move || {
        let json = match read_librepods_tooltip() {
            Ok(tooltip) => librepods_json(&tooltip, ""),
            Err(error) => librepods_json("", &error),
        };
        unsafe { emit_snapshot(cb, ctx as *mut c_void, json) };
    });
}

fn caller_json(caller: &DiscoveryCaller) -> String {
    serde_json::json!({
        "last_start_discovery_sender": caller.sender,
        "last_start_discovery_pid": caller.pid,
        "last_start_discovery_process": caller.process,
        "error": "",
    })
    .to_string()
}

fn stopped_json(error: Option<String>) -> String {
    match error {
        Some(error) => serde_json::json!({ "monitoring": false, "error": error }).to_string(),
        None => serde_json::json!({ "monitoring": false }).to_string(),
    }
}

fn librepods_json(tooltip: &str, error: &str) -> String {
    serde_json::json!({
        "librepods_tooltip": tooltip,
        "error": error,
    })
    .to_string()
}

fn run_discovery_monitor<F>(stop: Arc<AtomicBool>, mut on_caller: F) -> Result<(), String>
where
    F: FnMut(DiscoveryCaller),
{
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|error| error.to_string())?;

    runtime.block_on(async move {
        let monitor_connection = Connection::system()
            .await
            .map_err(|error| error.to_string())?;
        let resolver_connection = Connection::system()
            .await
            .map_err(|error| error.to_string())?;
        let rule = MatchRule::builder()
            .msg_type(MessageType::MethodCall)
            .destination("org.bluez")
            .map_err(|error| error.to_string())?
            .interface("org.bluez.Adapter1")
            .map_err(|error| error.to_string())?
            .member("StartDiscovery")
            .map_err(|error| error.to_string())?
            .build();

        MonitoringProxy::new(&monitor_connection)
            .await
            .map_err(|error| error.to_string())?
            .become_monitor(&[rule], 0)
            .await
            .map_err(|error| error.to_string())?;

        let mut stream = MessageStream::from(monitor_connection);
        while !stop.load(Ordering::Relaxed) {
            let message =
                match tokio::time::timeout(Duration::from_millis(500), stream.next()).await {
                    Ok(Some(message)) => message,
                    Ok(None) => break,
                    Err(_) => continue,
                };
            if stop.load(Ordering::Relaxed) {
                break;
            }
            let message = message.map_err(|error| error.to_string())?;
            let header = message.header();
            if header.message_type() != MessageType::MethodCall {
                continue;
            }
            if header.destination().map(BusName::as_str) != Some("org.bluez")
                || header.interface().map(zbus::names::InterfaceName::as_str)
                    != Some("org.bluez.Adapter1")
                || header.member().map(zbus::names::MemberName::as_str) != Some("StartDiscovery")
            {
                continue;
            }
            let Some(sender) = header.sender().map(|value| value.as_str().to_owned()) else {
                continue;
            };
            let caller = resolve_discovery_caller(&resolver_connection, sender).await;
            on_caller(caller);
        }

        Ok(())
    })
}

async fn resolve_discovery_caller(connection: &Connection, sender: String) -> DiscoveryCaller {
    let pid = match DBusProxy::new(connection).await {
        Ok(proxy) => match BusName::try_from(sender.as_str()) {
            Ok(bus_name) => proxy
                .get_connection_unix_process_id(bus_name)
                .await
                .map_or(-1, |pid| pid.try_into().unwrap_or(i32::MAX)),
            Err(_) => -1,
        },
        Err(_) => -1,
    };
    let process = if pid > 0 {
        process_name(pid)
    } else {
        String::new()
    };
    DiscoveryCaller {
        sender,
        pid,
        process,
    }
}

fn process_name(pid: i32) -> String {
    Process::new(pid)
        .ok()
        .and_then(|process| process.stat().ok())
        .map(|stat| stat.comm)
        .unwrap_or_default()
}

fn scan_holder_processes() -> String {
    let mut hits = Vec::new();
    let Ok(processes) = all_processes() else {
        return String::new();
    };

    for process in processes.flatten() {
        let cmd = process_command(&process);
        if cmd.is_empty() {
            continue;
        }
        let lower = cmd.to_lowercase();
        if !HOLDER_KEYWORDS.iter().any(|keyword| lower.contains(keyword)) {
            continue;
        }
        let user = process
            .status()
            .ok()
            .and_then(|status| username_for_uid(status.euid))
            .unwrap_or_else(|| "?".to_owned());
        hits.push(format!("{:>6} {:<12} {}", process.pid, user, cmd));
        if hits.len() >= 20 {
            break;
        }
    }

    hits.join("\n")
}

fn process_command(process: &Process) -> String {
    match process.cmdline() {
        Ok(parts) if !parts.is_empty() => parts.join(" "),
        _ => process.stat().map(|stat| stat.comm).unwrap_or_default(),
    }
}

fn username_for_uid(uid: u32) -> Option<String> {
    let passwd = fs::read_to_string("/etc/passwd").ok()?;
    passwd.lines().find_map(|line| {
        let mut parts = line.split(':');
        let name = parts.next()?;
        let _password = parts.next()?;
        let raw_uid = parts.next()?;
        if raw_uid.parse::<u32>().ok()? == uid {
            Some(name.to_owned())
        } else {
            None
        }
    })
}

fn read_librepods_tooltip() -> Result<String, String> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|error| error.to_string())?;
    runtime.block_on(read_librepods_tooltip_async())
}

async fn read_librepods_tooltip_async() -> Result<String, String> {
    let connection = Connection::session()
        .await
        .map_err(|error| error.to_string())?;
    let dbus = DBusProxy::new(&connection)
        .await
        .map_err(|error| error.to_string())?;
    let names = dbus.list_names().await.map_err(|error| error.to_string())?;

    for name in names
        .iter()
        .map(|name| name.as_str())
        .filter(|name| name.starts_with("org.kde.StatusNotifierItem-"))
    {
        let proxy = Proxy::new(
            &connection,
            name,
            "/StatusNotifierItem",
            "org.kde.StatusNotifierItem",
        )
        .await
        .map_err(|error| error.to_string())?;

        let id = proxy.get_property::<String>("Id").await.unwrap_or_default();
        if !id.eq_ignore_ascii_case("librepods") {
            continue;
        }

        let tooltip = proxy
            .get_property::<StatusNotifierTooltip>("ToolTip")
            .await
            .map_err(|error| error.to_string())?;
        let joined = [tooltip.0, tooltip.2, tooltip.3]
            .into_iter()
            .filter(|part| !part.trim().is_empty())
            .collect::<Vec<_>>()
            .join(" ");
        return Ok(joined);
    }

    Ok(String::new())
}

#[cfg(test)]
mod tests {
    use super::username_for_uid;

    #[test]
    fn passwd_lookup_handles_missing_uid() {
        assert!(username_for_uid(u32::MAX).is_none());
    }
}
