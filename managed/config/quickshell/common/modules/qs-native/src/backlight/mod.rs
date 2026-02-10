use std::fs;
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering as AtomicOrdering};
use std::sync::mpsc;
use std::sync::OnceLock;
use std::time::Duration;

use crate::qobjects;
use cxx_qt::CxxQtType;
use cxx_qt::Threading;
use std::pin::Pin;

#[derive(Clone)]
struct BacklightState {
  dir: PathBuf,
  device_name: String,
  max_brightness: i64,
  percent: i32,
}

fn backlight_device_dir() -> Result<PathBuf, String> {
  let base = Path::new("/sys/class/backlight");
  let entries = fs::read_dir(base).map_err(|err| format!("read_dir failed: {err}"))?;
  for ent in entries {
    let ent = ent.map_err(|err| format!("read_dir entry failed: {err}"))?;
    let p = ent.path();
    if !p.is_dir() {
      continue;
    }
    if p.join("brightness").is_file() && p.join("max_brightness").is_file() {
      return Ok(p);
    }
  }
  Err("No /sys/class/backlight device found".to_string())
}

fn read_int(path: &Path) -> Result<i64, String> {
  let s = fs::read_to_string(path).map_err(|err| format!("read {} failed: {err}", path.display()))?;
  let v: i64 = s.trim().parse().map_err(|err| format!("parse {} failed: {err}", path.display()))?;
  Ok(v)
}

fn clamp_i32(x: i32, min: i32, max: i32) -> i32 {
  if x < min {
    return min;
  }
  if x > max {
    return max;
  }
  x
}

fn monitor_started() -> &'static AtomicBool {
  static STARTED: OnceLock<AtomicBool> = OnceLock::new();
  STARTED.get_or_init(|| AtomicBool::new(false))
}

fn read_state() -> Result<BacklightState, String> {
  let dir = backlight_device_dir()?;
  let brightness = read_int(&dir.join("brightness"))?;
  let max_brightness = read_int(&dir.join("max_brightness"))?;
  if max_brightness <= 0 {
    return Err("max_brightness <= 0".to_string());
  }

  let device_name = dir
    .file_name()
    .and_then(|s| s.to_str())
    .unwrap_or("")
    .to_string();

  let percent = ((brightness as f64 / max_brightness as f64) * 100.0).round() as i32;
  let percent = clamp_i32(percent, 0, 100);

  Ok(BacklightState {
    dir,
    device_name,
    max_brightness,
    percent,
  })
}

fn apply_state(
  mut obj: std::pin::Pin<&mut qobjects::BacklightProvider>,
  state: BacklightState,
) -> Result<(), String> {
  obj.as_mut()
    .set_device(cxx_qt_lib::QString::from(state.device_name));
  obj.as_mut().set_available(true);
  obj.as_mut().set_brightness_percent(state.percent);
  obj.as_mut().set_error(cxx_qt_lib::QString::from(""));

  obj.as_mut().rust_mut().sysfs_dir = Some(state.dir);
  obj.as_mut().rust_mut().max_brightness = state.max_brightness;
  Ok(())
}

fn set_error(
  mut obj: std::pin::Pin<&mut qobjects::BacklightProvider>,
  err: String,
) -> Result<(), String> {
  obj.as_mut().set_error(cxx_qt_lib::QString::from(err));
  obj.as_mut().set_available(false);
  obj.as_mut().set_brightness_percent(0);
  Ok(())
}

