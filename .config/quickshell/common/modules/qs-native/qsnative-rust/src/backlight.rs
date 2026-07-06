//! `BacklightProvider` backend as a plain `extern "C"` surface over an opaque
//! handle. The C++ Qt glue (`cpp/QsNativeBacklight.{h,cpp}`) owns the `QObject` and
//! marshals worker-thread updates back onto the Qt thread.
//!
//! Two threaded paths feed the UI:
//! * a `notify` file watcher on the sysfs `.../brightness` file auto-refreshes the
//!   internal-backlight scalar state (delivered as a zero-copy `BacklightSnapshotC`
//!   `#[repr(C)]` struct; the synchronous `refresh`/`setBrightness` invokables
//!   push the same struct through the same callback);
//! * `ddcutil` subprocess calls (detect / getvcp / setvcp) run on short-lived
//!   worker threads, mutate the per-connector DDC map behind an `Arc<Mutex<…>>`,
//!   then fire a version-bump callback so QML re-queries the `ddc*` invokables.

use std::collections::HashMap;
use std::ffi::CString;
use std::os::raw::{c_char, c_void};
use std::path::PathBuf;
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::thread;

use blight::{Device, ErrorKind, Light};
use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};

use crate::ffi::{c_string, emit_snapshot, into_c_string, QsNativeUpdateFn};

#[derive(Debug, Clone, PartialEq, Eq)]
struct BacklightState {
    available: bool,
    brightness_percent: i32,
    device: String,
    error: String,
}

/// Zero-copy scalar-state snapshot handed to the C++ side. The `*const c_char`
/// fields borrow `CString`s that live on the worker/caller stack **only for the
/// duration of the callback**; C++ must copy them (`QString::fromUtf8`)
/// synchronously and must not retain the pointers. Fields map 1:1 to the
/// `BacklightProvider` scalar QML properties.
#[repr(C)]
pub struct BacklightSnapshotC {
    pub available: bool,
    pub brightness_percent: i32,
    pub device: *const c_char,
    pub error: *const c_char,
}

/// Delivers a `BacklightSnapshotC` (borrowed for the call only) to the C++ side.
pub type BacklightSnapshotFn = unsafe extern "C" fn(*mut c_void, *const BacklightSnapshotC);

/// Builds a `CString`, falling back to empty on an interior NUL.
fn cstr(value: &str) -> CString {
    CString::new(value).unwrap_or_default()
}

/// Binds `state`'s strings as `CString`s in this scope so the borrowed
/// `BacklightSnapshotC` pointers stay valid for the whole `cb` call.
///
/// # Safety
/// `cb`/`ctx` must be valid for the duration of the call.
unsafe fn emit_backlight_state(cb: BacklightSnapshotFn, ctx: *mut c_void, state: &BacklightState) {
    let device = cstr(&state.device);
    let error = cstr(&state.error);
    let c = BacklightSnapshotC {
        available: state.available,
        brightness_percent: state.brightness_percent,
        device: device.as_ptr(),
        error: error.as_ptr(),
    };
    cb(ctx, &raw const c);
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct DdcDisplay {
    bus: String,
    current: Option<i32>,
    max: Option<i32>,
    error: String,
}

/// Per-instance DDC state; shared with worker threads via `Arc<Mutex<…>>`.
struct BacklightInner {
    ddc_displays: HashMap<String, DdcDisplay>,
}

/// Live sysfs brightness watcher; dropping it stops/joins the watch thread.
struct BacklightMonitor {
    _watcher: RecommendedWatcher,
    path: PathBuf,
}

/// Opaque per-instance handle owned by the C++ `QsNativeBacklight` `QObject`.
pub struct BacklightHandle {
    inner: Arc<Mutex<BacklightInner>>,
    monitor: Option<BacklightMonitor>,
}

#[no_mangle]
pub extern "C" fn QsNative_Backlight_New() -> *mut BacklightHandle {
    Box::into_raw(Box::new(BacklightHandle {
        inner: Arc::new(Mutex::new(BacklightInner {
            ddc_displays: HashMap::new(),
        })),
        monitor: None,
    }))
}

/// # Safety
/// `handle` must be null or a pointer from `QsNative_Backlight_New` not yet freed.
/// Dropping the handle drops the watcher, which stops the watch thread cleanly.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Backlight_Delete(handle: *mut BacklightHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// True when the `ddcutil` binary is on `PATH` and executable. Pure PATH scan;
/// used to prime `ddcutil_available` during C++ construction (before `start()`).
#[no_mangle]
pub extern "C" fn QsNative_Backlight_DdcutilAvailable() -> bool {
    ddcutil_available()
}

/// Reads the internal backlight synchronously and delivers its state
/// (`available`, `brightness_percent`, `device`, `error`) through `cb` as a
/// borrowed `BacklightSnapshotC`. `cb` fires once, synchronously, before return.
///
/// # Safety
/// `ctx`/`cb` must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Backlight_Refresh(ctx: *mut c_void, cb: BacklightSnapshotFn) {
    emit_backlight_state(cb, ctx, &read_backlight_state());
}

