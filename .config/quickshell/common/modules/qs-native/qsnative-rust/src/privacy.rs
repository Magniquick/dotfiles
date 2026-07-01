use core::pin::Pin;
use std::collections::BTreeSet;
use std::fs::OpenOptions;
use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

use chrono::Local;
use cxx_qt::{CxxQtThread, CxxQtType, Threading};
use cxx_qt_lib::QString;
use serde::Deserialize;

const CAMERA_RETRY_ATTEMPTS: i32 = 3;
const CAMERA_RETRY_INTERVAL: Duration = Duration::from_millis(150);
const INOTIFY_RESTART_INTERVAL: Duration = Duration::from_millis(1000);

#[derive(Default)]
pub struct PrivacyProviderRust {
    microphone_active: bool,
    camera_active: bool,
    screensharing_active: bool,
    any_privacy_active: bool,
    camera_device: QString,
    camera_open_seen: bool,
    camera_pending_confirmation: bool,
    probing_camera: bool,
    camera_holder_apps: QString,
    camera_holders_summary: QString,
    camera_activation_state: QString,
    camera_retry_attempt: i32,
    camera_degraded: bool,
    error: QString,
    debug: bool,
    privacy_stdout_logging: bool,
    privacy_file_logging: bool,
    camera_log_path: QString,
    started: bool,
}

#[derive(Debug, Clone, Default, Deserialize, PartialEq, Eq)]
struct PipewireNodeSnapshot {
    #[serde(default)]
    name: String,
    #[serde(default)]
    media_class: String,
    #[serde(default)]
    media_name: String,
    #[serde(default)]
    application_name: String,
    #[serde(default)]
    stream_is_live: String,
    #[serde(default)]
    state: String,
    #[serde(default)]
    audio_muted: bool,
    #[serde(default)]
    audio_in_stream: bool,
    #[serde(default)]
    video_source: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct PipewirePrivacyState {
    microphone_active: bool,
    screensharing_active: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct CameraHolderSnapshot {
    hits: Vec<String>,
    apps: Vec<String>,
}

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    impl cxx_qt::Threading for PrivacyProvider {}

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qobject]
        #[qproperty(bool, microphone_active, cxx_name = "microphone_active")]
        #[qproperty(bool, camera_active, cxx_name = "camera_active")]
        #[qproperty(bool, screensharing_active, cxx_name = "screensharing_active")]
        #[qproperty(bool, any_privacy_active, cxx_name = "any_privacy_active")]
        #[qproperty(QString, camera_device, cxx_name = "camera_device")]
        #[qproperty(bool, camera_open_seen, cxx_name = "camera_open_seen")]
        #[qproperty(
            bool,
            camera_pending_confirmation,
            cxx_name = "camera_pending_confirmation"
        )]
        #[qproperty(bool, probing_camera, cxx_name = "probing_camera")]
        #[qproperty(QString, camera_holder_apps, cxx_name = "camera_holder_apps")]
        #[qproperty(QString, camera_holders_summary, cxx_name = "camera_holders_summary")]
        #[qproperty(QString, camera_activation_state, cxx_name = "camera_activation_state")]
        #[qproperty(i32, camera_retry_attempt, cxx_name = "camera_retry_attempt")]
        #[qproperty(bool, camera_degraded, cxx_name = "camera_degraded")]
        #[qproperty(QString, error)]
        #[qproperty(bool, debug)]
        #[qproperty(bool, privacy_stdout_logging, cxx_name = "privacy_stdout_logging")]
        #[qproperty(bool, privacy_file_logging, cxx_name = "privacy_file_logging")]
        #[qproperty(QString, camera_log_path, cxx_name = "camera_log_path")]
        type PrivacyProvider = super::PrivacyProviderRust;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qinvokable]
        fn start(self: Pin<&mut PrivacyProvider>);

        #[qinvokable]
        #[cxx_name = "refreshCamera"]
        fn refresh_camera(self: Pin<&mut PrivacyProvider>) -> bool;

        #[qinvokable]
        #[cxx_name = "updatePipewireSnapshot"]
        fn update_pipewire_snapshot(
            self: Pin<&mut PrivacyProvider>,
            snapshot_json: &QString,
        ) -> bool;
    }

    impl cxx_qt::Initialize for PrivacyProvider {}
}

impl cxx_qt::Initialize for ffi::PrivacyProvider {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut()
            .set_camera_device(QString::from("/dev/video0"));
        self.as_mut()
            .set_camera_activation_state(QString::from("inactive"));
        self.as_mut()
            .set_camera_log_path(QString::from("/tmp/quickshell-privacy-camera.log"));
        self.as_mut().set_privacy_stdout_logging(true);
        self.as_mut().set_privacy_file_logging(true);
    }
}

