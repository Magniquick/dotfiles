use core::pin::Pin;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::time::{Duration, Instant};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
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

#[derive(Default)]
pub struct MaterialPopupBackendRust {
    running: bool,
    available: bool,
    error: QString,
    last_text: QString,
    copy_serial: i32,
    activity_kind: QString,
    activity_serial: i32,
    stop_flag: Option<Arc<AtomicBool>>,
}

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, running)]
        #[qproperty(bool, available)]
        #[qproperty(QString, error)]
        #[qproperty(QString, last_text, cxx_name = "lastText")]
        #[qproperty(i32, copy_serial, cxx_name = "copySerial")]
        #[qproperty(QString, activity_kind, cxx_name = "activityKind")]
        #[qproperty(i32, activity_serial, cxx_name = "activitySerial")]
        type MaterialPopupBackend = super::MaterialPopupBackendRust;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qinvokable]
        fn start(self: Pin<&mut MaterialPopupBackend>);

        #[qinvokable]
        fn stop(self: Pin<&mut MaterialPopupBackend>);
    }

    impl cxx_qt::Threading for MaterialPopupBackend {}

    impl cxx_qt::Initialize for MaterialPopupBackend {}
}

impl ffi::MaterialPopupBackend {
    pub fn start(mut self: Pin<&mut Self>) {
        if *self.running() {
            return;
        }

        let stop_flag = Arc::new(AtomicBool::new(false));
        let clipboard_stop = Arc::clone(&stop_flag);
        let input_stop = Arc::clone(&stop_flag);
        self.as_mut().rust_mut().as_mut().get_mut().stop_flag = Some(stop_flag);
        self.as_mut().set_running(true);
        self.as_mut().set_available(true);
        self.as_mut().set_error(QString::default());

        let clipboard_thread = self.qt_thread();
        std::thread::spawn(move || {
            run_clipboard_watcher(clipboard_stop, clipboard_thread);
        });

        let input_thread = self.qt_thread();
        std::thread::spawn(move || {
            run_input_monitor(input_stop, input_thread);
        });
    }

    pub fn stop(mut self: Pin<&mut Self>) {
        let stop_flag = self.as_mut().rust_mut().as_mut().get_mut().stop_flag.take();
        if let Some(stop_flag) = stop_flag {
            stop_flag.store(true, Ordering::Relaxed);
        }
        self.as_mut().set_running(false);
    }

    fn publish_clipboard(mut self: Pin<&mut Self>, text: String) {
        let next_serial = (*self.copy_serial()).wrapping_add(1);
        self.as_mut().set_last_text(QString::from(text.as_str()));
        self.as_mut().set_copy_serial(next_serial);
    }

    fn publish_activity(mut self: Pin<&mut Self>, kind: &'static str) {
        let next_serial = (*self.activity_serial()).wrapping_add(1);
        self.as_mut().set_activity_kind(QString::from(kind));
        self.as_mut().set_activity_serial(next_serial);
    }

    fn publish_error(mut self: Pin<&mut Self>, error: String) {
        self.as_mut().set_error(QString::from(error.as_str()));
        self.as_mut().set_available(false);
    }
}

impl cxx_qt::Initialize for ffi::MaterialPopupBackend {
    fn initialize(self: Pin<&mut Self>) {}
}

fn run_clipboard_watcher(
    stop_flag: Arc<AtomicBool>,
    qt_thread: cxx_qt::CxxQtThread<ffi::MaterialPopupBackend>,
) {
    let mut stream = match WlClipboardPasteStreamWlr::init(WlListenType::ListenOnCopy) {
        Ok(stream) => stream,
        Err(err) => {
            queue_error(&qt_thread, format!("clipboard watcher: {err}"));
            return;
        }
    };

    let mut ignore_first = true;
    let mut last_text = String::new();
    let mut last_event = Instant::now() - CLIPBOARD_DEDUPE_WINDOW;

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
        last_text = text.clone();
        last_event = now;
        let _ = qt_thread.queue(move |backend| {
            backend.publish_clipboard(text);
        });
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

fn run_input_monitor(
    stop_flag: Arc<AtomicBool>,
    qt_thread: cxx_qt::CxxQtThread<ffi::MaterialPopupBackend>,
) {
    let entries = match std::fs::read_dir("/dev/input") {
        Ok(entries) => entries,
        Err(err) => {
            queue_error(&qt_thread, format!("input monitor: {err}"));
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
            .map(|name| name.starts_with("event"))
            .unwrap_or(false)
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
        let device_stop = Arc::clone(&stop_flag);
        let device_thread = qt_thread.clone();
        std::thread::spawn(move || {
            monitor_input_device(device, kind, device_stop, device_thread);
        });
    }

    if found == 0 {
        queue_error(
            &qt_thread,
            "input monitor: no readable keyboard or pointer devices".to_owned(),
        );
    }
}

fn monitor_input_device(
    mut device: Device,
    kind: &'static str,
    stop_flag: Arc<AtomicBool>,
    qt_thread: cxx_qt::CxxQtThread<ffi::MaterialPopupBackend>,
) {
    while !stop_flag.load(Ordering::Relaxed) {
        let events = match device.fetch_events() {
            Ok(events) => events,
            Err(_) => break,
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

            let _ = qt_thread.queue(move |backend| {
                backend.publish_activity(kind);
            });
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

fn queue_error(qt_thread: &cxx_qt::CxxQtThread<ffi::MaterialPopupBackend>, error: String) {
    let _ = qt_thread.queue(move |backend| {
        backend.publish_error(error);
    });
}

#[cfg(test)]
mod tests {
    use super::{should_ignore_clipboard_event, CLIPBOARD_DEDUPE_WINDOW};
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
}
