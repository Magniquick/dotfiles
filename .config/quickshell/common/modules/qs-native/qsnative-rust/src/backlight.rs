use core::pin::Pin;
use std::{collections::HashMap, path::PathBuf, process::Command};

use blight::{Device, ErrorKind, Light};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};

#[derive(Default)]
pub struct BacklightProviderRust {
    available: bool,
    brightness_percent: i32,
    device: QString,
    error: QString,
    monitor: Option<BacklightMonitor>,
    ddcutil_available: bool,
    ddc_version: i32,
    ddc_displays: HashMap<String, DdcDisplay>,
}

struct BacklightMonitor {
    _watcher: RecommendedWatcher,
    path: PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct BacklightState {
    available: bool,
    brightness_percent: i32,
    device: String,
    error: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct DdcDisplay {
    bus: String,
    current: Option<i32>,
    max: Option<i32>,
    error: String,
}

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    impl cxx_qt::Threading for BacklightProvider {}

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available)]
        #[qproperty(i32, brightness_percent, cxx_name = "brightness_percent")]
        #[qproperty(QString, device)]
        #[qproperty(QString, error)]
        #[qproperty(bool, ddcutil_available, cxx_name = "ddcutil_available")]
        #[qproperty(i32, ddc_version, cxx_name = "ddc_version")]
        type BacklightProvider = super::BacklightProviderRust;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qinvokable]
        fn start(self: Pin<&mut BacklightProvider>);

        #[qinvokable]
        #[cxx_name = "startMonitor"]
        fn start_monitor(self: Pin<&mut BacklightProvider>);

        #[qinvokable]
        #[cxx_name = "stopMonitor"]
        fn stop_monitor(self: Pin<&mut BacklightProvider>);

        #[qinvokable]
        fn refresh(self: Pin<&mut BacklightProvider>) -> bool;

        #[qinvokable]
        #[cxx_name = "setBrightness"]
        fn set_brightness(self: Pin<&mut BacklightProvider>, percent: i32) -> bool;

        #[qinvokable]
        #[cxx_name = "refreshDdc"]
        fn refresh_ddc(self: Pin<&mut BacklightProvider>) -> bool;

        #[qinvokable]
        #[cxx_name = "ddcBusForConnector"]
        fn ddc_bus_for_connector(self: Pin<&mut BacklightProvider>, connector: &QString)
            -> QString;

        #[qinvokable]
        #[cxx_name = "ddcBrightnessPercent"]
        fn ddc_brightness_percent(self: Pin<&mut BacklightProvider>, connector: &QString) -> i32;

        #[qinvokable]
        #[cxx_name = "ddcMaxBrightness"]
        fn ddc_max_brightness(self: Pin<&mut BacklightProvider>, connector: &QString) -> i32;

        #[qinvokable]
        #[cxx_name = "ddcError"]
        fn ddc_error(self: Pin<&mut BacklightProvider>, connector: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "refreshDdcBrightness"]
        fn refresh_ddc_brightness(self: Pin<&mut BacklightProvider>, connector: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "setDdcBrightness"]
        fn set_ddc_brightness(
            self: Pin<&mut BacklightProvider>,
            connector: &QString,
            percent: i32,
        ) -> bool;
    }

    impl cxx_qt::Initialize for BacklightProvider {}
}

impl cxx_qt::Initialize for ffi::BacklightProvider {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut().set_ddcutil_available(ddcutil_available());
    }
}

impl ffi::BacklightProvider {
    pub fn start(self: Pin<&mut Self>) {
        let mut this = self;
        this.as_mut().start_monitor();
        this.refresh_ddc();
    }

    pub fn start_monitor(mut self: Pin<&mut Self>) {
        let _ = self.as_mut().refresh();
        self.as_mut().start_watcher();
    }

    pub fn stop_monitor(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().as_mut().get_mut().monitor = None;
    }

    pub fn refresh(mut self: Pin<&mut Self>) -> bool {
        let state = read_backlight_state();
        self.as_mut().apply_state(state);
        true
    }

    pub fn set_brightness(mut self: Pin<&mut Self>, percent: i32) -> bool {
        match set_backlight_percent(percent) {
            Ok(()) => {
                self.as_mut().refresh();
            }
            Err(state) => {
                self.as_mut().apply_state(state);
            }
        }
        true
    }

    pub fn refresh_ddc(mut self: Pin<&mut Self>) -> bool {
        let available = ddcutil_available();
        self.as_mut().set_ddcutil_available(available);
        if !available {
            self.as_mut()
                .rust_mut()
                .as_mut()
                .get_mut()
                .ddc_displays
                .clear();
            self.as_mut().bump_ddc_version();
            return true;
        }

        let qt_thread = self.as_ref().qt_thread();
        std::thread::spawn(move || {
            let displays = detect_ddc_displays().unwrap_or_default();
            let _ = qt_thread.queue(move |mut provider| {
                provider.as_mut().rust_mut().as_mut().get_mut().ddc_displays = displays;
                provider.as_mut().bump_ddc_version();
            });
        });
        true
    }

    pub fn ddc_bus_for_connector(self: Pin<&mut Self>, connector: &QString) -> QString {
        let connector = connector.to_string();
        QString::from(
            self.as_ref()
                .rust()
                .ddc_displays
                .get(&connector)
                .map(|display| display.bus.as_str())
                .unwrap_or_default(),
        )
    }

    pub fn ddc_brightness_percent(self: Pin<&mut Self>, connector: &QString) -> i32 {
        let connector = connector.to_string();
        self.as_ref()
            .rust()
            .ddc_displays
            .get(&connector)
            .and_then(|display| {
                display
                    .current
                    .zip(display.max)
                    .map(|(c, m)| normalized_percent(c, m))
            })
            .unwrap_or(0)
    }

