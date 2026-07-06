//! Idle/DPMS/suspend settings provider (`IdleProvider`).
//!
//! Plain synchronous provider over an opaque handle: settings persist to a
//! JSON file, `statusJson` renders an IPC status payload, and a fire-and-forget
//! `systemd-inhibit` child blocks the lid switch while lid events are ignored.
//! No worker threads or cross-thread callbacks are involved.

use std::ffi::CString;
use std::os::raw::{c_char, c_void};
use std::path::Path;
use std::process::{Child, Command, Stdio};

use serde::{Deserialize, Serialize};

use crate::ffi::{self, c_string, QsNativeBytes};

const DEFAULT_DISPLAY_OFF_TIMEOUT_SEC: i32 = 10;
const DEFAULT_SUSPEND_TIMEOUT_SEC: i32 = 1800;

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

/// Opaque per-instance handle owned by the C++ `QsNativeIdle` `QObject`.
pub struct IdleHandle {
    settings: IdleSettings,
    lid_inhibited: bool,
    error: String,
    lid_inhibit_child: Option<Child>,
}

impl IdleHandle {
    fn new() -> Self {
        Self {
            settings: IdleSettings::default(),
            lid_inhibited: false,
            error: String::new(),
            lid_inhibit_child: None,
        }
    }
}

/// Zero-copy snapshot of the QML-facing properties. The `error` `*const c_char`
/// borrows a `CString` that lives on the caller's stack **only for the duration
/// of the callback**; C++ must copy it (`QString::fromUtf8`) synchronously and
/// must not retain the pointer. Fields map 1:1 to `IdleProvider` QML properties.
#[repr(C)]
pub struct IdleSnapshotC {
    pub display_off_timeout_sec: i32,
    pub suspend_timeout_sec: i32,
    pub suspend_enabled: bool,
    pub ignore_lid_events: bool,
    pub lid_inhibited: bool,
    pub error: *const c_char,
}

/// Delivers an `IdleSnapshotC` (borrowed for the call only) to the C++ side.
pub type IdleSnapshotFn = unsafe extern "C" fn(*mut c_void, *const IdleSnapshotC);

/// Builds a `CString`, falling back to empty on an interior NUL.
fn cstr(value: &str) -> CString {
    CString::new(value).unwrap_or_default()
}

impl Drop for IdleHandle {
    fn drop(&mut self) {
        stop_lid_inhibit_child(&mut self.lid_inhibit_child);
    }
}

#[no_mangle]
pub extern "C" fn QsNative_Idle_New() -> *mut IdleHandle {
    Box::into_raw(Box::new(IdleHandle::new()))
}

/// # Safety
/// `handle` must be null or a pointer from `QsNative_Idle_New` not yet freed.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Idle_Delete(handle: *mut IdleHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Delivers the current property snapshot as a zero-copy `IdleSnapshotC` via
/// `cb`. Synchronous: `cb` fires on the caller's thread before this returns.
///
/// # Safety
/// `handle` must be valid; `ctx`/`cb` must remain valid until `cb` fires.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Idle_Snapshot(
    handle: *mut IdleHandle,
    ctx: *mut c_void,
    cb: IdleSnapshotFn,
) {
    if handle.is_null() {
        return;
    }
    let handle = &*handle;
    // The CString must outlive the callback; keep it bound in this scope.
    let error = cstr(&handle.error);
    let c = IdleSnapshotC {
        display_off_timeout_sec: handle.settings.display_off_timeout_sec,
        suspend_timeout_sec: handle.settings.suspend_timeout_sec,
        suspend_enabled: handle.settings.suspend_enabled,
        ignore_lid_events: handle.settings.ignore_lid_events,
        lid_inhibited: handle.lid_inhibited,
        error: error.as_ptr(),
    };
    cb(ctx, &raw const c);
}

/// Loads settings from `path`; on failure applies defaults and records an error.
///
/// # Safety
/// `handle` must be valid; `path` must be null or a valid C string.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Idle_LoadSettings(
    handle: *mut IdleHandle,
    path: *const c_char,
) -> bool {
    if handle.is_null() {
        return false;
    }
    let handle = &mut *handle;
    match load_settings(Path::new(&c_string(path))) {
        Ok(settings) => {
            handle.settings = settings;
            handle.error.clear();
            true
        }
        Err(error) => {
            handle.settings = IdleSettings::default();
            handle.error = error;
            false
        }
    }
}

/// Clamps then applies the given settings and writes them atomically to `path`.
///
/// # Safety
/// `handle` must be valid; `path` must be null or a valid C string.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Idle_SaveSettings(
    handle: *mut IdleHandle,
    path: *const c_char,
    display_off_timeout_sec: i32,
    suspend_timeout_sec: i32,
    suspend_enabled: bool,
    ignore_lid_events: bool,
) -> bool {
    if handle.is_null() {
        return false;
    }
    let handle = &mut *handle;
    let settings = IdleSettings {
        display_off_timeout_sec,
        suspend_timeout_sec,
        suspend_enabled,
        ignore_lid_events,
    }
    .clamped();

    handle.settings = settings;
    match save_settings(Path::new(&c_string(path)), settings) {
        Ok(()) => {
            handle.error.clear();
            true
        }
        Err(error) => {
            handle.error = error;
            false
        }
    }
}

