//! `SystemdFailedProvider` provider: snapshots failed system + user systemd
//! units and refreshes on a 250ms-debounced timer driven by `systemd1` D-Bus
//! manager signals (system and session buses).
//!
//! Delivered to C++ as a borrowed `#[repr(C)]` `SystemdFailedSnapshotC` (scalar
//! counts/strings plus two zero-copy `FailedUnitC` row arrays, one per scope);
//! the C++ `QsNativeSystemdFailedProvider` `QObject` deep-copies it into
//! `QVariantList`s of `QVariantMap`s on the Qt thread.

use std::ffi::CString;
use std::os::raw::{c_char, c_void};
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc, Mutex};
use std::thread;
use std::time::Duration;

use chrono::Local;
use futures_util::{stream, StreamExt};
use serde::Deserialize;
use zbus::{message::Type as MessageType, Connection, MatchRule, MessageStream};

use crate::count_to_i32;

const SYSTEMD_SERVICE: &str = "org.freedesktop.systemd1";
const SYSTEMD_PATH: &str = "/org/freedesktop/systemd1";
const SYSTEMD_MANAGER: &str = "org.freedesktop.systemd1.Manager";
const SYSTEMD_SIGNALS: &[&str] = &[
    "UnitFilesChanged",
    "Reloading",
    "JobRemoved",
    "UnitNew",
    "UnitRemoved",
];
const REFRESH_DEBOUNCE: Duration = Duration::from_millis(250);
/// Poll interval for the D-Bus signal-stream stop check (mirrors the
/// `bluetooth` discovery monitor's cancellation pattern).
const DBUS_POLL_TIMEOUT: Duration = Duration::from_millis(500);

#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct FailedUnit {
    unit: String,
    load: String,
    active: String,
    sub: String,
    description: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct FailedSnapshot {
    system_units: Vec<FailedUnit>,
    user_units: Vec<FailedUnit>,
    last_checked: String,
    error: String,
}

#[derive(Deserialize)]
struct SystemctlUnit {
    unit: Option<String>,
    load: Option<String>,
    active: Option<String>,
    sub: Option<String>,
    description: Option<String>,
}

/// A single failed unit row, borrowed for the duration of the callback.
#[repr(C)]
pub struct FailedUnitC {
    pub unit: *const c_char,
    pub load: *const c_char,
    pub active: *const c_char,
    pub sub: *const c_char,
    pub description: *const c_char,
}

/// Zero-copy snapshot handed to the C++ side. The `*const c_char`/row-array
/// fields borrow `CString`s/`Vec`s that live on the worker stack **only for the
/// duration of the callback**; C++ must copy them synchronously and must not
/// retain the pointers. Fields map 1:1 to `SystemdFailedProvider` QML
/// properties (`refreshing` is owned/toggled by C++ around the call instead).
#[repr(C)]
pub struct SystemdFailedSnapshotC {
    pub system_failed_count: i32,
    pub user_failed_count: i32,
    pub failed_count: i32,
    pub system_units: *const FailedUnitC,
    pub system_units_len: usize,
    pub user_units: *const FailedUnitC,
    pub user_units_len: usize,
    pub last_checked: *const c_char,
    pub error: *const c_char,
}

/// Delivers a `SystemdFailedSnapshotC` (borrowed for the call only) to C++.
pub type SystemdFailedSnapshotFn = unsafe extern "C" fn(*mut c_void, *const SystemdFailedSnapshotC);

/// A running persistent worker (D-Bus signal listener): its stop flag and join
/// handle, joined synchronously in `_Delete`.
struct Worker {
    stop: Arc<AtomicBool>,
    join: thread::JoinHandle<()>,
}

/// Opaque per-instance handle owned by the C++ `QsNativeSystemdFailedProvider`
/// `QObject`.
///
/// `alive` is shared with every worker and one-shot refresh thread so none of
/// them deliver a callback once the `QObject` has started tearing down.
pub struct SystemdFailedHandle {
    alive: Arc<AtomicBool>,
    started: AtomicBool,
    refresh_tx: Mutex<Option<mpsc::Sender<()>>>,
    debounce_join: Mutex<Option<thread::JoinHandle<()>>>,
    workers: Mutex<Vec<Worker>>,
}

