//! evdev caps-lock / num-lock LED watcher.
//!
//! Opaque handle owned by the C++ `QsNativeKeyboardLock` `QObject`. `Start` spawns
//! a background reader thread that blocks on `fetch_events` and reports each LED
//! toggle back to C++ as a zero-copy `KeyboardLockSnapshotC` event through a
//! typed callback. The `QObject` owns the property state (caps/num/serial); this
//! file only reports raw transitions.

use std::ffi::CString;
use std::os::raw::{c_char, c_void};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;

use evdev::{Device, EventType};

use crate::ffi::c_string;

const LED_NUML: u16 = 0x00;
const LED_CAPSL: u16 = 0x01;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum LockKey {
    Caps,
    Num,
}

impl LockKey {
    fn name(self) -> &'static str {
        match self {
            LockKey::Caps => "caps",
            LockKey::Num => "num",
        }
    }
}

/// Zero-copy event handed to the C++ side. The `*const c_char` fields borrow
/// `CString`s that live on the worker stack **only for the duration of the
/// callback**; C++ must copy them (`QString::fromUtf8`) synchronously and must
/// not retain the pointers. `event_type` is one of `available`/`error`/`lock`;
/// `message` carries the error text, `key` the `caps`/`num` toggle, and
/// `enabled` its new state. Unused fields are empty/false for a given kind.
#[repr(C)]
pub struct KeyboardLockSnapshotC {
    pub event_type: *const c_char,
    pub message: *const c_char,
    pub key: *const c_char,
    pub enabled: bool,
}

/// Delivers a `KeyboardLockSnapshotC` (borrowed for the call only) to C++.
pub type KeyboardLockSnapshotFn =
    unsafe extern "C" fn(*mut c_void, *const KeyboardLockSnapshotC);

/// Builds a `CString`, falling back to empty on an interior NUL.
fn cstr(value: &str) -> CString {
    CString::new(value).unwrap_or_default()
}

/// Callback target shared between the handle and the worker thread. Set to
/// `None` by `Delete` while holding the mutex, which both stops any further
/// callbacks and blocks until an in-flight callback finishes, so the C++ `ctx`
/// is never touched after the `QObject` is torn down.
struct Sink {
    ctx: usize,
    cb: KeyboardLockSnapshotFn,
}

type Gate = Arc<Mutex<Option<Sink>>>;

/// Opaque per-instance handle owned by the C++ `QsNativeKeyboardLock` `QObject`.
pub struct KeyboardLockHandle {
    gate: Gate,
    stop_flag: Option<Arc<AtomicBool>>,
}

#[no_mangle]
pub extern "C" fn QsNative_KeyboardLock_New() -> *mut KeyboardLockHandle {
    Box::into_raw(Box::new(KeyboardLockHandle {
        gate: Arc::new(Mutex::new(None)),
        stop_flag: None,
    }))
}

/// # Safety
/// `handle` must be null or a pointer from `QsNative_KeyboardLock_New` not yet
/// freed. Any in-flight worker callback is drained before the handle drops.
///
/// # Panics
/// Panics if the gate mutex is poisoned (a worker thread panicked while holding it).
#[no_mangle]
pub unsafe extern "C" fn QsNative_KeyboardLock_Delete(handle: *mut KeyboardLockHandle) {
    if handle.is_null() {
        return;
    }
    let handle = Box::from_raw(handle);
    if let Some(flag) = &handle.stop_flag {
        flag.store(true, Ordering::Relaxed);
    }
    // Close the gate: no callback fires after this returns, and this blocks
    // until any in-flight callback has finished posting to the Qt thread.
    *handle.gate.lock().expect("keyboard lock gate poisoned") = None;
}