/// Pure `max(0)` clamp of a timeout value; no handle state involved.
#[no_mangle]
pub extern "C" fn QsNative_Idle_ClampTimeout(seconds: i32) -> i32 {
    clamp_timeout(seconds)
}

/// Builds the `idle` IPC status payload as a CBOR byte buffer
/// (release with `QsNative_FreeBytes`).
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Idle_StatusCbor(
    handle: *mut IdleHandle,
    dpms_off: bool,
    next_suspend_at_ms: f64,
    sleep_inhibited: bool,
    now_ms: f64,
) -> QsNativeBytes {
    if handle.is_null() {
        #[expect(
            clippy::zero_sized_map_values,
            reason = "an empty map with a unit value type is only used to serialize an \
                      empty CBOR object for the null-handle fallback; no values are ever inserted"
        )]
        let empty = std::collections::BTreeMap::<String, ()>::new();
        return ffi::into_cbor(&empty);
    }
    let settings = (*handle).settings;
    ffi::into_cbor(&build_status(StatusInput {
        dpms_off,
        display_off_timeout_sec: settings.display_off_timeout_sec,
        suspend_enabled: settings.suspend_enabled,
        suspend_timeout_sec: settings.suspend_timeout_sec,
        next_suspend_at_ms,
        sleep_inhibited,
        ignore_lid_events: settings.ignore_lid_events,
        now_ms,
    }))
}

/// Spawns or kills the `systemd-inhibit` lid-switch blocker and updates the
/// `lidInhibited`/`error` state.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Idle_SyncLidInhibitProcess(
    handle: *mut IdleHandle,
    inhibited: bool,
) -> bool {
    if handle.is_null() {
        return false;
    }
    let handle = &mut *handle;

    if inhibited {
        let should_spawn = match handle.lid_inhibit_child {
            Some(ref mut child) => !matches!(child.try_wait(), Ok(None)),
            None => true,
        };

        if should_spawn {
            match spawn_lid_inhibit_child() {
                Ok(child) => handle.lid_inhibit_child = Some(child),
                Err(error) => {
                    handle.lid_inhibited = false;
                    handle.error = error;
                    return false;
                }
            }
        }
        handle.lid_inhibited = true;
        handle.error.clear();
        return true;
    }

    stop_lid_inhibit_child(&mut handle.lid_inhibit_child);
    handle.lid_inhibited = false;
    handle.error.clear();
    true
}

#[derive(Debug, Clone, Copy)]
#[expect(
    clippy::struct_excessive_bools,
    reason = "flat parameter bag mirroring the independent idle/DPMS/suspend inputs \
              passed from FFI; each bool is a distinct status flag, not a state machine"
)]
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

    let raw = std::fs::read_to_string(path).map_err(|error| format!("read settings: {error}"))?;
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

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
#[expect(
    clippy::struct_excessive_bools,
    reason = "flat status payload mirroring the independent idle/DPMS/suspend fields \
              serialized to the IPC status output; each bool is a distinct status flag, \
              not a state machine"
)]
struct StatusOutput {
    managed_by: &'static str,
    dpms_off: bool,
    display_off_timeout_sec: i32,
    display_off_seconds_left: Option<i32>,
    suspend_enabled: bool,
    suspend_timeout_sec: i32,
    suspend_seconds_left: i32,
    sleep_inhibited: bool,
    ignore_lid_events: bool,
}

fn build_status(input: StatusInput) -> StatusOutput {
    let suspend_seconds_left = seconds_left(input.next_suspend_at_ms, input.now_ms);
    StatusOutput {
        managed_by: "quickshell",
        dpms_off: input.dpms_off,
        display_off_timeout_sec: clamp_timeout(input.display_off_timeout_sec),
        display_off_seconds_left: if input.dpms_off { Some(0) } else { None },
        suspend_enabled: input.suspend_enabled,
        suspend_timeout_sec: clamp_timeout(input.suspend_timeout_sec),
        suspend_seconds_left,
        sleep_inhibited: input.sleep_inhibited,
        ignore_lid_events: input.ignore_lid_events,
    }
}

#[expect(
    clippy::cast_possible_truncation,
    reason = "seconds-left countdown; value is ceil()+max(0.0) clamped and always \
              a small non-negative second count that fits in i32"
)]
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
        let status = build_status(StatusInput {
            dpms_off: false,
            display_off_timeout_sec: -1,
            suspend_enabled: true,
            suspend_timeout_sec: -10,
            next_suspend_at_ms: 12_300.0,
            sleep_inhibited: true,
            ignore_lid_events: false,
            now_ms: 10_000.0,
        });

        assert_eq!(status.managed_by, "quickshell");
        assert!(!status.dpms_off);
        assert_eq!(status.display_off_timeout_sec, 0);
        assert!(status.display_off_seconds_left.is_none());
        assert!(status.suspend_enabled);
        assert_eq!(status.suspend_timeout_sec, 0);
        assert_eq!(status.suspend_seconds_left, 3);
        assert!(status.sleep_inhibited);
        assert!(!status.ignore_lid_events);
    }
}