/// Writes `percent` to the internal backlight, then delivers the resulting state
/// (or the failure state on error) through `cb` as a borrowed `BacklightSnapshotC`.
/// `cb` fires once, synchronously, before return.
///
/// # Safety
/// `ctx`/`cb` must be valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Backlight_SetBrightness(
    percent: i32,
    ctx: *mut c_void,
    cb: BacklightSnapshotFn,
) {
    let state = match set_backlight_percent(percent) {
        Ok(()) => read_backlight_state(),
        Err(state) => state,
    };
    emit_backlight_state(cb, ctx, &state);
}

/// Installs (or reuses) a `notify` watcher on the sysfs `.../brightness` file.
/// On Modify/Create the watcher reads fresh state and delivers it through `cb`
/// as a borrowed `BacklightSnapshotC` (the C++ side copies it but must not retain
/// the pointers). Returns an error string as owned `char*` ("" on success); freed
/// with `QsNative_Free`.
///
/// # Safety
/// `handle` must be valid; `ctx`/`cb` must stay valid until the watcher is
/// dropped (via `stopMonitor` or `Delete`).
#[no_mangle]
pub unsafe extern "C" fn QsNative_Backlight_StartMonitor(
    handle: *mut BacklightHandle,
    ctx: *mut c_void,
    cb: BacklightSnapshotFn,
) -> *mut c_char {
    if handle.is_null() {
        return into_c_string(String::new());
    }
    let Some(path) = brightness_path() else {
        return into_c_string(String::new());
    };
    if (*handle)
        .monitor
        .as_ref()
        .is_some_and(|monitor| monitor.path == path)
    {
        return into_c_string(String::new());
    }

    let ctx = ctx as usize;
    let mut watcher = match RecommendedWatcher::new(
        move |result: notify::Result<Event>| {
            if result.as_ref().is_ok_and(|event| {
                matches!(event.kind, EventKind::Modify(_) | EventKind::Create(_))
            }) {
                let state = read_backlight_state();
                unsafe { emit_backlight_state(cb, ctx as *mut c_void, &state) };
            }
        },
        Config::default(),
    ) {
        Ok(watcher) => watcher,
        Err(error) => return into_c_string(format!("watch brightness: {error}")),
    };

    if let Err(error) = watcher.watch(&path, RecursiveMode::NonRecursive) {
        return into_c_string(format!("watch brightness: {error}"));
    }

    (*handle).monitor = Some(BacklightMonitor {
        _watcher: watcher,
        path,
    });
    into_c_string(String::new())
}

/// Drops the sysfs watcher, stopping the watch thread.
///
/// # Safety
/// `handle` must be null or a valid handle.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Backlight_StopMonitor(handle: *mut BacklightHandle) {
    if !handle.is_null() {
        (*handle).monitor = None;
    }
}

/// Re-checks `ddcutil` availability and returns it. When unavailable the DDC map
/// is cleared synchronously (C++ then bumps the version). When available a worker
/// thread runs `ddcutil detect`, stores the connector→bus map, and fires `cb` to
/// bump the change-notification version.
///
/// # Safety
/// `handle` must be valid; `ctx`/`cb` must remain valid until `cb` fires.
///
/// # Panics
/// Panics if the shared DDC state mutex is poisoned by a prior panic.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Backlight_RefreshDdc(
    handle: *mut BacklightHandle,
    ctx: *mut c_void,
    cb: QsNativeUpdateFn,
) -> bool {
    if handle.is_null() {
        return false;
    }
    let available = ddcutil_available();
    if !available {
        (*handle)
            .inner
            .lock()
            .expect("backlight state poisoned")
            .ddc_displays
            .clear();
        return false;
    }

    let inner = (*handle).inner.clone();
    let ctx = ctx as usize;
    thread::spawn(move || {
        let displays = detect_ddc_displays().unwrap_or_default();
        inner
            .lock()
            .expect("backlight state poisoned")
            .ddc_displays = displays;
        unsafe { emit_snapshot(cb, ctx as *mut c_void, "{}".to_owned()) };
    });
    true
}