#[no_mangle]
pub extern "C" fn QsNative_SystemdFailedProvider_New() -> *mut SystemdFailedHandle {
    Box::into_raw(Box::new(SystemdFailedHandle {
        alive: Arc::new(AtomicBool::new(true)),
        started: AtomicBool::new(false),
        refresh_tx: Mutex::new(None),
        debounce_join: Mutex::new(None),
        workers: Mutex::new(Vec::new()),
    }))
}

/// # Panics
/// Panics if any of the handle's mutexes have been poisoned (a worker thread
/// panicked while holding the lock).
///
/// # Safety
/// `handle` must be null or a pointer from `QsNative_SystemdFailedProvider_New`
/// that has not yet been freed.
#[no_mangle]
pub unsafe extern "C" fn QsNative_SystemdFailedProvider_Delete(handle: *mut SystemdFailedHandle) {
    if handle.is_null() {
        return;
    }
    let handle = Box::from_raw(handle);
    handle.alive.store(false, Ordering::SeqCst);

    // Drop the sender: the debounce thread's blocking `recv` wakes with an
    // error and the loop exits.
    handle
        .refresh_tx
        .lock()
        .expect("systemd_failed refresh_tx poisoned")
        .take();
    if let Some(join) = handle
        .debounce_join
        .lock()
        .expect("systemd_failed debounce_join poisoned")
        .take()
    {
        let _ = join.join();
    }

    for worker in handle
        .workers
        .lock()
        .expect("systemd_failed workers poisoned")
        .drain(..)
    {
        worker.stop.store(true, Ordering::Relaxed);
        let _ = worker.join.join();
    }
}

/// Starts the provider: on the first call, spawns the debounce worker plus the
/// system + session `systemd1` D-Bus signal listeners that feed it, then (every
/// call) performs an immediate refresh.
///
/// # Panics
/// Panics if any of the handle's mutexes have been poisoned.
///
/// # Safety
/// `handle` must be valid; `ctx`/`cb` must remain valid until `_Delete` returns
/// (every worker that can call `cb` is stopped and joined there first).
#[no_mangle]
pub unsafe extern "C" fn QsNative_SystemdFailedProvider_Start(
    handle: *mut SystemdFailedHandle,
    ctx: *mut c_void,
    cb: SystemdFailedSnapshotFn,
) {
    if handle.is_null() {
        return;
    }

    if (*handle)
        .started
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_ok()
    {
        let (tx, rx) = mpsc::channel();
        *(*handle)
            .refresh_tx
            .lock()
            .expect("systemd_failed refresh_tx poisoned") = Some(tx.clone());

        let alive = (*handle).alive.clone();
        let ctx_addr = ctx as usize;
        let debounce_join = thread::spawn(move || {
            while rx.recv().is_ok() {
                while rx.recv_timeout(REFRESH_DEBOUNCE).is_ok() {}
                if !alive.load(Ordering::SeqCst) {
                    break;
                }
                read_and_emit(&alive, ctx_addr, cb);
            }
        });
        *(*handle)
            .debounce_join
            .lock()
            .expect("systemd_failed debounce_join poisoned") = Some(debounce_join);

        let workers = vec![
            spawn_systemd_signal_listener(SystemdBus::System, tx.clone()),
            spawn_systemd_signal_listener(SystemdBus::Session, tx),
        ];
        *(*handle)
            .workers
            .lock()
            .expect("systemd_failed workers poisoned") = workers;
    }

    QsNative_SystemdFailedProvider_Refresh(handle, ctx, cb);
}

/// Performs an immediate (non-debounced) refresh on a worker thread and
/// delivers the snapshot via `cb`. Always returns `true` (fire-and-forget).
///
/// # Safety
/// `handle` must be valid; `ctx`/`cb` must remain valid until `cb` fires.
#[no_mangle]
pub unsafe extern "C" fn QsNative_SystemdFailedProvider_Refresh(
    handle: *mut SystemdFailedHandle,
    ctx: *mut c_void,
    cb: SystemdFailedSnapshotFn,
) -> bool {
    if handle.is_null() {
        return false;
    }
    let alive = (*handle).alive.clone();
    let ctx_addr = ctx as usize;
    thread::spawn(move || read_and_emit(&alive, ctx_addr, cb));
    true
}

/// Sends a debounce tick; the running debounce worker (started via `_Start`)
/// coalesces bursts and performs a single refresh `REFRESH_DEBOUNCE` after the
/// last tick. No-op before `_Start` has run.
///
/// # Panics
/// Panics if the handle's `refresh_tx` mutex has been poisoned.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn QsNative_SystemdFailedProvider_ScheduleRefresh(
    handle: *mut SystemdFailedHandle,
) {
    if handle.is_null() {
        return;
    }
    if let Some(tx) = (*handle)
        .refresh_tx
        .lock()
        .expect("systemd_failed refresh_tx poisoned")
        .as_ref()
    {
        let _ = tx.send(());
    }
}

