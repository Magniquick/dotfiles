//! Privacy provider: camera-ownership watching (inotifywait + fuser + ps) and
//! `PipeWire` node classification for the `PrivacyProvider` QML type.
//!
//! Rust owns the worker threads and the pure classification/probe logic; the
//! hand-written C++ `QObject` (`cpp/QsNativePrivacy.{h,cpp}`) owns every Qt
//! property and all state-transition/logging behaviour on the Qt thread.

use std::collections::BTreeSet;
use std::io::{BufRead, BufReader};
use std::os::raw::{c_char, c_void};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::ffi::{self, c_string, emit_snapshot, QsNativeBytes, QsNativeUpdateFn};

const CAMERA_RETRY_ATTEMPTS: i32 = 3;
const CAMERA_RETRY_INTERVAL: Duration = Duration::from_millis(150);
const INOTIFY_RESTART_INTERVAL: Duration = Duration::from_secs(1);

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

/// CBOR outbound result of [`QsNative_Privacy_ClassifyPipewire`], shaped to match
/// the previous JSON object exactly: success carries `microphone_active` /
/// `screensharing_active` and omits `error`; failure carries `error` and omits
/// the two booleans.
#[derive(Debug, Clone, Serialize)]
struct PipewireClassifyResult {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    microphone_active: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    screensharing_active: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

/// Opaque per-instance handle owned by the C++ `QsNativePrivacy` `QObject`.
///
/// `alive` is shared with the persistent inotify watcher and every probe worker
/// so they stop delivering callbacks once the `QObject` has been destroyed.
pub struct PrivacyHandle {
    alive: Arc<AtomicBool>,
}

#[no_mangle]
pub extern "C" fn QsNative_Privacy_New() -> *mut PrivacyHandle {
    Box::into_raw(Box::new(PrivacyHandle {
        alive: Arc::new(AtomicBool::new(true)),
    }))
}

/// # Safety
/// `handle` must be null or a pointer from `QsNative_Privacy_New` not yet freed.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Privacy_Delete(handle: *mut PrivacyHandle) {
    if !handle.is_null() {
        (*handle).alive.store(false, Ordering::SeqCst);
        drop(Box::from_raw(handle));
    }
}

/// Spawns the persistent inotify camera watcher. Delivers `camera_event` and
/// `monitor_exited` JSON events via `cb`.
///
/// # Safety
/// `handle`/`device` must be valid; `ctx`/`cb` must stay valid for the `QObject`
/// lifetime (guarded by the handle's alive flag).
#[no_mangle]
pub unsafe extern "C" fn QsNative_Privacy_StartWatch(
    handle: *mut PrivacyHandle,
    ctx: *mut c_void,
    cb: QsNativeUpdateFn,
    device: *const c_char,
) {
    if handle.is_null() {
        return;
    }
    let alive = (*handle).alive.clone();
    let device = c_string(device);
    let ctx = ctx as usize;
    thread::spawn(move || watch_camera_device(&device, &alive, ctx, cb));
}

/// Probes camera holders on a worker thread and delivers a `probe` JSON event.
/// `from_open` selects the retry policy (used for OPEN events / explicit
/// refreshes) and is echoed back so the C++ side can derive the retry counter.
///
/// # Safety
/// `handle`/`device` must be valid; `ctx`/`cb` must stay valid until `cb` fires.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Privacy_Probe(
    handle: *mut PrivacyHandle,
    ctx: *mut c_void,
    cb: QsNativeUpdateFn,
    device: *const c_char,
    from_open: bool,
    debug: bool,
) {
    if handle.is_null() {
        return;
    }
    let alive = (*handle).alive.clone();
    let device = c_string(device);
    let ctx = ctx as usize;
    thread::spawn(move || {
        let snapshot = if from_open {
            probe_camera_holders_with_retries(&device, debug)
        } else {
            probe_camera_holders(&device)
        };
        let json = serde_json::json!({
            "type": "probe",
            "from_open": from_open,
            "hits": snapshot.hits,
            "apps": snapshot.apps,
        })
        .to_string();
        emit_event(&alive, ctx, cb, json);
    });
}

/// Classifies a CBOR array of `PipeWire` nodes. Returns an owned CBOR object:
/// `{ok: true, microphone_active, screensharing_active}` on success or
/// `{ok: false, error}` on parse failure. Free with `QsNative_FreeBytes`.
///
/// # Safety
/// `(ptr, len)` must describe a readable CBOR byte range for the call, or `ptr`
/// null.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Privacy_ClassifyPipewire(
    ptr: *const u8,
    len: usize,
) -> QsNativeBytes {
    let result = match ffi::from_cbor::<Vec<PipewireNodeSnapshot>>(ptr, len) {
        Some(nodes) => {
            let state = classify_pipewire_nodes(&nodes);
            PipewireClassifyResult {
                ok: true,
                microphone_active: Some(state.microphone_active),
                screensharing_active: Some(state.screensharing_active),
                error: None,
            }
        }
        None => PipewireClassifyResult {
            ok: false,
            microphone_active: None,
            screensharing_active: None,
            error: Some("pipewire snapshot: invalid cbor".to_owned()),
        },
    };
    ffi::into_cbor(&result)
}

fn emit_event(alive: &Arc<AtomicBool>, ctx: usize, cb: QsNativeUpdateFn, json: String) {
    if !alive.load(Ordering::SeqCst) {
        return;
    }
    unsafe { emit_snapshot(cb, ctx as *mut c_void, json) };
}

fn camera_event_json(open_seen: bool) -> String {
    serde_json::json!({ "type": "camera_event", "open_seen": open_seen }).to_string()
}

fn monitor_exited_json(error: &str) -> String {
    serde_json::json!({ "type": "monitor_exited", "error": error }).to_string()
}

fn watch_camera_device(device: &str, alive: &Arc<AtomicBool>, ctx: usize, cb: QsNativeUpdateFn) {
    while alive.load(Ordering::SeqCst) {
        let mut child = match Command::new("inotifywait")
            .args(["-m", "-e", "open", "-e", "close", device])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
        {
            Ok(child) => child,
            Err(error) => {
                emit_event(
                    alive,
                    ctx,
                    cb,
                    monitor_exited_json(&format!("inotifywait: {error}")),
                );
                thread::sleep(INOTIFY_RESTART_INTERVAL);
                continue;
            }
        };

        if let Some(stdout) = child.stdout.take() {
            for line in BufReader::new(stdout).lines().map_while(Result::ok) {
                if !alive.load(Ordering::SeqCst) {
                    let _ = child.kill();
                    return;
                }
                let open_seen = if line.contains("OPEN") {
                    Some(true)
                } else if line.contains("CLOSE") {
                    Some(false)
                } else {
                    None
                };
                if let Some(open_seen) = open_seen {
                    emit_event(alive, ctx, cb, camera_event_json(open_seen));
                }
            }
        }

        let status = child.wait();
        let message = match status {
            Ok(status) => format!("inotifywait exited {status}"),
            Err(error) => format!("inotifywait wait: {error}"),
        };
        emit_event(alive, ctx, cb, monitor_exited_json(&message));
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