impl ffi::PrivacyProvider {
    pub fn start(mut self: Pin<&mut Self>) {
        if self.as_ref().rust().started {
            self.refresh_camera();
            return;
        }

        let device = self.camera_device().to_string();
        let qt_thread = self.as_ref().qt_thread();
        self.as_mut().rust_mut().as_mut().get_mut().started = true;

        thread::spawn(move || watch_camera_device(device, qt_thread));
        self.refresh_camera();
    }

    pub fn refresh_camera(mut self: Pin<&mut Self>) -> bool {
        let device = self.camera_device().to_string();
        let qt_thread = self.as_ref().qt_thread();
        let debug = *self.debug();
        self.as_mut().set_camera_pending_confirmation(true);
        self.as_mut().set_probing_camera(true);
        self.as_mut()
            .set_camera_activation_state(QString::from("pending"));

        thread::spawn(move || {
            let result = probe_camera_holders_with_retries(&device, debug);
            let _ = qt_thread.queue(move |mut provider| {
                provider.as_mut().apply_camera_probe(result, true);
            });
        });

        true
    }

    pub fn update_pipewire_snapshot(mut self: Pin<&mut Self>, snapshot_json: &QString) -> bool {
        let nodes =
            match serde_json::from_str::<Vec<PipewireNodeSnapshot>>(&snapshot_json.to_string()) {
                Ok(nodes) => nodes,
                Err(error) => {
                    self.as_mut().set_error(QString::from(
                        format!("pipewire snapshot: {error}").as_str(),
                    ));
                    return false;
                }
            };

        let state = classify_pipewire_nodes(&nodes);
        self.as_mut().set_microphone_active(state.microphone_active);
        self.as_mut()
            .set_screensharing_active(state.screensharing_active);
        self.as_mut().set_error(QString::default());
        self.as_mut().refresh_any_privacy_active();
        true
    }

    fn refresh_any_privacy_active(mut self: Pin<&mut Self>) {
        let active =
            *self.microphone_active() || *self.camera_active() || *self.screensharing_active();
        self.as_mut().set_any_privacy_active(active);
    }

    fn on_camera_event(mut self: Pin<&mut Self>, open_seen: bool) {
        self.as_mut().set_camera_degraded(false);
        self.as_mut().set_camera_open_seen(open_seen);
        self.as_mut().set_camera_pending_confirmation(open_seen);
        self.as_mut().set_camera_retry_attempt(0);
        self.as_mut().set_probing_camera(true);
        self.as_mut()
            .set_camera_activation_state(QString::from("pending"));

        let device = self.camera_device().to_string();
        let qt_thread = self.as_ref().qt_thread();
        let debug = *self.debug();
        thread::spawn(move || {
            let result = if open_seen {
                probe_camera_holders_with_retries(&device, debug)
            } else {
                probe_camera_holders(&device)
            };
            let _ = qt_thread.queue(move |mut provider| {
                provider.as_mut().apply_camera_probe(result, open_seen);
            });
        });
    }

    fn on_camera_monitor_exited(mut self: Pin<&mut Self>, error: String) {
        self.as_mut().set_camera_degraded(true);
        self.as_mut().set_camera_open_seen(false);
        self.as_mut().set_camera_pending_confirmation(false);
        self.as_mut().set_probing_camera(false);
        self.as_mut().set_camera_retry_attempt(0);
        self.as_mut().set_error(QString::from(error.as_str()));
        self.as_mut()
            .apply_camera_holder_state(CameraHolderSnapshot::default());
    }

    fn apply_camera_probe(
        mut self: Pin<&mut Self>,
        snapshot: CameraHolderSnapshot,
        from_open: bool,
    ) {
        let retry_attempt = if from_open && snapshot.hits.is_empty() {
            CAMERA_RETRY_ATTEMPTS
        } else {
            0
        };
        self.as_mut().set_probing_camera(false);
        self.as_mut().set_camera_pending_confirmation(false);
        self.as_mut().set_camera_retry_attempt(retry_attempt);
        self.as_mut().apply_camera_holder_state(snapshot);
    }

    fn apply_camera_holder_state(mut self: Pin<&mut Self>, snapshot: CameraHolderSnapshot) {
        let was_active = *self.camera_active();
        let holders_summary = snapshot.hits.join(",");
        let apps_summary = snapshot.apps.join(", ");
        let camera_active = !snapshot.apps.is_empty();
        let activation = if camera_active {
            "confirmed"
        } else if *self.camera_pending_confirmation() || *self.probing_camera() {
            "pending"
        } else {
            "inactive"
        };

        self.as_mut()
            .set_camera_holder_apps(QString::from(apps_summary.as_str()));
        self.as_mut()
            .set_camera_holders_summary(QString::from(holders_summary.as_str()));
        self.as_mut().set_camera_active(camera_active);
        self.as_mut()
            .set_camera_activation_state(QString::from(activation));
        self.as_mut().refresh_any_privacy_active();

        if was_active != camera_active {
            let line = camera_log_line(self.as_ref(), &snapshot);
            self.as_mut().persist_camera_log_line(line);
        }
    }

