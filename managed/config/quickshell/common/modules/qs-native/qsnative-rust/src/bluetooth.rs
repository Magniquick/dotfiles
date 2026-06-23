use core::pin::Pin;
use std::fs;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::thread;
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use futures_util::StreamExt;
use procfs::process::{all_processes, Process};
use zbus::names::BusName;
use zbus::zvariant::Type;
use zbus::{
    fdo::{DBusProxy, MonitoringProxy},
    message::Type as MessageType,
    Connection, MatchRule, MessageStream, Proxy,
};

const HOLDER_KEYWORDS: &[&str] = &[
    "btmgmt",
    "bluetoothctl",
    "blueman",
    "blueberry",
    "kdeconnectd",
    "librepods",
];

#[derive(Default)]
pub struct BluetoothDiagnosticsProviderRust {
    last_start_discovery_sender: QString,
    last_start_discovery_pid: i32,
    last_start_discovery_process: QString,
    last_scan_holders: QString,
    librepods_tooltip: QString,
    error: QString,
    monitoring: bool,
    stop_monitor: Option<Arc<AtomicBool>>,
}

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

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    impl cxx_qt::Threading for BluetoothDiagnosticsProvider {}

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qobject]
        #[qproperty(
            QString,
            last_start_discovery_sender,
            cxx_name = "last_start_discovery_sender"
        )]
        #[qproperty(i32, last_start_discovery_pid, cxx_name = "last_start_discovery_pid")]
        #[qproperty(
            QString,
            last_start_discovery_process,
            cxx_name = "last_start_discovery_process"
        )]
        #[qproperty(QString, last_scan_holders, cxx_name = "last_scan_holders")]
        #[qproperty(QString, librepods_tooltip, cxx_name = "librepods_tooltip")]
        #[qproperty(QString, error)]
        #[qproperty(bool, monitoring)]
        type BluetoothDiagnosticsProvider = super::BluetoothDiagnosticsProviderRust;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qinvokable]
        #[cxx_name = "startDiscoveryMonitor"]
        fn start_discovery_monitor(self: Pin<&mut BluetoothDiagnosticsProvider>) -> bool;

        #[qinvokable]
        #[cxx_name = "stopDiscoveryMonitor"]
        fn stop_discovery_monitor(self: Pin<&mut BluetoothDiagnosticsProvider>);

        #[qinvokable]
        #[cxx_name = "probeScanHolders"]
        fn probe_scan_holders(self: Pin<&mut BluetoothDiagnosticsProvider>) -> bool;

        #[qinvokable]
        #[cxx_name = "probeLibrepodsTooltip"]
        fn probe_librepods_tooltip(self: Pin<&mut BluetoothDiagnosticsProvider>) -> bool;
    }

    impl cxx_qt::Initialize for BluetoothDiagnosticsProvider {}
}

impl cxx_qt::Initialize for ffi::BluetoothDiagnosticsProvider {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut().set_last_start_discovery_pid(-1);
    }
}

impl ffi::BluetoothDiagnosticsProvider {
    pub fn start_discovery_monitor(mut self: Pin<&mut Self>) -> bool {
        if *self.monitoring() {
            return true;
        }

        let stop = Arc::new(AtomicBool::new(false));
        let qt_thread = self.as_ref().qt_thread();
        let event_thread = qt_thread.clone();
        self.as_mut().rust_mut().as_mut().get_mut().stop_monitor = Some(stop.clone());
        self.as_mut().set_monitoring(true);

        thread::spawn(move || {
            let result = run_discovery_monitor(stop, move |caller| {
                let _ = event_thread.queue(move |mut provider| {
                    provider.as_mut().apply_discovery_caller(caller);
                });
            });

            let _ = qt_thread.queue(move |mut provider| {
                provider.as_mut().set_monitoring(false);
                if let Err(error) = result {
                    provider.as_mut().set_error(QString::from(error));
                }
            });
        });

        true
    }

    pub fn stop_discovery_monitor(mut self: Pin<&mut Self>) {
        if let Some(stop) = self.as_ref().rust().stop_monitor.as_ref() {
            stop.store(true, Ordering::Relaxed);
        }
        self.as_mut().rust_mut().as_mut().get_mut().stop_monitor = None;
    }

    pub fn probe_scan_holders(mut self: Pin<&mut Self>) -> bool {
        let holders = scan_holder_processes();
        self.as_mut().set_last_scan_holders(QString::from(holders));
        true
    }

    pub fn probe_librepods_tooltip(self: Pin<&mut Self>) -> bool {
        let qt_thread = self.as_ref().qt_thread();
        thread::spawn(move || {
            let result = read_librepods_tooltip();
            let _ = qt_thread.queue(move |mut provider| match result {
                Ok(tooltip) => {
                    provider
                        .as_mut()
                        .set_librepods_tooltip(QString::from(tooltip));
                    provider.as_mut().set_error(QString::default());
                }
                Err(error) => {
                    provider.as_mut().set_librepods_tooltip(QString::default());
                    provider.as_mut().set_error(QString::from(error));
                }
            });
        });
        true
    }

    fn apply_discovery_caller(mut self: Pin<&mut Self>, caller: DiscoveryCaller) {
        if caller.sender == self.last_start_discovery_sender().to_string() {
            return;
        }
        self.as_mut()
            .set_last_start_discovery_sender(QString::from(caller.sender));
        self.as_mut().set_last_start_discovery_pid(caller.pid);
        self.as_mut()
            .set_last_start_discovery_process(QString::from(caller.process));
        self.as_mut().set_error(QString::default());
    }
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
            if header.destination().map(|value| value.as_str()) != Some("org.bluez")
                || header.interface().map(|value| value.as_str()) != Some("org.bluez.Adapter1")
                || header.member().map(|value| value.as_str()) != Some("StartDiscovery")
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
                .map(|pid| pid.try_into().unwrap_or(i32::MAX))
                .unwrap_or(-1),
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
        if !HOLDER_KEYWORDS
            .iter()
            .any(|keyword| lower.contains(keyword))
        {
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