/// Reads a fresh snapshot and, if the handle is still alive, delivers it via
/// `cb`. Guards against firing into a `QObject` that is mid-teardown: `_Delete`
/// flips `alive` before joining every thread that can reach this function.
fn read_and_emit(alive: &Arc<AtomicBool>, ctx: usize, cb: SystemdFailedSnapshotFn) {
    let snapshot = read_failed_snapshot();
    if !alive.load(Ordering::SeqCst) {
        return;
    }
    emit_snapshot(ctx, cb, &snapshot);
}

/// Builds the `CString`s/row arrays (kept alive for the call only) and invokes
/// `cb` with a borrowed `SystemdFailedSnapshotC`.
fn emit_snapshot(ctx: usize, cb: SystemdFailedSnapshotFn, snapshot: &FailedSnapshot) {
    // CStrings must outlive the callback; keep them bound in this scope.
    let system_owned = owned_units(&snapshot.system_units);
    let user_owned = owned_units(&snapshot.user_units);
    let system_rows: Vec<FailedUnitC> = system_owned.iter().map(OwnedFailedUnit::as_c).collect();
    let user_rows: Vec<FailedUnitC> = user_owned.iter().map(OwnedFailedUnit::as_c).collect();
    let last_checked = cstr(&snapshot.last_checked);
    let error = cstr(&snapshot.error);

    let system_count = count_to_i32(snapshot.system_units.len());
    let user_count = count_to_i32(snapshot.user_units.len());

    let c = SystemdFailedSnapshotC {
        system_failed_count: system_count,
        user_failed_count: user_count,
        failed_count: system_count.saturating_add(user_count),
        system_units: system_rows.as_ptr(),
        system_units_len: system_rows.len(),
        user_units: user_rows.as_ptr(),
        user_units_len: user_rows.len(),
        last_checked: last_checked.as_ptr(),
        error: error.as_ptr(),
    };

    unsafe { cb(ctx as *mut c_void, std::ptr::from_ref(&c)) };
}

/// `CString`-backed mirror of `FailedUnit`, kept alive across the callback so
/// `FailedUnitC` pointers stay valid.
struct OwnedFailedUnit {
    unit: CString,
    load: CString,
    active: CString,
    sub: CString,
    description: CString,
}

impl OwnedFailedUnit {
    fn as_c(&self) -> FailedUnitC {
        FailedUnitC {
            unit: self.unit.as_ptr(),
            load: self.load.as_ptr(),
            active: self.active.as_ptr(),
            sub: self.sub.as_ptr(),
            description: self.description.as_ptr(),
        }
    }
}

fn owned_units(units: &[FailedUnit]) -> Vec<OwnedFailedUnit> {
    units
        .iter()
        .map(|unit| OwnedFailedUnit {
            unit: cstr(&unit.unit),
            load: cstr(&unit.load),
            active: cstr(&unit.active),
            sub: cstr(&unit.sub),
            description: cstr(&unit.description),
        })
        .collect()
}

/// Builds a `CString`, falling back to empty on an interior NUL.
fn cstr(value: &str) -> CString {
    CString::new(value).unwrap_or_default()
}

fn read_failed_snapshot() -> FailedSnapshot {
    let (system_units, system_error) = list_failed_units(false);
    let (user_units, user_error) = list_failed_units(true);
    let errors = [("system", system_error), ("user", user_error)]
        .into_iter()
        .filter_map(|(scope, error)| error.map(|error| format!("{scope}: {error}")))
        .collect::<Vec<_>>()
        .join("; ");

    FailedSnapshot {
        system_units,
        user_units,
        last_checked: Local::now().format("%I:%M %p").to_string(),
        error: errors,
    }
}

fn list_failed_units(user: bool) -> (Vec<FailedUnit>, Option<String>) {
    let mut args = Vec::new();
    if user {
        args.push("--user");
    }
    args.extend(["list-units", "--failed", "--no-pager", "--output=json"]);

    match Command::new("systemctl").args(args).output() {
        Ok(output) if output.status.success() => match parse_failed_units_json(&output.stdout) {
            Ok(units) => (units, None),
            Err(error) => (Vec::new(), Some(error)),
        },
        Ok(output) => {
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_owned();
            let detail = if stderr.is_empty() { stdout } else { stderr };
            let error = if detail.is_empty() {
                output.status.to_string()
            } else {
                format!("{}: {detail}", output.status)
            };
            (Vec::new(), Some(error))
        }
        Err(error) => (Vec::new(), Some(error.to_string())),
    }
}

