use core::pin::Pin;
use std::fs;
use std::path::Path;
use std::process::{Child, Command, Stdio};

use cxx_qt::CxxQtType;
use cxx_qt_lib::QString;
use serde::{Deserialize, Serialize};
use serde_json::json;

const DEFAULT_DISPLAY_OFF_TIMEOUT_SEC: i32 = 10;
const DEFAULT_SUSPEND_TIMEOUT_SEC: i32 = 1800;

pub struct IdleProviderRust {
    display_off_timeout_sec: i32,
    suspend_timeout_sec: i32,
    suspend_enabled: bool,
    ignore_lid_events: bool,
    lid_inhibited: bool,
    error: QString,
    lid_inhibit_child: Option<Child>,
}

impl Default for IdleProviderRust {
    fn default() -> Self {
        Self {
            display_off_timeout_sec: DEFAULT_DISPLAY_OFF_TIMEOUT_SEC,
            suspend_timeout_sec: DEFAULT_SUSPEND_TIMEOUT_SEC,
            suspend_enabled: false,
            ignore_lid_events: false,
            lid_inhibited: false,
            error: QString::default(),
            lid_inhibit_child: None,
        }
    }
}

impl Drop for IdleProviderRust {
    fn drop(&mut self) {
        stop_lid_inhibit_child(&mut self.lid_inhibit_child);
    }
}

#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
struct IdleSettings {
    display_off_timeout_sec: i32,
    suspend_timeout_sec: i32,
    suspend_enabled: bool,
    ignore_lid_events: bool,
}

impl Default for IdleSettings {
    fn default() -> Self {
        Self {
            display_off_timeout_sec: DEFAULT_DISPLAY_OFF_TIMEOUT_SEC,
            suspend_timeout_sec: DEFAULT_SUSPEND_TIMEOUT_SEC,
            suspend_enabled: false,
            ignore_lid_events: false,
        }
    }
}

impl IdleSettings {
    fn clamped(self) -> Self {
        Self {
            display_off_timeout_sec: clamp_timeout(self.display_off_timeout_sec),
            suspend_timeout_sec: clamp_timeout(self.suspend_timeout_sec),
            suspend_enabled: self.suspend_enabled,
            ignore_lid_events: self.ignore_lid_events,
        }
    }
}

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qobject]
        #[qproperty(i32, display_off_timeout_sec, cxx_name = "displayOffTimeoutSec")]
        #[qproperty(i32, suspend_timeout_sec, cxx_name = "suspendTimeoutSec")]
        #[qproperty(bool, suspend_enabled, cxx_name = "suspendEnabled")]
        #[qproperty(bool, ignore_lid_events, cxx_name = "ignoreLidEvents")]
        #[qproperty(bool, lid_inhibited, cxx_name = "lidInhibited")]
        #[qproperty(QString, error)]
        type IdleProvider = super::IdleProviderRust;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qinvokable]
        #[cxx_name = "loadSettings"]
        fn load_settings(self: Pin<&mut IdleProvider>, path: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "saveSettings"]
        fn save_settings(
            self: Pin<&mut IdleProvider>,
            path: &QString,
            display_off_timeout_sec: i32,
            suspend_timeout_sec: i32,
            suspend_enabled: bool,
            ignore_lid_events: bool,
        ) -> bool;

        #[qinvokable]
        #[cxx_name = "clampTimeout"]
        fn clamp_timeout_qml(self: &IdleProvider, seconds: i32) -> i32;

        #[qinvokable]
        #[cxx_name = "statusJson"]
        fn status_json(
            self: &IdleProvider,
            dpms_off: bool,
            next_suspend_at_ms: f64,
            sleep_inhibited: bool,
            now_ms: f64,
        ) -> QString;

        #[qinvokable]
        #[cxx_name = "syncLidInhibitProcess"]
        fn set_lid_inhibited_process(self: Pin<&mut IdleProvider>, inhibited: bool) -> bool;
    }

    impl cxx_qt::Initialize for IdleProvider {}
}