pub(crate) fn start_udev_monitor(qt_thread: cxx_qt::CxxQtThread<qobjects::BacklightProvider>) -> bool {
  if monitor_started()
    .compare_exchange(false, true, AtomicOrdering::SeqCst, AtomicOrdering::SeqCst)
    .is_err()
  {
    return true;
  }

  let (tx, rx) = mpsc::channel::<()>();
  let qt_thread_udev = qt_thread.clone();

  // Udev listener thread: emit a unit message for each backlight event.
  std::thread::spawn(move || {
    let builder = match udev::MonitorBuilder::new() {
      Ok(b) => b,
      Err(err) => {
        let _ = qt_thread_udev.queue(move |mut obj: Pin<&mut qobjects::BacklightProvider>| {
          let _ = set_error(
            obj.as_mut(),
            format!("udev monitor init failed: {err}"),
          );
        });
        return;
      }
    };

    let builder = match builder.match_subsystem("backlight") {
      Ok(b) => b,
      Err(err) => {
        let _ = qt_thread_udev.queue(move |mut obj: Pin<&mut qobjects::BacklightProvider>| {
          let _ = set_error(
            obj.as_mut(),
            format!("udev match_subsystem failed: {err}"),
          );
        });
        return;
      }
    };

    let socket = match builder.listen() {
      Ok(s) => s,
      Err(err) => {
        let _ = qt_thread_udev.queue(move |mut obj: Pin<&mut qobjects::BacklightProvider>| {
          let _ = set_error(
            obj.as_mut(),
            format!("udev listen failed: {err}"),
          );
        });
        return;
      }
    };

    // Block on the monitor FD; this is event-driven (no periodic polling).
    let fd = socket.as_raw_fd();
    let mut fds = libc::pollfd {
      fd,
      events: libc::POLLIN,
      revents: 0,
    };
    loop {
      let rc = unsafe { libc::poll(&mut fds, 1, -1) };
      if rc < 0 {
        // Interrupted is fine; keep waiting.
        let errno = std::io::Error::last_os_error();
        if errno.kind() == std::io::ErrorKind::Interrupted {
          continue;
        }
        break;
      }

      // Drain any pending events.
      let mut iter = socket.iter();
      while iter.next().is_some() {
        if tx.send(()).is_err() {
          return;
        }
      }
    }
  });

  // Debouncer thread: coalesce bursts and trigger refresh.
  std::thread::spawn(move || {
    while rx.recv().is_ok() {
      // Coalesce any burst of events within 150ms.
      while rx.recv_timeout(Duration::from_millis(150)).is_ok() {}
      let state = match read_state() {
        Ok(s) => s,
        Err(err) => {
          let qt_thread2 = qt_thread.clone();
          let _ = qt_thread2.queue(move |mut obj: Pin<&mut qobjects::BacklightProvider>| {
            let _ = set_error(obj.as_mut(), err);
          });
          continue;
        }
      };

      let qt_thread2 = qt_thread.clone();
      let _ = qt_thread2.queue(move |mut obj: Pin<&mut qobjects::BacklightProvider>| {
        let _ = apply_state(obj.as_mut(), state);
      });
    }
  });

  true
}

pub(crate) fn refresh_from_sysfs(obj: std::pin::Pin<&mut qobjects::BacklightProvider>) -> Result<(), String> {
  match read_state() {
    Ok(state) => apply_state(obj, state),
    Err(err) => set_error(obj, err),
  }
}

pub(crate) fn set_brightness_sysfs(
  obj: std::pin::Pin<&mut qobjects::BacklightProvider>,
  percent: i32,
) -> Result<(), String> {
  let percent = clamp_i32(percent, 1, 100);

  // Discover current backlight device each time to avoid stale cached paths.
  let dir = backlight_device_dir()?;
  let max = read_int(&dir.join("max_brightness"))?;
  if max <= 0 {
    return Err("max_brightness <= 0".to_string());
  }

  let raw = ((percent as f64 / 100.0) * max as f64).floor() as i64;
  let raw = raw.max(1).min(max);

  fs::write(dir.join("brightness"), format!("{raw}\n"))
    .map_err(|err| format!("write brightness failed: {err}"))?;

  // Refresh immediately so UI reflects actual values.
  refresh_from_sysfs(obj)?;
  Ok(())
}

impl qobjects::BacklightProvider {
  pub fn start(self: Pin<&mut Self>) -> bool {
    let qt_thread = self.qt_thread();
    // Start monitor thread (idempotent) and do an initial refresh.
    start_udev_monitor(qt_thread.clone());

    let qt_thread2 = qt_thread.clone();
    std::thread::spawn(move || {
      let state = read_state();
      let _ = qt_thread2.queue(move |mut obj| match state {
        Ok(s) => {
          let _ = apply_state(obj.as_mut(), s);
        }
        Err(err) => {
          let _ = set_error(obj.as_mut(), err);
        }
      });
    });

    true
  }

  pub fn refresh(self: Pin<&mut Self>) -> bool {
    let qt_thread = self.qt_thread();
    std::thread::spawn(move || {
      let state = read_state();
      let _ = qt_thread.queue(move |mut obj| match state {
        Ok(s) => {
          let _ = apply_state(obj.as_mut(), s);
        }
        Err(err) => {
          let _ = set_error(obj.as_mut(), err);
        }
      });
    });
    true
  }

  pub fn set_brightness(self: Pin<&mut Self>, percent: i32) -> bool {
    let qt_thread = self.qt_thread();
    std::thread::spawn(move || {
      // Write on this worker thread using fresh sysfs discovery, then queue an update.
      let result = (|| -> Result<BacklightState, String> {
        let percent = clamp_i32(percent, 1, 100);
        let dir = backlight_device_dir()?;
        let max = read_int(&dir.join("max_brightness"))?;
        if max <= 0 {
          return Err("max_brightness <= 0".to_string());
        }
        let raw = ((percent as f64 / 100.0) * max as f64).floor() as i64;
        let raw = raw.max(1).min(max);
        fs::write(dir.join("brightness"), format!("{raw}\n"))
          .map_err(|err| format!("write brightness failed: {err}"))?;
        read_state()
      })();

      let _ = qt_thread.queue(move |mut obj| match result {
        Ok(state) => {
          let _ = apply_state(obj.as_mut(), state);
        }
        Err(err) => {
          let _ = set_error(obj.as_mut(), err);
        }
      });
    });
    true
  }
}
