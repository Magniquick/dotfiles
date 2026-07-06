//! Clipboard + input-watcher backend behind a hand-written C ABI.
//!
//! The C++ `QsNativeMaterialPopup` `QObject` owns one opaque handle and receives
//! events (new clipboard text, keyboard/pointer activity, worker errors) through
//! a borrowed-JSON callback that it marshals back onto the Qt thread. This crate
//! is standalone (no shared `crate::ffi`), so the few ABI helpers it needs are
//! inlined below.

use std::ffi::CString;
use std::fmt::Write as _;
use std::os::raw::{c_char, c_void};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use std::time::{Duration, Instant};

use evdev::{Device, EventType, KeyCode};
use wayland_clipboard_listener::{WlClipboardPasteStreamWlr, WlListenType};

const CLIPBOARD_DEDUPE_WINDOW: Duration = Duration::from_millis(50);
const TEXT_MIMES: &[&str] = &[
    "text/plain;charset=utf-8",
    "text/plain",
    "UTF8_STRING",
    "STRING",
    "TEXT",
];

/// Callback used to deliver a JSON event to C++. The `json` pointer is borrowed
/// for the duration of the call only: C++ copies it (`QString::fromUtf8`) and
/// must **not** free it.
pub type MaterialPopupUpdateFn = unsafe extern "C" fn(ctx: *mut c_void, json: *const c_char);

/// Where delivered events go. A function pointer plus `usize` context are both
/// `Send`, so the whole shared state can cross the worker-thread boundary.
#[derive(Clone, Copy)]
struct CallbackTarget {
    cb: MaterialPopupUpdateFn,
    ctx: usize,
}

/// Per-instance state shared with any live worker threads. Held behind a mutex
/// so `_Delete` can atomically drop the callback (blocking any in-flight
/// delivery) before the C++ object is torn down.
struct SharedState {
    callback: Option<CallbackTarget>,
    running: bool,
    stop_flag: Arc<AtomicBool>,
}

/// Opaque per-instance handle owned by the C++ `QsNativeMaterialPopup` `QObject`.
pub struct MaterialPopupHandle {
    shared: Arc<Mutex<SharedState>>,
}

/// Escapes a string for embedding inside a JSON string literal.
fn json_escape(input: &str) -> String {
    let mut out = String::with_capacity(input.len() + 2);
    for ch in input.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out
}

/// Delivers `json` to C++ while holding the lock, so a concurrent `_Delete` that
/// clears the callback cannot free the receiver mid-call.
fn emit_event(shared: &Arc<Mutex<SharedState>>, json: String) {
    let guard = shared.lock().expect("material popup state poisoned");
    if let Some(target) = &guard.callback {
        let buf =
            CString::new(json).unwrap_or_else(|_| CString::new("{}").expect("literal cstring"));
        unsafe { (target.cb)(target.ctx as *mut c_void, buf.as_ptr()) };
    }
}

fn emit_clipboard(shared: &Arc<Mutex<SharedState>>, text: &str) {
    emit_event(
        shared,
        format!("{{\"kind\":\"clipboard\",\"text\":\"{}\"}}", json_escape(text)),
    );
}

fn emit_activity(shared: &Arc<Mutex<SharedState>>, kind: &str) {
    emit_event(
        shared,
        format!("{{\"kind\":\"activity\",\"activity\":\"{}\"}}", json_escape(kind)),
    );
}

fn emit_error(shared: &Arc<Mutex<SharedState>>, error: &str) {
    emit_event(
        shared,
        format!("{{\"kind\":\"error\",\"error\":\"{}\"}}", json_escape(error)),
    );
}

/// Creates a handle that delivers events to `cb`/`ctx`. The caller must keep
/// `ctx`/`cb` valid until `QsNative_MaterialPopup_Delete`.
#[no_mangle]
pub extern "C" fn QsNative_MaterialPopup_New(
    ctx: *mut c_void,
    cb: MaterialPopupUpdateFn,
) -> *mut MaterialPopupHandle {
    Box::into_raw(Box::new(MaterialPopupHandle {
        shared: Arc::new(Mutex::new(SharedState {
            callback: Some(CallbackTarget {
                cb,
                ctx: ctx as usize,
            }),
            running: false,
            stop_flag: Arc::new(AtomicBool::new(false)),
        })),
    }))
}