    fn persist_camera_log_line(self: Pin<&mut Self>, line: String) {
        if *self.privacy_stdout_logging() {
            println!("{line}");
        }
        if !*self.privacy_file_logging() {
            return;
        }

        let path = self.camera_log_path().to_string();
        if path.trim().is_empty() {
            return;
        }

        if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
            let _ = writeln!(file, "{line}");
        }
    }
}

fn watch_camera_device(device: String, qt_thread: CxxQtThread<ffi::PrivacyProvider>) {
    loop {
        let mut child = match Command::new("inotifywait")
            .args(["-m", "-e", "open", "-e", "close", device.as_str()])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
        {
            Ok(child) => child,
            Err(error) => {
                let message = format!("inotifywait: {error}");
                let _ = qt_thread.queue(move |mut provider| {
                    provider.as_mut().on_camera_monitor_exited(message);
                });
                thread::sleep(INOTIFY_RESTART_INTERVAL);
                continue;
            }
        };

        if let Some(stdout) = child.stdout.take() {
            for line in BufReader::new(stdout).lines().map_while(Result::ok) {
                let open_seen = if line.contains("OPEN") {
                    Some(true)
                } else if line.contains("CLOSE") {
                    Some(false)
                } else {
                    None
                };
                if let Some(open_seen) = open_seen {
                    let _ = qt_thread.queue(move |mut provider| {
                        provider.as_mut().on_camera_event(open_seen);
                    });
                }
            }
        }

        let status = child.wait();
        let message = match status {
            Ok(status) => format!("inotifywait exited {status}"),
            Err(error) => format!("inotifywait wait: {error}"),
        };
        let _ = qt_thread.queue(move |mut provider| {
            provider.as_mut().on_camera_monitor_exited(message);
        });
        thread::sleep(INOTIFY_RESTART_INTERVAL);
    }
}

fn classify_pipewire_nodes(nodes: &[PipewireNodeSnapshot]) -> PipewirePrivacyState {
    let mut state = PipewirePrivacyState::default();

    for node in nodes {
        if node.audio_in_stream && !looks_like_system_virtual_mic(node) && !node.audio_muted {
            state.microphone_active = true;
        }

        if node.video_source && looks_like_screencast(node) {
            state.screensharing_active = true;
        }

        if node.media_class == "Stream/Input/Audio" {
            let media_name = node.media_name.to_lowercase();
            let app_name = node.application_name.to_lowercase();
            let looks_like_screen_audio =
                media_name.contains("desktop") || app_name.contains("screen") || app_name == "obs";
            if looks_like_screen_audio && node.stream_is_live == "true" && !node.audio_muted {
                state.screensharing_active = true;
            }
        }
    }

    state
}

fn looks_like_system_virtual_mic(node: &PipewireNodeSnapshot) -> bool {
    let combined = format!(
        "{} {} {}",
        node.name.to_lowercase(),
        node.media_name.to_lowercase(),
        node.application_name.to_lowercase()
    );
    ["cava", "monitor", "system"]
        .iter()
        .any(|needle| combined.contains(needle))
}

fn looks_like_screencast(node: &PipewireNodeSnapshot) -> bool {
    let combined = format!(
        "{} {}",
        node.application_name.to_lowercase(),
        node.name.to_lowercase()
    );
    [
        "xdg-desktop-portal",
        "xdpw",
        "screencast",
        "screen",
        "gnome shell",
        "kwin",
        "obs",
    ]
    .iter()
    .any(|needle| combined.contains(needle))
}

fn probe_camera_holders_with_retries(device: &str, debug: bool) -> CameraHolderSnapshot {
    for attempt in 0..=CAMERA_RETRY_ATTEMPTS {
        let snapshot = probe_camera_holders(device);
        if !snapshot.hits.is_empty() || attempt == CAMERA_RETRY_ATTEMPTS {
            return snapshot;
        }
        if debug {
            eprintln!(
                "[PrivacyService] {device} holders none; retry {attempt}/{CAMERA_RETRY_ATTEMPTS}"
            );
        }
        thread::sleep(CAMERA_RETRY_INTERVAL);
    }
    unreachable!("loop always returns on the final attempt")
}