/// I2C bus string for a connector ("" when unmapped). Freed with `QsNative_Free`.
///
/// # Safety
/// `handle` must be valid; `connector` a valid C string.
///
/// # Panics
/// Panics if the shared DDC state mutex is poisoned by a prior panic.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Backlight_DdcBusForConnector(
    handle: *mut BacklightHandle,
    connector: *const c_char,
) -> *mut c_char {
    if handle.is_null() {
        return into_c_string(String::new());
    }
    let connector = c_string(connector);
    let guard = (*handle).inner.lock().expect("backlight state poisoned");
    into_c_string(
        guard
            .ddc_displays
            .get(&connector)
            .map(|display| display.bus.clone())
            .unwrap_or_default(),
    )
}

/// Current DDC brightness as a 0-100 percent (0 when missing/unknown).
///
/// # Safety
/// `handle` must be valid; `connector` a valid C string.
///
/// # Panics
/// Panics if the shared DDC state mutex is poisoned by a prior panic.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Backlight_DdcBrightnessPercent(
    handle: *mut BacklightHandle,
    connector: *const c_char,
) -> i32 {
    if handle.is_null() {
        return 0;
    }
    let connector = c_string(connector);
    let guard = (*handle).inner.lock().expect("backlight state poisoned");
    guard
        .ddc_displays
        .get(&connector)
        .and_then(|display| {
            display
                .current
                .zip(display.max)
                .map(|(current, max)| normalized_percent(current, max))
        })
        .unwrap_or(0)
}

/// Max DDC brightness for a connector (100 fallback).
///
/// # Safety
/// `handle` must be valid; `connector` a valid C string.
///
/// # Panics
/// Panics if the shared DDC state mutex is poisoned by a prior panic.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Backlight_DdcMaxBrightness(
    handle: *mut BacklightHandle,
    connector: *const c_char,
) -> i32 {
    if handle.is_null() {
        return 100;
    }
    let connector = c_string(connector);
    let guard = (*handle).inner.lock().expect("backlight state poisoned");
    guard
        .ddc_displays
        .get(&connector)
        .and_then(|display| display.max)
        .unwrap_or(100)
}

/// Last DDC error string for a connector ("" when ok). Freed with `QsNative_Free`.
///
/// # Safety
/// `handle` must be valid; `connector` a valid C string.
///
/// # Panics
/// Panics if the shared DDC state mutex is poisoned by a prior panic.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Backlight_DdcError(
    handle: *mut BacklightHandle,
    connector: *const c_char,
) -> *mut c_char {
    if handle.is_null() {
        return into_c_string(String::new());
    }
    let connector = c_string(connector);
    let guard = (*handle).inner.lock().expect("backlight state poisoned");
    into_c_string(
        guard
            .ddc_displays
            .get(&connector)
            .map(|display| display.error.clone())
            .unwrap_or_default(),
    )
}

/// Reads a single connector's DDC brightness off-thread and bumps the version.
/// Returns false (no work started) when the connector is unmapped.
///
/// # Safety
/// `handle` must be valid; `connector` a valid C string; `ctx`/`cb` valid until
/// `cb` fires.
///
/// # Panics
/// Panics if the shared DDC state mutex is poisoned by a prior panic.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Backlight_RefreshDdcBrightness(
    handle: *mut BacklightHandle,
    connector: *const c_char,
    ctx: *mut c_void,
    cb: QsNativeUpdateFn,
) -> bool {
    if handle.is_null() {
        return false;
    }
    let connector = c_string(connector);
    let inner = (*handle).inner.clone();
    let bus = {
        let guard = inner.lock().expect("backlight state poisoned");
        match guard.ddc_displays.get(&connector) {
            Some(display) => display.bus.clone(),
            None => return false,
        }
    };

    let ctx = ctx as usize;
    thread::spawn(move || {
        let result = read_ddc_brightness(&bus);
        apply_ddc_brightness_result(&inner, &connector, result);
        unsafe { emit_snapshot(cb, ctx as *mut c_void, "{}".to_owned()) };
    });
    true
}