impl cxx_qt::Initialize for ffi::IdleProvider {
    fn initialize(self: Pin<&mut Self>) {}
}

impl ffi::IdleProvider {
    pub fn load_settings(mut self: Pin<&mut Self>, path: &QString) -> bool {
        match load_settings(Path::new(&path.to_string())) {
            Ok(settings) => {
                self.as_mut().apply_settings(settings);
                self.as_mut().set_error(QString::default());
                true
            }
            Err(error) => {
                self.as_mut().apply_settings(IdleSettings::default());
                self.as_mut().set_error(QString::from(error.as_str()));
                false
            }
        }
    }

    pub fn save_settings(
        mut self: Pin<&mut Self>,
        path: &QString,
        display_off_timeout_sec: i32,
        suspend_timeout_sec: i32,
        suspend_enabled: bool,
        ignore_lid_events: bool,
    ) -> bool {
        let settings = IdleSettings {
            display_off_timeout_sec,
            suspend_timeout_sec,
            suspend_enabled,
            ignore_lid_events,
        }
        .clamped();

        self.as_mut().apply_settings(settings);
        match save_settings(Path::new(&path.to_string()), settings) {
            Ok(()) => {
                self.as_mut().set_error(QString::default());
                true
            }
            Err(error) => {
                self.as_mut().set_error(QString::from(error.as_str()));
                false
            }
        }
    }

    pub fn clamp_timeout_qml(&self, seconds: i32) -> i32 {
        clamp_timeout(seconds)
    }

    pub fn status_json(
        &self,
        dpms_off: bool,
        next_suspend_at_ms: f64,
        sleep_inhibited: bool,
        now_ms: f64,
    ) -> QString {
        QString::from(
            build_status_json(StatusInput {
                dpms_off,
                display_off_timeout_sec: *self.display_off_timeout_sec(),
                suspend_enabled: *self.suspend_enabled(),
                suspend_timeout_sec: *self.suspend_timeout_sec(),
                next_suspend_at_ms,
                sleep_inhibited,
                ignore_lid_events: *self.ignore_lid_events(),
                now_ms,
            })
            .as_str(),
        )
    }

    pub fn set_lid_inhibited_process(mut self: Pin<&mut Self>, inhibited: bool) -> bool {
        if inhibited {
            let should_spawn = match self
                .as_mut()
                .rust_mut()
                .as_mut()
                .get_mut()
                .lid_inhibit_child
            {
                Some(ref mut child) => !matches!(child.try_wait(), Ok(None)),
                None => true,
            };

            if should_spawn {
                match spawn_lid_inhibit_child() {
                    Ok(child) => {
                        self.as_mut()
                            .rust_mut()
                            .as_mut()
                            .get_mut()
                            .lid_inhibit_child = Some(child);
                    }
                    Err(error) => {
                        self.as_mut().set_lid_inhibited(false);
                        self.as_mut().set_error(QString::from(error.as_str()));
                        return false;
                    }
                }
            }
            self.as_mut().set_lid_inhibited(true);
            self.as_mut().set_error(QString::default());
            return true;
        }

        stop_lid_inhibit_child(
            &mut self
                .as_mut()
                .rust_mut()
                .as_mut()
                .get_mut()
                .lid_inhibit_child,
        );
        self.as_mut().set_lid_inhibited(false);
        self.as_mut().set_error(QString::default());
        true
    }

    fn apply_settings(mut self: Pin<&mut Self>, settings: IdleSettings) {
        self.as_mut()
            .set_display_off_timeout_sec(settings.display_off_timeout_sec);
        self.as_mut()
            .set_suspend_timeout_sec(settings.suspend_timeout_sec);
        self.as_mut().set_suspend_enabled(settings.suspend_enabled);
        self.as_mut()
            .set_ignore_lid_events(settings.ignore_lid_events);
    }
}

#[derive(Debug, Clone, Copy)]
struct StatusInput {
    dpms_off: bool,
    display_off_timeout_sec: i32,
    suspend_enabled: bool,
    suspend_timeout_sec: i32,
    next_suspend_at_ms: f64,
    sleep_inhibited: bool,
    ignore_lid_events: bool,
    now_ms: f64,
}