/// # Safety
/// `handle` must be null or a pointer from `QsNative_MaterialPopup_New` not yet
/// freed.
///
/// # Panics
/// Panics if the shared-state mutex has been poisoned by a panic in a worker
/// thread.
#[no_mangle]
pub unsafe extern "C" fn QsNative_MaterialPopup_Delete(handle: *mut MaterialPopupHandle) {
    if handle.is_null() {
        return;
    }
    {
        let mut guard = (*handle).shared.lock().expect("material popup state poisoned");
        guard.stop_flag.store(true, Ordering::Relaxed);
        guard.running = false;
        // Disable delivery so any in-flight worker cannot call into the C++
        // object once this returns and the QObject is destroyed.
        guard.callback = None;
    }
    drop(Box::from_raw(handle));
}

/// Spawns the clipboard watcher and input monitor if not already running.
///
/// # Safety
/// `handle` must be valid.
///
/// # Panics
/// Panics if the shared-state mutex has been poisoned by a panic in a worker
/// thread.
#[no_mangle]
pub unsafe extern "C" fn QsNative_MaterialPopup_Start(handle: *mut MaterialPopupHandle) {
    if handle.is_null() {
        return;
    }
    let shared = (*handle).shared.clone();
    let stop_flag = {
        let mut guard = shared.lock().expect("material popup state poisoned");
        if guard.running {
            return;
        }
        guard.running = true;
        let stop_flag = Arc::new(AtomicBool::new(false));
        guard.stop_flag = Arc::clone(&stop_flag);
        stop_flag
    };

    let clipboard_shared = Arc::clone(&shared);
    let clipboard_stop = Arc::clone(&stop_flag);
    std::thread::spawn(move || run_clipboard_watcher(&clipboard_stop, &clipboard_shared));

    let input_shared = Arc::clone(&shared);
    let input_stop = stop_flag;
    std::thread::spawn(move || run_input_monitor(&input_stop, &input_shared));
}

/// Signals the worker threads to stop and clears the running flag.
///
/// # Safety
/// `handle` must be valid.
///
/// # Panics
/// Panics if the shared-state mutex has been poisoned by a panic in a worker
/// thread.
#[no_mangle]
pub unsafe extern "C" fn QsNative_MaterialPopup_Stop(handle: *mut MaterialPopupHandle) {
    if handle.is_null() {
        return;
    }
    let mut guard = (*handle).shared.lock().expect("material popup state poisoned");
    guard.stop_flag.store(true, Ordering::Relaxed);
    guard.running = false;
}

fn run_clipboard_watcher(stop_flag: &Arc<AtomicBool>, shared: &Arc<Mutex<SharedState>>) {
    let mut stream = match WlClipboardPasteStreamWlr::init(WlListenType::ListenOnCopy) {
        Ok(stream) => stream,
        Err(err) => {
            emit_error(shared, &format!("clipboard watcher: {err}"));
            return;
        }
    };

    let mut ignore_first = true;
    let mut last_text = String::new();
    let now = Instant::now();
    let mut last_event = now.checked_sub(CLIPBOARD_DEDUPE_WINDOW).unwrap_or(now);

    for msg in stream.paste_stream().flatten() {
        if stop_flag.load(Ordering::Relaxed) {
            break;
        }

        let mime = &msg.context.mime_type;
        if !TEXT_MIMES.contains(&mime.as_str()) {
            continue;
        }

        let Ok(text) = String::from_utf8(msg.context.context) else {
            continue;
        };
        let text = text.trim_end_matches('\n').to_owned();
        if text.is_empty() {
            continue;
        }

        let now = Instant::now();
        if should_ignore_clipboard_event(ignore_first, &last_text, last_event, &text, now) {
            ignore_first = false;
            continue;
        }

        ignore_first = false;
        last_text.clone_from(&text);
        last_event = now;
        emit_clipboard(shared, &text);
    }
}