/// Sets a connector's DDC brightness off-thread (setvcp then getvcp) and bumps
/// the version. Returns false (no work started) when the connector is unmapped.
///
/// # Safety
/// `handle` must be valid; `connector` a valid C string; `ctx`/`cb` valid until
/// `cb` fires.
///
/// # Panics
/// Panics if the shared DDC state mutex is poisoned by a prior panic.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Backlight_SetDdcBrightness(
    handle: *mut BacklightHandle,
    connector: *const c_char,
    percent: i32,
    ctx: *mut c_void,
    cb: QsNativeUpdateFn,
) -> bool {
    if handle.is_null() {
        return false;
    }
    let connector = c_string(connector);
    let inner = (*handle).inner.clone();
    let (bus, max) = {
        let guard = inner.lock().expect("backlight state poisoned");
        match guard.ddc_displays.get(&connector) {
            Some(display) => (display.bus.clone(), display.max.unwrap_or(100)),
            None => return false,
        }
    };

    let raw = percent_to_ddc_raw(percent, max);
    let ctx = ctx as usize;
    thread::spawn(move || {
        let result = set_ddc_brightness_raw(&bus, raw).and_then(|()| read_ddc_brightness(&bus));
        apply_ddc_brightness_result(&inner, &connector, result);
        unsafe { emit_snapshot(cb, ctx as *mut c_void, "{}".to_owned()) };
    });
    true
}

fn apply_ddc_brightness_result(
    inner: &Arc<Mutex<BacklightInner>>,
    connector: &str,
    result: Result<(i32, i32), String>,
) {
    let mut guard = inner.lock().expect("backlight state poisoned");
    if let Some(display) = guard.ddc_displays.get_mut(connector) {
        match result {
            Ok((current, max)) => {
                display.current = Some(current);
                display.max = Some(max);
                display.error.clear();
            }
            Err(error) => {
                display.error = error;
            }
        }
    }
}

fn brightness_path() -> Option<PathBuf> {
    Device::new(None)
        .ok()
        .map(|device| device.device_path().join("brightness"))
}

fn read_backlight_state() -> BacklightState {
    match Device::new(None) {
        Ok(device) => BacklightState::from_device(&device, String::new()),
        Err(error) if matches!(error.kind(), ErrorKind::NotFound) => {
            BacklightState::unavailable("no backlight devices found")
        }
        Err(error) => BacklightState::unavailable(error.to_string()),
    }
}

fn set_backlight_percent(percent: i32) -> Result<(), BacklightState> {
    let mut device = match Device::new(None) {
        Ok(device) => device,
        Err(error) if matches!(error.kind(), ErrorKind::NotFound) => {
            return Err(BacklightState::unavailable("no backlight devices found"));
        }
        Err(error) => return Err(BacklightState::unavailable(error.to_string())),
    };

    let target = percent_to_raw(percent, device.max());
    device
        .write_value(target)
        .map_err(|error| BacklightState::from_device(&device, error.to_string()))
}

#[expect(
    clippy::cast_possible_truncation,
    reason = "percent is bounded to roughly 0..=100 and truncating the rounded f64 to i32 is intentional"
)]
fn raw_to_percent(current: u32, max: u32) -> i32 {
    ((f64::from(current) / f64::from(max)) * 100.0).round() as i32
}

#[expect(
    clippy::cast_possible_truncation,
    reason = "truncating the rounded f64 to i32 is intentional"
)]
fn percent_to_raw(percent: i32, max: u32) -> u32 {
    let clamped = percent.clamp(0, 100);
    let max_i32 = i32::try_from(max).unwrap_or(i32::MAX);
    let raw = ((f64::from(clamped) / 100.0) * f64::from(max)).round() as i32;
    if clamped > 0 {
        u32::try_from(raw.clamp(1, max_i32)).unwrap_or(0)
    } else {
        0
    }
}