fn probe_camera_holders(device: &str) -> CameraHolderSnapshot {
    let fuser = Command::new("fuser").arg(device).output();
    let raw = match fuser {
        Ok(output) => {
            let mut raw = String::from_utf8_lossy(&output.stdout).to_string();
            raw.push('\n');
            raw.push_str(&String::from_utf8_lossy(&output.stderr));
            raw
        }
        Err(_) => String::new(),
    };
    let pids = extract_pids(&raw);
    if pids.is_empty() {
        return CameraHolderSnapshot::default();
    }

    let pid_arg = pids
        .iter()
        .map(u32::to_string)
        .collect::<Vec<_>>()
        .join(",");
    let ps = Command::new("ps")
        .args(["-o", "pid=,comm=", "-p", pid_arg.as_str()])
        .output();
    match ps {
        Ok(output) => parse_holder_details(&String::from_utf8_lossy(&output.stdout)),
        Err(_) => CameraHolderSnapshot::default(),
    }
}

fn extract_pids(raw: &str) -> Vec<u32> {
    let mut seen = BTreeSet::new();
    raw.lines()
        .map(|line| line.split_once(':').map_or(line, |(_, rest)| rest))
        .flat_map(|line| line.split(|ch: char| !ch.is_ascii_digit()))
        .filter_map(|part| part.parse::<u32>().ok())
        .filter(|pid| seen.insert(*pid))
        .collect()
}

fn parse_holder_details(raw: &str) -> CameraHolderSnapshot {
    let mut hits = Vec::new();
    let mut apps = Vec::new();

    for line in raw.lines().map(str::trim).filter(|line| !line.is_empty()) {
        if line.starts_with("PID") {
            continue;
        }
        let Some((pid, command)) = line.split_once(char::is_whitespace) else {
            continue;
        };
        let command = command.trim();
        if pid.parse::<u32>().is_ok() && !command.is_empty() {
            hits.push(format!("{pid}:{command}"));
            if !apps.iter().any(|app| app == command) {
                apps.push(command.to_owned());
            }
        }
    }

    CameraHolderSnapshot { hits, apps }
}

fn camera_log_line(
    provider: Pin<&ffi::PrivacyProvider>,
    snapshot: &CameraHolderSnapshot,
) -> String {
    let holder_count = snapshot.apps.len();
    let holders = if snapshot.hits.is_empty() {
        "none".to_owned()
    } else {
        snapshot.hits.join(",")
    };
    let apps = if snapshot.apps.is_empty() {
        String::new()
    } else {
        format!(" camera_apps={}", snapshot.apps.join(", "))
    };

    format!(
        "[PrivacyService][{}] camera {}; device={} open_seen={} activation={} holder_count={} holders={}{}",
        Local::now().to_rfc3339(),
        if *provider.camera_active() { "ACTIVE" } else { "INACTIVE" },
        provider.camera_device(),
        if *provider.camera_open_seen() { "yes" } else { "no" },
        provider.camera_activation_state(),
        holder_count,
        holders,
        apps
    )
}

#[cfg(test)]
mod tests {
    use super::{
        classify_pipewire_nodes, extract_pids, parse_holder_details, PipewireNodeSnapshot,
    };

    #[test]
    fn classifies_real_mic_and_ignores_system_monitor() {
        let state = classify_pipewire_nodes(&[
            PipewireNodeSnapshot {
                name: "cava monitor".to_owned(),
                audio_in_stream: true,
                ..PipewireNodeSnapshot::default()
            },
            PipewireNodeSnapshot {
                application_name: "Chromium".to_owned(),
                audio_in_stream: true,
                ..PipewireNodeSnapshot::default()
            },
        ]);

        assert!(state.microphone_active);
        assert!(!state.screensharing_active);
    }

    #[test]
    fn classifies_screencast_video_and_audio() {
        let state = classify_pipewire_nodes(&[
            PipewireNodeSnapshot {
                name: "xdpw screencast".to_owned(),
                video_source: true,
                ..PipewireNodeSnapshot::default()
            },
            PipewireNodeSnapshot {
                media_class: "Stream/Input/Audio".to_owned(),
                media_name: "Desktop audio".to_owned(),
                stream_is_live: "true".to_owned(),
                ..PipewireNodeSnapshot::default()
            },
        ]);

        assert!(state.screensharing_active);
    }

    #[test]
    fn extracts_unique_pids_from_fuser_output() {
        assert_eq!(extract_pids("/dev/video0: 123 456 123"), vec![123, 456]);
    }

    #[test]
    fn parses_ps_holder_details() {
        let parsed = parse_holder_details(" 123 firefox\n 456 wireplumber\n");

        assert_eq!(parsed.hits, vec!["123:firefox", "456:wireplumber"]);
        assert_eq!(parsed.apps, vec!["firefox", "wireplumber"]);
    }
}