fn parse_failed_units_json(raw: &[u8]) -> Result<Vec<FailedUnit>, String> {
    let parsed: Vec<SystemctlUnit> =
        serde_json::from_slice(raw).map_err(|error| error.to_string())?;
    Ok(parsed
        .into_iter()
        .filter_map(|unit| {
            let name = unit.unit?;
            if name.is_empty() {
                return None;
            }

            Some(FailedUnit {
                unit: name,
                load: unit.load.unwrap_or_default(),
                active: unit.active.unwrap_or_default(),
                sub: unit.sub.unwrap_or_default(),
                description: unit.description.unwrap_or_default(),
            })
        })
        .collect())
}

#[derive(Clone, Copy)]
enum SystemdBus {
    System,
    Session,
}

/// Spawns a persistent worker that listens for `systemd1` manager signals on
/// `bus` and sends a debounce tick on `refresh_tx` for each one. Stoppable via
/// the returned `Worker`'s `stop` flag (polled every `DBUS_POLL_TIMEOUT`,
/// mirroring the `bluetooth` discovery monitor's cancellation pattern).
fn spawn_systemd_signal_listener(bus: SystemdBus, refresh_tx: mpsc::Sender<()>) -> Worker {
    let stop = Arc::new(AtomicBool::new(false));
    let thread_stop = stop.clone();
    let join = thread::spawn(move || {
        let Ok(runtime) = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        else {
            return;
        };
        runtime.block_on(async move {
            let _ = listen_for_systemd_signals(bus, &refresh_tx, &thread_stop).await;
        });
    });
    Worker { stop, join }
}

async fn listen_for_systemd_signals(
    bus: SystemdBus,
    refresh_tx: &mpsc::Sender<()>,
    stop: &Arc<AtomicBool>,
) -> zbus::Result<()> {
    let connection = match bus {
        SystemdBus::System => Connection::system().await?,
        SystemdBus::Session => Connection::session().await?,
    };

    let mut streams = Vec::with_capacity(SYSTEMD_SIGNALS.len());
    for signal in SYSTEMD_SIGNALS {
        streams.push(systemd_signal_stream(&connection, signal).await?);
    }

    let mut signals = stream::select_all(streams);
    while !stop.load(Ordering::Relaxed) {
        let message = match tokio::time::timeout(DBUS_POLL_TIMEOUT, signals.next()).await {
            Ok(Some(message)) => message,
            Ok(None) => break,
            Err(_) => continue,
        };
        let _ = message?;
        let _ = refresh_tx.send(());
    }

    Ok(())
}

async fn systemd_signal_stream(
    connection: &Connection,
    signal: &str,
) -> zbus::Result<MessageStream> {
    let rule = MatchRule::builder()
        .msg_type(MessageType::Signal)
        .sender(SYSTEMD_SERVICE)?
        .path(SYSTEMD_PATH)?
        .interface(SYSTEMD_MANAGER)?
        .member(signal)?
        .build();
    MessageStream::for_match_rule(rule, connection, Some(8)).await
}

#[cfg(test)]
mod tests {
    use super::{parse_failed_units_json, FailedUnit};

    #[test]
    fn parses_systemctl_json_and_skips_empty_unit_names() {
        let got = parse_failed_units_json(
            br#"[
                {"unit":"alpha.service","load":"loaded","active":"failed","sub":"failed","description":"Alpha"},
                {"unit":"","description":"ignored"},
                {"unit":"beta.timer","load":null,"active":"failed","sub":"failed"}
            ]"#,
        )
        .expect("parse units");

        assert_eq!(
            got,
            vec![
                FailedUnit {
                    unit: "alpha.service".to_owned(),
                    load: "loaded".to_owned(),
                    active: "failed".to_owned(),
                    sub: "failed".to_owned(),
                    description: "Alpha".to_owned(),
                },
                FailedUnit {
                    unit: "beta.timer".to_owned(),
                    load: String::new(),
                    active: "failed".to_owned(),
                    sub: "failed".to_owned(),
                    description: String::new(),
                },
            ]
        );
    }
}