fn clamp_timeout(seconds: i32) -> i32 {
    seconds.max(0)
}

fn load_settings(path: &Path) -> Result<IdleSettings, String> {
    if !path.exists() {
        return Ok(IdleSettings::default());
    }

    let raw = fs::read_to_string(path).map_err(|error| format!("read settings: {error}"))?;
    serde_json::from_str::<IdleSettings>(&raw)
        .map(IdleSettings::clamped)
        .map_err(|error| format!("parse settings: {error}"))
}

fn save_settings(path: &Path, settings: IdleSettings) -> Result<(), String> {
    let raw =
        serde_json::to_string(&settings).map_err(|error| format!("serialize settings: {error}"))?;
    crate::utils::write_file_atomic(path, raw.as_bytes(), true, None)
        .map_err(|error| format!("write settings: {error}"))
}

fn build_status_json(input: StatusInput) -> String {
    let suspend_seconds_left = seconds_left(input.next_suspend_at_ms, input.now_ms);
    serde_json::to_string(&json!({
        "managedBy": "quickshell",
        "dpmsOff": input.dpms_off,
        "displayOffTimeoutSec": clamp_timeout(input.display_off_timeout_sec),
        "displayOffSecondsLeft": if input.dpms_off { Some(0) } else { None },
        "suspendEnabled": input.suspend_enabled,
        "suspendTimeoutSec": clamp_timeout(input.suspend_timeout_sec),
        "suspendSecondsLeft": suspend_seconds_left,
        "sleepInhibited": input.sleep_inhibited,
        "ignoreLidEvents": input.ignore_lid_events,
    }))
    .unwrap_or_else(|_| "{}".to_owned())
}

fn seconds_left(target_ms: f64, now_ms: f64) -> i32 {
    if !target_ms.is_finite() || target_ms <= 0.0 {
        return 0;
    }
    ((target_ms - now_ms) / 1000.0).ceil().max(0.0) as i32
}

fn spawn_lid_inhibit_child() -> Result<Child, String> {
    Command::new("systemd-inhibit")
        .args([
            "--what=handle-lid-switch",
            "--who=Quickshell",
            "--why=Ignore lid close from Caffeine",
            "--mode=block",
            "sleep",
            "infinity",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| format!("start lid inhibitor: {error}"))
}

fn stop_lid_inhibit_child(child: &mut Option<Child>) {
    if let Some(mut child) = child.take() {
        let _ = child.kill();
        let _ = child.wait();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clamps_negative_timeouts() {
        let settings = IdleSettings {
            display_off_timeout_sec: -5,
            suspend_timeout_sec: -20,
            suspend_enabled: true,
            ignore_lid_events: true,
        }
        .clamped();

        assert_eq!(settings.display_off_timeout_sec, 0);
        assert_eq!(settings.suspend_timeout_sec, 0);
        assert!(settings.suspend_enabled);
        assert!(settings.ignore_lid_events);
    }

    #[test]
    fn builds_status_json_with_clamped_values_and_seconds_left() {
        let raw = build_status_json(StatusInput {
            dpms_off: false,
            display_off_timeout_sec: -1,
            suspend_enabled: true,
            suspend_timeout_sec: -10,
            next_suspend_at_ms: 12_300.0,
            sleep_inhibited: true,
            ignore_lid_events: false,
            now_ms: 10_000.0,
        });
        let status: serde_json::Value = serde_json::from_str(&raw).expect("status json");

        assert_eq!(status["managedBy"], "quickshell");
        assert_eq!(status["dpmsOff"], false);
        assert_eq!(status["displayOffTimeoutSec"], 0);
        assert!(status["displayOffSecondsLeft"].is_null());
        assert_eq!(status["suspendEnabled"], true);
        assert_eq!(status["suspendTimeoutSec"], 0);
        assert_eq!(status["suspendSecondsLeft"], 3);
        assert_eq!(status["sleepInhibited"], true);
        assert_eq!(status["ignoreLidEvents"], false);
    }
}