#[expect(
    clippy::cast_possible_truncation,
    reason = "percent is bounded to roughly 0..=100 and truncating the rounded f64 to i32 is intentional"
)]
fn normalized_percent(current: i32, max: i32) -> i32 {
    if max <= 0 {
        return 0;
    }
    ((f64::from(current) / f64::from(max)) * 100.0).round() as i32
}

#[expect(
    clippy::cast_possible_truncation,
    reason = "value is clamped to 1.0..=max (which fits in i32) before truncating to i32"
)]
fn percent_to_ddc_raw(percent: i32, max: i32) -> i32 {
    let max = max.max(1);
    let clamped = percent.clamp(1, 100);
    ((f64::from(clamped) / 100.0) * f64::from(max))
        .round()
        .clamp(1.0, f64::from(max)) as i32
}

fn ddcutil_available() -> bool {
    let Some(path) = std::env::var_os("PATH") else {
        return false;
    };

    std::env::split_paths(&path).any(|dir| {
        let candidate = dir.join("ddcutil");
        candidate.is_file() && is_executable(&candidate)
    })
}

#[cfg(unix)]
fn is_executable(path: &std::path::Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.metadata()
        .is_ok_and(|metadata| metadata.permissions().mode() & 0o111 != 0)
}

#[cfg(not(unix))]
fn is_executable(path: &std::path::Path) -> bool {
    path.is_file()
}

fn detect_ddc_displays() -> Result<HashMap<String, DdcDisplay>, String> {
    let output = Command::new("ddcutil")
        .args(["detect", "--brief", "--sleep-multiplier=0.5"])
        .output()
        .map_err(|error| format!("run ddcutil detect: {error}"))?;

    if !output.status.success() {
        return Err(command_error("ddcutil detect", &output));
    }

    Ok(parse_ddc_detect(&String::from_utf8_lossy(&output.stdout)))
}

fn read_ddc_brightness(bus: &str) -> Result<(i32, i32), String> {
    let output = Command::new("ddcutil")
        .args([
            "-b",
            bus,
            "--sleep-multiplier=0.05",
            "getvcp",
            "10",
            "--brief",
        ])
        .output()
        .map_err(|error| format!("run ddcutil getvcp: {error}"))?;

    if !output.status.success() {
        return Err(command_error("ddcutil getvcp", &output));
    }

    parse_ddc_vcp10(&String::from_utf8_lossy(&output.stdout))
        .ok_or_else(|| "DDC read failed".to_owned())
}

fn set_ddc_brightness_raw(bus: &str, raw: i32) -> Result<(), String> {
    let raw = raw.to_string();
    let output = Command::new("ddcutil")
        .args(["-b", bus, "--sleep-multiplier=0.05", "setvcp", "10", &raw])
        .output()
        .map_err(|error| format!("run ddcutil setvcp: {error}"))?;

    if output.status.success() {
        Ok(())
    } else {
        Err(command_error("ddcutil setvcp", &output))
    }
}

fn command_error(command: &str, output: &std::process::Output) -> String {
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
    if stderr.is_empty() {
        format!("{command} exited with {}", output.status)
    } else {
        stderr
    }
}

fn parse_ddc_detect(text: &str) -> HashMap<String, DdcDisplay> {
    let mut displays = HashMap::new();
    for block in split_blocks(text) {
        let lower = block.to_ascii_lowercase();
        if block.is_empty()
            || lower.contains("does not support ddc/ci")
            || lower.contains("invalid display")
        {
            continue;
        }

        let connector = block
            .lines()
            .find_map(|line| line.split_once("DRM connector:"))
            .map(|(_, value)| {
                let value = value.trim();
                value
                    .split_once('-')
                    .and_then(|(prefix, connector)| {
                        (prefix.starts_with("card")
                            && prefix["card".len()..]
                                .chars()
                                .all(|character| character.is_ascii_digit()))
                        .then_some(connector)
                    })
                    .unwrap_or(value)
                    .to_owned()
            });
        let bus = block.lines().find_map(parse_i2c_bus);

        if let (Some(connector), Some(bus)) = (connector, bus) {
            if !connector.is_empty() && !bus.is_empty() {
                displays.insert(
                    connector,
                    DdcDisplay {
                        bus,
                        current: None,
                        max: None,
                        error: String::new(),
                    },
                );
            }
        }
    }
    displays
}

