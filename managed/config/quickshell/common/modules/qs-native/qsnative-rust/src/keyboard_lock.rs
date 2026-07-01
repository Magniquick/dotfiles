use core::pin::Pin;
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use evdev::{Device, EventType};

const LED_NUML: u16 = 0x00;
const LED_CAPSL: u16 = 0x01;

#[derive(Default)]
pub struct KeyboardLockProviderRust {
    running: bool,
    available: bool,
    error: QString,
    device_path: QString,
    caps_lock: bool,
    num_lock: bool,
    changed_key: QString,
    event_serial: i32,
    stop_flag: Option<Arc<AtomicBool>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum LockKey {
    Caps,
    Num,
}

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    impl cxx_qt::Threading for KeyboardLockProvider {}

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qobject]
        #[qproperty(bool, running)]
        #[qproperty(bool, available)]
        #[qproperty(QString, error)]
        #[qproperty(QString, device_path, cxx_name = "device_path")]
        #[qproperty(bool, caps_lock, cxx_name = "caps_lock")]
        #[qproperty(bool, num_lock, cxx_name = "num_lock")]
        #[qproperty(QString, changed_key, cxx_name = "changed_key")]
        #[qproperty(i32, event_serial, cxx_name = "event_serial")]
        type KeyboardLockProvider = super::KeyboardLockProviderRust;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qinvokable]
        fn start(self: Pin<&mut KeyboardLockProvider>, path: &QString) -> bool;

        #[qinvokable]
        fn stop(self: Pin<&mut KeyboardLockProvider>);
    }

    impl cxx_qt::Initialize for KeyboardLockProvider {}
}

impl cxx_qt::Initialize for ffi::KeyboardLockProvider {
    fn initialize(self: Pin<&mut Self>) {}
}

impl ffi::KeyboardLockProvider {
    pub fn start(mut self: Pin<&mut Self>, path: &QString) -> bool {
        let device_path = PathBuf::from(path.to_string());
        if device_path.as_os_str().is_empty() {
            self.as_mut()
                .publish_error("keyboard path is empty".to_owned());
            return false;
        }

        self.as_mut().stop();

        let stop_flag = Arc::new(AtomicBool::new(false));
        self.as_mut().rust_mut().as_mut().get_mut().stop_flag = Some(Arc::clone(&stop_flag));
        self.as_mut().set_running(true);
        self.as_mut().set_available(false);
        self.as_mut().set_error(QString::default());
        self.as_mut()
            .set_device_path(QString::from(device_path.to_string_lossy().as_ref()));

        let qt_thread = self.as_ref().qt_thread();
        std::thread::spawn(move || run_keyboard_monitor(device_path, stop_flag, qt_thread));
        true
    }

    pub fn stop(mut self: Pin<&mut Self>) {
        if let Some(stop_flag) = self.as_mut().rust_mut().as_mut().get_mut().stop_flag.take() {
            stop_flag.store(true, Ordering::Relaxed);
        }
        self.as_mut().set_running(false);
    }

    fn publish_available(mut self: Pin<&mut Self>) {
        self.as_mut().set_available(true);
        self.as_mut().set_error(QString::default());
    }

    fn publish_error(mut self: Pin<&mut Self>, error: String) {
        self.as_mut().set_available(false);
        self.as_mut().set_running(false);
        self.as_mut().set_error(QString::from(error.as_str()));
    }

    fn publish_lock_event(mut self: Pin<&mut Self>, key: LockKey, enabled: bool) {
        match key {
            LockKey::Caps => {
                self.as_mut().set_caps_lock(enabled);
                self.as_mut().set_changed_key(QString::from("caps"));
            }
            LockKey::Num => {
                self.as_mut().set_num_lock(enabled);
                self.as_mut().set_changed_key(QString::from("num"));
            }
        }
        let next_serial = self.as_ref().rust().event_serial.wrapping_add(1);
        self.as_mut().set_event_serial(next_serial);
    }
}

fn run_keyboard_monitor(
    device_path: PathBuf,
    stop_flag: Arc<AtomicBool>,
    qt_thread: cxx_qt::CxxQtThread<ffi::KeyboardLockProvider>,
) {
    let mut device = match Device::open(&device_path) {
        Ok(device) => device,
        Err(error) => {
            queue_error(&qt_thread, format!("keyboard lock monitor: {error}"));
            return;
        }
    };

    let _ = qt_thread.queue(|provider| {
        provider.publish_available();
    });

    while !stop_flag.load(Ordering::Relaxed) {
        let events = match device.fetch_events() {
            Ok(events) => events,
            Err(error) => {
                queue_error(&qt_thread, format!("keyboard lock monitor: {error}"));
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
            let enabled = event.value() != 0;
            let _ = qt_thread.queue(move |provider| {
                provider.publish_lock_event(key, enabled);
            });
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

fn queue_error(qt_thread: &cxx_qt::CxxQtThread<ffi::KeyboardLockProvider>, error: String) {
    let _ = qt_thread.queue(move |provider| {
        provider.publish_error(error);
    });
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