fn should_ignore_clipboard_event(
    ignore_first: bool,
    last_text: &str,
    last_event: Instant,
    text: &str,
    now: Instant,
) -> bool {
    ignore_first || (last_text == text && now.duration_since(last_event) < CLIPBOARD_DEDUPE_WINDOW)
}

fn run_input_monitor(stop_flag: &Arc<AtomicBool>, shared: &Arc<Mutex<SharedState>>) {
    let entries = match std::fs::read_dir("/dev/input") {
        Ok(entries) => entries,
        Err(err) => {
            emit_error(shared, &format!("input monitor: {err}"));
            return;
        }
    };

    let mut found = 0usize;
    for entry in entries.flatten() {
        if stop_flag.load(Ordering::Relaxed) {
            break;
        }

        let path = entry.path();
        if !path
            .file_name()
            .and_then(|name| name.to_str())
            .is_some_and(|name| name.starts_with("event"))
        {
            continue;
        }

        let Ok(device) = Device::open(&path) else {
            continue;
        };
        let kind = if is_keyboard(&device) {
            Some("keyboard")
        } else if is_pointer(&device) {
            Some("pointer")
        } else {
            None
        };
        let Some(kind) = kind else {
            continue;
        };

        found += 1;
        let device_stop = Arc::clone(stop_flag);
        let device_shared = Arc::clone(shared);
        std::thread::spawn(move || {
            monitor_input_device(device, kind, &device_stop, &device_shared);
        });
    }

    if found == 0 {
        emit_error(
            shared,
            "input monitor: no readable keyboard or pointer devices",
        );
    }
}

fn monitor_input_device(
    mut device: Device,
    kind: &'static str,
    stop_flag: &Arc<AtomicBool>,
    shared: &Arc<Mutex<SharedState>>,
) {
    while !stop_flag.load(Ordering::Relaxed) {
        let Ok(events) = device.fetch_events() else {
            break;
        };

        for event in events {
            if event.event_type() != EventType::KEY || event.value() != 1 {
                continue;
            }

            let key = KeyCode::new(event.code());
            let fire = if kind == "keyboard" {
                true
            } else {
                matches!(
                    key,
                    KeyCode::BTN_LEFT | KeyCode::BTN_RIGHT | KeyCode::BTN_MIDDLE
                )
            };
            if !fire {
                continue;
            }

            emit_activity(shared, kind);
        }
    }
}

fn is_keyboard(device: &Device) -> bool {
    let Some(keys) = device.supported_keys() else {
        return false;
    };
    keys.contains(KeyCode::KEY_A)
        && keys.contains(KeyCode::KEY_Z)
        && keys.contains(KeyCode::KEY_SPACE)
}

fn is_pointer(device: &Device) -> bool {
    let events = device.supported_events();
    let Some(keys) = device.supported_keys() else {
        return false;
    };
    keys.contains(KeyCode::BTN_LEFT)
        && (events.contains(EventType::RELATIVE) || events.contains(EventType::ABSOLUTE))
}

#[cfg(test)]
mod tests {
    use super::{json_escape, should_ignore_clipboard_event, CLIPBOARD_DEDUPE_WINDOW};
    use std::time::Instant;

    #[test]
    fn ignores_initial_clipboard_offer() {
        let now = Instant::now();
        assert!(should_ignore_clipboard_event(true, "", now, "hello", now));
    }

    #[test]
    fn dedupes_rapid_identical_copy() {
        let first = Instant::now();
        let second = first + (CLIPBOARD_DEDUPE_WINDOW / 2);
        assert!(should_ignore_clipboard_event(
            false, "hello", first, "hello", second
        ));
    }

    #[test]
    fn allows_later_identical_copy() {
        let first = Instant::now();
        let second = first + (CLIPBOARD_DEDUPE_WINDOW * 2);
        assert!(!should_ignore_clipboard_event(
            false, "hello", first, "hello", second
        ));
    }

    #[test]
    fn escapes_json_control_and_quotes() {
        assert_eq!(json_escape("a\"b\\c"), "a\\\"b\\\\c");
        assert_eq!(json_escape("line\nbreak"), "line\\nbreak");
        assert_eq!(json_escape("tab\tend"), "tab\\tend");
    }
}
