use core::pin::Pin;
use std::process::Command;
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use crate::count_to_i32;

use chrono::Local;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QString, QVariant};
use futures_util::{stream, StreamExt};
use serde::Deserialize;
use zbus::{message::Type as MessageType, Connection, MatchRule, MessageStream};

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

#[derive(Default)]
pub struct SystemdFailedProviderRust {
    system_failed_count: i32,
    user_failed_count: i32,
    failed_count: i32,
    system_failed_units: QList<QVariant>,
    user_failed_units: QList<QVariant>,
    last_checked: QString,
    error: QString,
    refreshing: bool,
    started: bool,
    refresh_tx: Option<mpsc::Sender<()>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct FailedUnit {
    unit: String,
    load: String,
    active: String,
    sub: String,
    description: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
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

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;

        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;

        include!("cxx-qt-lib/core/qlist/qlist_QVariant.h");
        type QList_QVariant = cxx_qt_lib::QList<QVariant>;
    }

    #[namespace = "qsnative::systemd_failed"]
    unsafe extern "C++" {
        include!("QsNativeSystemdFailed.h");

        #[rust_name = "failed_unit_variant"]
        fn failedUnitVariant(
            unit: &QString,
            load: &QString,
            active: &QString,
            sub: &QString,
            description: &QString,
        ) -> QVariant;
    }

    impl cxx_qt::Threading for SystemdFailedProvider {}

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qobject]
        #[qproperty(i32, system_failed_count, cxx_name = "system_failed_count")]
        #[qproperty(i32, user_failed_count, cxx_name = "user_failed_count")]
        #[qproperty(i32, failed_count, cxx_name = "failed_count")]
        #[qproperty(QList_QVariant, system_failed_units, cxx_name = "system_failed_units")]
        #[qproperty(QList_QVariant, user_failed_units, cxx_name = "user_failed_units")]
        #[qproperty(QString, last_checked, cxx_name = "last_checked")]
        #[qproperty(QString, error)]
        #[qproperty(bool, refreshing)]
        type SystemdFailedProvider = super::SystemdFailedProviderRust;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qinvokable]
        fn start(self: Pin<&mut SystemdFailedProvider>);

        #[qinvokable]
        fn refresh(self: Pin<&mut SystemdFailedProvider>) -> bool;

        #[qinvokable]
        #[cxx_name = "scheduleRefresh"]
        fn schedule_refresh(self: Pin<&mut SystemdFailedProvider>);
    }

    impl cxx_qt::Initialize for SystemdFailedProvider {}
}

impl cxx_qt::Initialize for ffi::SystemdFailedProvider {
    fn initialize(self: Pin<&mut Self>) {}
}

impl ffi::SystemdFailedProvider {
    pub fn start(mut self: Pin<&mut Self>) {
        if !self.as_ref().rust().started {
            let qt_thread = self.as_ref().qt_thread();
            let (refresh_tx, refresh_rx) = mpsc::channel();
            self.as_mut().rust_mut().as_mut().get_mut().started = true;
            self.as_mut().rust_mut().as_mut().get_mut().refresh_tx = Some(refresh_tx.clone());
            thread::spawn(move || {
                while refresh_rx.recv().is_ok() {
                    while refresh_rx.recv_timeout(REFRESH_DEBOUNCE).is_ok() {}
                    let _ = qt_thread.queue(|mut provider| {
                        provider.as_mut().refresh();
                    });
                }
            });
            spawn_systemd_signal_listeners(refresh_tx);
        }

        self.refresh();
    }

    pub fn refresh(mut self: Pin<&mut Self>) -> bool {
        self.as_mut().set_refreshing(true);
        let qt_thread = self.as_ref().qt_thread();

        thread::spawn(move || {
            let snapshot = read_failed_snapshot();
            let _ = qt_thread.queue(move |mut provider| {
                provider.as_mut().apply_snapshot(snapshot);
                provider.as_mut().set_refreshing(false);
            });
        });

        true
    }

    pub fn schedule_refresh(self: Pin<&mut Self>) {
        if let Some(refresh_tx) = self.as_ref().rust().refresh_tx.as_ref() {
            let _ = refresh_tx.send(());
        }
    }

    fn apply_snapshot(mut self: Pin<&mut Self>, snapshot: FailedSnapshot) {
        let system_count = count_to_i32(snapshot.system_units.len());
        let user_count = count_to_i32(snapshot.user_units.len());

        self.as_mut().set_system_failed_count(system_count);
        self.as_mut().set_user_failed_count(user_count);
        self.as_mut()
            .set_failed_count(system_count.saturating_add(user_count));
        self.as_mut()
            .set_system_failed_units(units_to_qvariant_list(&snapshot.system_units));
        self.as_mut()
            .set_user_failed_units(units_to_qvariant_list(&snapshot.user_units));
        self.as_mut()
            .set_last_checked(QString::from(snapshot.last_checked));
        self.set_error(QString::from(snapshot.error));
    }
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

fn units_to_qvariant_list(units: &[FailedUnit]) -> QList<QVariant> {
    let mut list = QList::default();
    list.reserve(units.len().try_into().unwrap_or(isize::MAX));
    for unit in units {
        list.append(failed_unit_variant(unit));
    }
    list
}

fn failed_unit_variant(unit: &FailedUnit) -> QVariant {
    ffi::failed_unit_variant(
        &QString::from(unit.unit.as_str()),
        &QString::from(unit.load.as_str()),
        &QString::from(unit.active.as_str()),
        &QString::from(unit.sub.as_str()),
        &QString::from(unit.description.as_str()),
    )
}

fn spawn_systemd_signal_listeners(refresh_tx: mpsc::Sender<()>) {
    for bus in [SystemdBus::System, SystemdBus::Session] {
        let refresh_tx = refresh_tx.clone();
        thread::spawn(move || {
            let runtime = match tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
            {
                Ok(runtime) => runtime,
                Err(_) => return,
            };
            runtime.block_on(async move {
                let _ = listen_for_systemd_signals(bus, refresh_tx).await;
            });
        });
    }
}

#[derive(Clone, Copy)]
enum SystemdBus {
    System,
    Session,
}

async fn listen_for_systemd_signals(
    bus: SystemdBus,
    refresh_tx: mpsc::Sender<()>,
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
    while signals.next().await.transpose()?.is_some() {
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