/// Spawns the evdev reader thread. `ctx`/`cb` deliver events back to the
/// `QObject`; the caller is responsible for the empty-path case (it never calls
/// here with an empty path).
///
/// # Safety
/// `handle` must be valid; `path` a valid C string; `ctx`/`cb` must stay valid
/// until `QsNative_KeyboardLock_Delete` drains the gate.
///
/// # Panics
/// Panics if the gate mutex is poisoned (a worker thread panicked while holding it).
#[no_mangle]
pub unsafe extern "C" fn QsNative_KeyboardLock_Start(
    handle: *mut KeyboardLockHandle,
    path: *const c_char,
    ctx: *mut c_void,
    cb: KeyboardLockSnapshotFn,
) {
    if handle.is_null() {
        return;
    }
    let handle = &mut *handle;
    stop_worker(handle);

    let device_path = PathBuf::from(c_string(path));
    *handle.gate.lock().expect("keyboard lock gate poisoned") = Some(Sink {
        ctx: ctx as usize,
        cb,
    });

    let stop_flag = Arc::new(AtomicBool::new(false));
    handle.stop_flag = Some(Arc::clone(&stop_flag));
    let gate = Arc::clone(&handle.gate);
    thread::spawn(move || run_keyboard_monitor(&device_path, &stop_flag, &gate));
}

/// # Safety
/// `handle` must be null or a valid handle pointer.
#[no_mangle]
pub unsafe extern "C" fn QsNative_KeyboardLock_Stop(handle: *mut KeyboardLockHandle) {
    if handle.is_null() {
        return;
    }
    stop_worker(&mut *handle);
}

fn stop_worker(handle: &mut KeyboardLockHandle) {
    if let Some(flag) = handle.stop_flag.take() {
        flag.store(true, Ordering::Relaxed);
    }
}

fn run_keyboard_monitor(device_path: &Path, stop_flag: &AtomicBool, gate: &Gate) {
    let mut device = match Device::open(device_path) {
        Ok(device) => device,
        Err(error) => {
            emit_error(gate, &format!("keyboard lock monitor: {error}"));
            return;
        }
    };

    emit_available(gate);

    while !stop_flag.load(Ordering::Relaxed) {
        let events = match device.fetch_events() {
            Ok(events) => events,
            Err(error) => {
                emit_error(gate, &format!("keyboard lock monitor: {error}"));
                break;
            }
        };

        for event in events {
            if event.event_type() != EventType::LED {
                continue;
            }
            let Some(key) = lock_key_for_code(event.code()) else {
                continue;
            };
            emit_lock(gate, key, event.value() != 0);
        }
    }
}

fn lock_key_for_code(code: u16) -> Option<LockKey> {
    match code {
        LED_CAPSL => Some(LockKey::Caps),
        LED_NUML => Some(LockKey::Num),
        _ => None,
    }
}

fn emit_available(gate: &Gate) {
    emit_event(gate, "available", "", "", false);
}

fn emit_error(gate: &Gate, message: &str) {
    emit_event(gate, "error", message, "", false);
}

fn emit_lock(gate: &Gate, key: LockKey, enabled: bool) {
    emit_event(gate, "lock", "", key.name(), enabled);
}

/// Delivers one event to C++ while holding the gate, so a concurrent `Delete`
/// cannot free the `QObject` mid-callback. The `CString`s stay bound in this
/// scope so the borrowed `*const c_char` pointers outlive the `cb` call.
fn emit_event(gate: &Gate, event_type: &str, message: &str, key: &str, enabled: bool) {
    let guard = gate.lock().expect("keyboard lock gate poisoned");
    if let Some(sink) = guard.as_ref() {
        let event_type_c = cstr(event_type);
        let message_c = cstr(message);
        let key_c = cstr(key);
        let c = KeyboardLockSnapshotC {
            event_type: event_type_c.as_ptr(),
            message: message_c.as_ptr(),
            key: key_c.as_ptr(),
            enabled,
        };
        unsafe { (sink.cb)(sink.ctx as *mut c_void, std::ptr::from_ref(&c)) };
    }
}

#[cfg(test)]
mod tests {
    use super::{lock_key_for_code, LockKey, LED_CAPSL, LED_NUML};

    #[test]
    fn maps_led_codes_to_lock_keys() {
        assert_eq!(lock_key_for_code(LED_CAPSL), Some(LockKey::Caps));
        assert_eq!(lock_key_for_code(LED_NUML), Some(LockKey::Num));
        assert_eq!(lock_key_for_code(0x02), None);
    }
}