    pub fn ddc_max_brightness(self: Pin<&mut Self>, connector: &QString) -> i32 {
        let connector = connector.to_string();
        self.as_ref()
            .rust()
            .ddc_displays
            .get(&connector)
            .and_then(|display| display.max)
            .unwrap_or(100)
    }

    pub fn ddc_error(self: Pin<&mut Self>, connector: &QString) -> QString {
        let connector = connector.to_string();
        QString::from(
            self.as_ref()
                .rust()
                .ddc_displays
                .get(&connector)
                .map(|display| display.error.as_str())
                .unwrap_or_default(),
        )
    }

    pub fn refresh_ddc_brightness(self: Pin<&mut Self>, connector: &QString) -> bool {
        let connector = connector.to_string();
        let Some(bus) = self
            .as_ref()
            .rust()
            .ddc_displays
            .get(&connector)
            .map(|display| display.bus.clone())
        else {
            return false;
        };

        let qt_thread = self.as_ref().qt_thread();
        std::thread::spawn(move || {
            let result = read_ddc_brightness(&bus);
            let _ = qt_thread.queue(move |mut provider| {
                provider
                    .as_mut()
                    .apply_ddc_brightness_result(connector, result);
            });
        });
        true
    }

    pub fn set_ddc_brightness(self: Pin<&mut Self>, connector: &QString, percent: i32) -> bool {
        let connector = connector.to_string();
        let Some((bus, max)) = self
            .as_ref()
            .rust()
            .ddc_displays
            .get(&connector)
            .map(|display| (display.bus.clone(), display.max.unwrap_or(100)))
        else {
            return false;
        };

        let raw = percent_to_ddc_raw(percent, max);
        let qt_thread = self.as_ref().qt_thread();
        std::thread::spawn(move || {
            let result = set_ddc_brightness_raw(&bus, raw).and_then(|()| read_ddc_brightness(&bus));
            let _ = qt_thread.queue(move |mut provider| {
                provider
                    .as_mut()
                    .apply_ddc_brightness_result(connector, result);
            });
        });
        true
    }

    fn start_watcher(mut self: Pin<&mut Self>) {
        let Some(path) = brightness_path() else {
            return;
        };

        if self
            .as_ref()
            .rust()
            .monitor
            .as_ref()
            .is_some_and(|monitor| monitor.path == path)
        {
            return;
        }

        let qt_thread = self.as_ref().qt_thread();
        let mut watcher = match RecommendedWatcher::new(
            move |result: notify::Result<Event>| {
                if result.as_ref().is_ok_and(|event| {
                    matches!(event.kind, EventKind::Modify(_) | EventKind::Create(_))
                }) {
                    let _ = qt_thread.queue(|mut provider| {
                        provider.as_mut().refresh();
                    });
                }
            },
            Config::default(),
        ) {
            Ok(watcher) => watcher,
            Err(error) => {
                self.as_mut()
                    .set_error(QString::from(format!("watch brightness: {error}")));
                return;
            }
        };

        if let Err(error) = watcher.watch(&path, RecursiveMode::NonRecursive) {
            self.as_mut()
                .set_error(QString::from(format!("watch brightness: {error}")));
            return;
        }

        self.as_mut().rust_mut().as_mut().get_mut().monitor = Some(BacklightMonitor {
            _watcher: watcher,
            path,
        });
    }

    fn apply_state(mut self: Pin<&mut Self>, state: BacklightState) {
        self.as_mut().set_available(state.available);
        self.as_mut()
            .set_brightness_percent(state.brightness_percent);
        self.as_mut().set_device(QString::from(state.device));
        self.set_error(QString::from(state.error));
    }

    fn apply_ddc_brightness_result(
        mut self: Pin<&mut Self>,
        connector: String,
        result: Result<(i32, i32), String>,
    ) {
        if let Some(display) = self
            .as_mut()
            .rust_mut()
            .as_mut()
            .get_mut()
            .ddc_displays
            .get_mut(&connector)
        {
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
        self.bump_ddc_version();
    }

    fn bump_ddc_version(mut self: Pin<&mut Self>) {
        let next = self.as_ref().rust().ddc_version.saturating_add(1);
        self.as_mut().set_ddc_version(next);
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

fn raw_to_percent(current: u32, max: u32) -> i32 {
    ((current as f64 / max as f64) * 100.0).round() as i32
}

fn percent_to_raw(percent: i32, max: u32) -> u32 {
    let clamped = percent.clamp(0, 100);
    let raw = ((clamped as f64 / 100.0) * max as f64).round() as i32;
    if clamped > 0 {
        raw.clamp(1, max as i32) as u32
    } else {
        0
    }
}

fn normalized_percent(current: i32, max: i32) -> i32 {
    if max <= 0 {
        return 0;
    }
    ((current as f64 / max as f64) * 100.0).round() as i32
}

fn percent_to_ddc_raw(percent: i32, max: i32) -> i32 {
    let max = max.max(1);
    let clamped = percent.clamp(1, 100);
    ((clamped as f64 / 100.0) * max as f64)
        .round()
        .clamp(1.0, max as f64) as i32
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
        .map(|metadata| metadata.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
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
        .take_while(|character| character.is_ascii_digit())
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
            r#"
Display 1
   I2C bus:  /dev/i2c-7
   DRM connector: card1-DP-2

Display 2
   I2C bus:  /dev/i2c-8
   DRM connector: HDMI-A-1

Invalid display
   I2C bus: /dev/i2c-9
   DRM connector: card1-DP-3
"#,
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