fn split_blocks(text: &str) -> impl Iterator<Item = &str> {
    text.split("\n\n")
        .map(str::trim)
        .filter(|block| !block.is_empty())
}

fn parse_i2c_bus(line: &str) -> Option<String> {
    let (_, value) = line.split_once("I2C bus:")?;
    let index = value.rfind("i2c-")?;
    let bus = value[index + "i2c-".len()..]
        .chars()
        .take_while(char::is_ascii_digit)
        .collect::<String>();
    (!bus.is_empty()).then_some(bus)
}

fn parse_ddc_vcp10(output: &str) -> Option<(i32, i32)> {
    let mut numbers = Vec::new();
    for token in output.split(|character: char| {
        character.is_ascii_whitespace() || matches!(character, '(' | ')' | ',' | '=' | ':')
    }) {
        let token = token.trim();
        if token.is_empty() {
            continue;
        }
        let value = if let Some(hex) = token
            .strip_prefix("0x")
            .or_else(|| token.strip_prefix("0X"))
        {
            i32::from_str_radix(hex, 16).ok()
        } else {
            token.parse::<i32>().ok()
        };
        if let Some(value) = value {
            numbers.push(value);
        }
    }

    let max = *numbers.last()?;
    let current = *numbers.get(numbers.len().checked_sub(2)?)?;
    (max > 0).then_some((current, max))
}

impl BacklightState {
    fn from_device(device: &Device, error: String) -> Self {
        Self {
            available: true,
            brightness_percent: raw_to_percent(device.current(), device.max()),
            device: device.name().to_owned(),
            error,
        }
    }

    fn unavailable(error: impl Into<String>) -> Self {
        Self {
            available: false,
            brightness_percent: 0,
            device: String::new(),
            error: error.into(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        parse_ddc_detect, parse_ddc_vcp10, percent_to_ddc_raw, percent_to_raw, raw_to_percent,
    };

    #[test]
    fn maps_percent_to_raw_with_minimum_nonzero_brightness() {
        assert_eq!(percent_to_raw(-10, 937), 0);
        assert_eq!(percent_to_raw(0, 937), 0);
        assert_eq!(percent_to_raw(1, 937), 9);
        assert_eq!(percent_to_raw(50, 937), 469);
        assert_eq!(percent_to_raw(101, 937), 937);
        assert_eq!(percent_to_raw(1, 10), 1);
    }

    #[test]
    fn maps_raw_to_rounded_percent() {
        assert_eq!(raw_to_percent(0, 937), 0);
        assert_eq!(raw_to_percent(469, 937), 50);
        assert_eq!(raw_to_percent(937, 937), 100);
    }

    #[test]
    fn parses_ddc_detect_connector_to_bus_map() {
        let displays = parse_ddc_detect(
            r"
Display 1
   I2C bus:  /dev/i2c-7
   DRM connector: card1-DP-2

Display 2
   I2C bus:  /dev/i2c-8
   DRM connector: HDMI-A-1

Invalid display
   I2C bus: /dev/i2c-9
   DRM connector: card1-DP-3
",
        );

        assert_eq!(
            displays.get("DP-2").map(|display| display.bus.as_str()),
            Some("7")
        );
        assert_eq!(
            displays.get("HDMI-A-1").map(|display| display.bus.as_str()),
            Some("8")
        );
        assert!(!displays.contains_key("DP-3"));
    }

    #[test]
    fn parses_ddc_vcp10_current_and_max_from_decimal_or_hex() {
        assert_eq!(parse_ddc_vcp10("VCP 10 C 50 100"), Some((50, 100)));
        assert_eq!(
            parse_ddc_vcp10("VCP code 0x10 current value = 0x32, max value = 0x64"),
            Some((50, 100))
        );
        assert_eq!(parse_ddc_vcp10("VCP 10 C 50 0"), None);
    }

    #[test]
    fn maps_percent_to_ddc_raw_with_minimum_nonzero_brightness() {
        assert_eq!(percent_to_ddc_raw(-10, 937), 9);
        assert_eq!(percent_to_ddc_raw(0, 937), 9);
        assert_eq!(percent_to_ddc_raw(50, 937), 469);
        assert_eq!(percent_to_ddc_raw(101, 937), 937);
        assert_eq!(percent_to_ddc_raw(1, 10), 1);
    }
}
