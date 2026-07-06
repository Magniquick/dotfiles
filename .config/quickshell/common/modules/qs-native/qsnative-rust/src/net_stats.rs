//! `NetStatsProvider` backend: traffic-rate smoothing/history, network source
//! sort/switch state, and pure `ip`/udev parsing helpers.
//!
//! The C++ `QsNativeNetStats` `QObject` owns one opaque [`NetStatsHandle`] and
//! calls the `extern "C"` surface synchronously on the Qt/main thread; there are
//! no worker threads. Stateful calls return a JSON snapshot the `QObject` mirrors
//! into its properties; pure transforms return owned strings freed with
//! `QsNative_Free`.

use std::collections::HashMap;
use std::fs;
use std::os::raw::c_char;
use std::path::{Path, PathBuf};
use std::process::Command;

use procfs::net::DeviceStatus;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::ffi::{c_string, from_cbor, into_c_string, into_cbor, QsNativeBytes};

#[derive(Debug, Clone, PartialEq, Eq)]
struct NetDevSample {
    rx_bytes: u64,
    tx_bytes: u64,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
struct SourceEntry {
    id: String,
    #[serde(rename = "type")]
    source_type: String,
    name: String,
    device: String,
    active: bool,
    connectable: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Default)]
struct EthernetMetadata {
    subsystem: String,
    label: String,
}

/// CBOR payload for [`QsNative_NetStats_Refresh`]; `rx_bytes`/`tx_bytes` are
/// omitted (not `null`) when `ok` is false, matching the prior JSON shape.
#[derive(Debug, Serialize)]
struct RefreshResult {
    ok: bool,
    error: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    rx_bytes: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tx_bytes: Option<f64>,
}

/// CBOR payload for the traffic-rate snapshot returned by
/// [`QsNative_NetStats_UpdateTrafficRates`] / [`QsNative_NetStats_ResetTraffic`].
/// The history fields stay pre-serialized JSON-array strings (unchanged shape);
/// only the FFI envelope moves from JSON text to CBOR.
#[derive(Debug, Serialize)]
struct TrafficSnapshot {
    #[serde(rename = "rxBytesPerSec")]
    rx_bytes_per_sec: f64,
    #[serde(rename = "txBytesPerSec")]
    tx_bytes_per_sec: f64,
    #[serde(rename = "trafficScaleMax")]
    traffic_scale_max: f64,
    #[serde(rename = "rxHistoryJson")]
    rx_history_json: String,
    #[serde(rename = "txHistoryJson")]
    tx_history_json: String,
}

#[derive(Debug, Default)]
struct TrafficState {
    last_rx_bytes: f64,
    last_tx_bytes: f64,
    last_sample_ms: f64,
    baseline_ready: bool,
    rx_history: Vec<f64>,
    tx_history: Vec<f64>,
}

#[derive(Debug, Clone, Copy)]
struct TrafficRates {
    rx_bytes_per_sec: f64,
    tx_bytes_per_sec: f64,
    traffic_scale_max: f64,
}

const TRAFFIC_HISTORY_SIZE: usize = 60;
const TRAFFIC_SCALE_FLOOR: f64 = 1024.0;
const MIN_TRAFFIC_SAMPLE_DELTA_MS: f64 = 600.0;
const TRAFFIC_EMA_ALPHA: f64 = 0.5;

/// Opaque per-instance state owned by the C++ `QsNativeNetStats` `QObject`.
///
/// Holds the cross-call traffic history/smoothing state plus the source-switch
/// bookkeeping; the scalar properties (device, rx/tx counters, per-sec rates,
/// error) are mirrored on the C++ side from the JSON snapshots returned here.
pub struct NetStatsHandle {
    traffic: TrafficState,
    source_entries_json: String,
    source_switching: bool,
    source_switching_name: String,
    source_error: String,
}

impl NetStatsHandle {
    fn new() -> Self {
        NetStatsHandle {
            traffic: TrafficState::default(),
            source_entries_json: "[]".to_owned(),
            source_switching: false,
            source_switching_name: String::new(),
            source_error: String::new(),
        }
    }
}

#[no_mangle]
pub extern "C" fn QsNative_NetStats_New() -> *mut NetStatsHandle {
    Box::into_raw(Box::new(NetStatsHandle::new()))
}

/// # Safety
/// `handle` must be null or a pointer from `QsNative_NetStats_New` not yet freed.
#[no_mangle]
pub unsafe extern "C" fn QsNative_NetStats_Delete(handle: *mut NetStatsHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Reads `/proc/net/dev` for `device` (borrowed C string). Returns a CBOR
/// object `{ok, error, rx_bytes?, tx_bytes?}`; `rx_bytes`/`tx_bytes` are only
/// present when `ok` is true. Stateless: does not touch the handle.
///
/// # Safety
/// `device` must be null or a valid NUL-terminated string for the call.
#[no_mangle]
pub unsafe extern "C" fn QsNative_NetStats_Refresh(device: *const c_char) -> QsNativeBytes {
    let device = c_string(device);
    let device = device.trim();
    if device.is_empty() {
        return into_cbor(&RefreshResult {
            ok: false,
            error: "interface is empty".to_owned(),
            rx_bytes: None,
            tx_bytes: None,
        });
    }
    let result = match read_net_dev(device) {
        #[expect(
            clippy::cast_precision_loss,
            reason = "byte counters are surfaced to QML as f64; precision loss only past 4 PB and QML numbers are f64 anyway"
        )]
        Ok(sample) => RefreshResult {
            ok: true,
            error: String::new(),
            rx_bytes: Some(sample.rx_bytes as f64),
            tx_bytes: Some(sample.tx_bytes as f64),
        },
        Err(error) => RefreshResult {
            ok: false,
            error,
            rx_bytes: None,
            tx_bytes: None,
        },
    };
    into_cbor(&result)
}

/// Folds a fresh cumulative sample into the EMA rates + history, returning the
/// traffic snapshot (rates, scale, history JSON).
///
/// # Safety
/// `handle` must be a valid pointer from `QsNative_NetStats_New`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_NetStats_UpdateTrafficRates(
    handle: *mut NetStatsHandle,
    rx_bytes: f64,
    tx_bytes: f64,
    now_ms: f64,
) -> QsNativeBytes {
    if handle.is_null() {
        return QsNativeBytes { ptr: core::ptr::null_mut(), len: 0 };
    }
    let handle = &mut *handle;
    let rates = handle.traffic.update(rx_bytes, tx_bytes, now_ms);
    traffic_snapshot_cbor(handle, rates)
}

/// Clears the traffic history and zeroes the rates, returning the reset snapshot.
///
/// # Safety
/// `handle` must be a valid pointer from `QsNative_NetStats_New`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_NetStats_ResetTraffic(handle: *mut NetStatsHandle) -> QsNativeBytes {
    if handle.is_null() {
        return QsNativeBytes { ptr: core::ptr::null_mut(), len: 0 };
    }
    let handle = &mut *handle;
    handle.traffic = TrafficState::default();
    let rates = TrafficRates {
        rx_bytes_per_sec: 0.0,
        tx_bytes_per_sec: 0.0,
        traffic_scale_max: TRAFFIC_SCALE_FLOOR,
    };
    traffic_snapshot_cbor(handle, rates)
}

/// Normalizes + sorts the CBOR-encoded source entries. On success rewrites the
/// stored entries and auto-clears the switch state if the switching source is
/// now active. Returns `{ok, error, <source snapshot>}` as JSON (unchanged;
/// only the input crossing moved to CBOR).
///
/// # Safety
/// `handle` valid; `(entries_ptr, entries_len)` must describe a readable CBOR
/// byte range for the call, or `entries_ptr` null.
#[no_mangle]
pub unsafe extern "C" fn QsNative_NetStats_SetSourceEntries(
    handle: *mut NetStatsHandle,
    entries_ptr: *const u8,
    entries_len: usize,
) -> *mut c_char {
    if handle.is_null() {
        return into_c_string("{}".to_owned());
    }
    let handle = &mut *handle;
    match from_cbor::<Vec<SourceEntry>>(entries_ptr, entries_len) {
        Some(entries) => {
            let entries = sort_source_entries(entries);
            let switch_complete = handle.source_switching
                && !handle.source_switching_name.is_empty()
                && entries
                    .iter()
                    .any(|entry| entry.active && entry.name == handle.source_switching_name);
            handle.source_entries_json =
                serde_json::to_string(&entries).unwrap_or_else(|_| "[]".to_owned());
            if switch_complete {
                handle.source_switching = false;
                handle.source_switching_name = String::new();
                handle.source_error = String::new();
            }
            into_c_string(source_snapshot_json(handle, true, ""))
        }
        None => into_c_string(source_snapshot_json(
            handle,
            false,
            "source entries: invalid payload",
        )),
    }
}

/// Marks a source switch as in flight. Returns `{ok, <source snapshot>}`; `ok`
/// is false if `name` is blank or a switch is already running.
///
/// # Safety
/// `handle` valid; `name` null or valid NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn QsNative_NetStats_BeginSourceSwitch(
    handle: *mut NetStatsHandle,
    name: *const c_char,
) -> *mut c_char {
    if handle.is_null() {
        return into_c_string("{}".to_owned());
    }
    let handle = &mut *handle;
    let name = c_string(name).trim().to_owned();
    if name.is_empty() || handle.source_switching {
        return into_c_string(source_snapshot_json(handle, false, ""));
    }
    handle.source_switching = true;
    handle.source_switching_name = name;
    handle.source_error = String::new();
    into_c_string(source_snapshot_json(handle, true, ""))
}

/// Records a switch failure message and clears the in-flight state. Returns the
/// source snapshot.
///
/// # Safety
/// `handle` valid; `message` null or valid NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn QsNative_NetStats_FailSourceSwitch(
    handle: *mut NetStatsHandle,
    message: *const c_char,
) -> *mut c_char {
    if handle.is_null() {
        return into_c_string("{}".to_owned());
    }
    let handle = &mut *handle;
    c_string(message).trim().clone_into(&mut handle.source_error);
    handle.source_switching = false;
    handle.source_switching_name = String::new();
    into_c_string(source_snapshot_json(handle, true, ""))
}

/// Clears the switch flag, name, and error. Returns the source snapshot.
///
/// # Safety
/// `handle` must be a valid pointer from `QsNative_NetStats_New`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_NetStats_ClearSourceSwitch(
    handle: *mut NetStatsHandle,
) -> *mut c_char {
    if handle.is_null() {
        return into_c_string("{}".to_owned());
    }
    let handle = &mut *handle;
    handle.source_switching = false;
    handle.source_switching_name = String::new();
    handle.source_error = String::new();
    into_c_string(source_snapshot_json(handle, true, ""))
}

/// Parses `ip -j -4 addr show` JSON (raw external text, passed through as-is);
/// returns the first `local/prefixlen` (or `local`) inet address as plain
/// text, or an empty string. Not JSON: crosses as a `char*`, not CBOR.
///
/// # Safety
/// `text` must be null or a valid NUL-terminated string for the call.
#[no_mangle]
pub unsafe extern "C" fn QsNative_NetStats_ParseIpAddressJson(text: *const c_char) -> *mut c_char {
    into_c_string(parse_ip_address_json(&c_string(text)))
}

/// Parses `ip -j route show default` JSON (raw external text, passed through
/// as-is); returns the first non-empty gateway as plain text, or an empty
/// string. Not JSON: crosses as a `char*`, not CBOR.
///
/// # Safety
/// `text` must be null or a valid NUL-terminated string for the call.
#[no_mangle]
pub unsafe extern "C" fn QsNative_NetStats_ParseGatewayJson(text: *const c_char) -> *mut c_char {
    into_c_string(parse_gateway_json(&c_string(text)))
}

/// Trims and replaces `_` with spaces in a udev-derived label.
///
/// # Safety
/// `text` must be null or a valid NUL-terminated string for the call.
#[no_mangle]
pub unsafe extern "C" fn QsNative_NetStats_NormalizeEthernetLabel(
    text: *const c_char,
) -> *mut c_char {
    into_c_string(normalize_ethernet_label_text(&c_string(text)))
}

/// Resolves ethernet/USB NIC metadata via sysfs + `udevadm`, returning a CBOR
/// object `{subsystem,label}` (empty fields on failure). Shells out synchronously.
///
/// # Safety
/// `device_name` must be null or a valid NUL-terminated string for the call.
#[no_mangle]
pub unsafe extern "C" fn QsNative_NetStats_EthernetMetadataJson(
    device_name: *const c_char,
) -> QsNativeBytes {
    let metadata = ethernet_metadata_for_device(&c_string(device_name)).unwrap_or_default();
    into_cbor(&metadata)
}

fn traffic_snapshot_cbor(handle: &NetStatsHandle, rates: TrafficRates) -> QsNativeBytes {
    let rx_history_json =
        serde_json::to_string(&handle.traffic.rx_history).unwrap_or_else(|_| "[]".to_owned());
    let tx_history_json =
        serde_json::to_string(&handle.traffic.tx_history).unwrap_or_else(|_| "[]".to_owned());
    into_cbor(&TrafficSnapshot {
        rx_bytes_per_sec: rates.rx_bytes_per_sec,
        tx_bytes_per_sec: rates.tx_bytes_per_sec,
        traffic_scale_max: rates.traffic_scale_max,
        rx_history_json,
        tx_history_json,
    })
}

fn source_snapshot_json(handle: &NetStatsHandle, ok: bool, error: &str) -> String {
    serde_json::json!({
        "ok": ok,
        "error": error,
        "sourceEntriesJson": handle.source_entries_json,
        "sourceSwitching": handle.source_switching,
        "sourceSwitchingName": handle.source_switching_name,
        "sourceError": handle.source_error,
    })
    .to_string()
}

fn read_net_dev(iface: &str) -> Result<NetDevSample, String> {
    let devices = procfs::net::dev_status().map_err(|err| format!("netdev: {err}"))?;
    sample_for_interface(&devices, iface)
}

fn sample_for_interface(
    devices: &HashMap<String, DeviceStatus>,
    iface: &str,
) -> Result<NetDevSample, String> {
    let device = devices
        .get(iface)
        .ok_or_else(|| format!("interface {iface} not found"))?;

    Ok(NetDevSample {
        rx_bytes: device.recv_bytes,
        tx_bytes: device.sent_bytes,
    })
}

fn sort_source_entries(mut entries: Vec<SourceEntry>) -> Vec<SourceEntry> {
    entries.sort_by(|a, b| {
        b.active
            .cmp(&a.active)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
            .then_with(|| a.device.to_lowercase().cmp(&b.device.to_lowercase()))
            .then_with(|| a.id.cmp(&b.id))
    });
    entries
}

fn parse_ip_address_json(text: &str) -> String {
    let Ok(entries) = serde_json::from_str::<Value>(text.trim()) else {
        return String::new();
    };
    entries
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|entry| entry.get("addr_info").and_then(Value::as_array))
        .flatten()
        .find_map(|item| {
            (item.get("family").and_then(Value::as_str) == Some("inet"))
                .then(|| item.get("local").and_then(Value::as_str))
                .flatten()
                .map(
                    |local| match item.get("prefixlen").and_then(Value::as_u64) {
                        Some(prefix) => format!("{local}/{prefix}"),
                        None => local.to_owned(),
                    },
                )
        })
        .unwrap_or_default()
}

fn parse_gateway_json(text: &str) -> String {
    let Ok(entries) = serde_json::from_str::<Value>(text.trim()) else {
        return String::new();
    };
    entries
        .as_array()
        .into_iter()
        .flatten()
        .find_map(|entry| {
            entry
                .get("gateway")
                .and_then(Value::as_str)
                .filter(|gateway| !gateway.is_empty())
                .map(str::to_owned)
        })
        .unwrap_or_default()
}

fn ethernet_metadata_for_device(device_name: &str) -> Option<EthernetMetadata> {
    let sysfs_path = sysfs_net_path(device_name)?;
    let subsystem = read_device_subsystem(&sysfs_path).unwrap_or_default();
    let label = if subsystem == "usb" {
        read_udev_label(&sysfs_path).unwrap_or_default()
    } else {
        String::new()
    };

    Some(EthernetMetadata { subsystem, label })
}

fn sysfs_net_path(device_name: &str) -> Option<PathBuf> {
    let name = device_name.trim();
    if name.is_empty()
        || name == "."
        || name == ".."
        || name.as_bytes().contains(&0)
        || name.contains('/')
    {
        return None;
    }
    Some(Path::new("/sys/class/net").join(name))
}

fn read_device_subsystem(sysfs_path: &Path) -> Option<String> {
    let subsystem_path = sysfs_path.join("device/subsystem");
    let target = fs::read_link(subsystem_path).ok()?;
    target
        .file_name()
        .and_then(|name| name.to_str())
        .map(|s| s.trim().to_owned())
        .filter(|subsystem| !subsystem.is_empty())
}

fn read_udev_label(sysfs_path: &Path) -> Option<String> {
    let output = Command::new("udevadm")
        .args(["info", "-q", "property", "-p"])
        .arg(sysfs_path)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    parse_udev_label(&String::from_utf8_lossy(&output.stdout))
}

fn parse_udev_label(properties: &str) -> Option<String> {
    const LABEL_KEYS: [&str; 4] = [
        "ID_MODEL_FROM_DATABASE",
        "ID_MODEL",
        "ID_VENDOR_FROM_DATABASE",
        "ID_VENDOR",
    ];

    LABEL_KEYS.iter().find_map(|key| {
        properties.lines().find_map(|line| {
            let (name, value) = line.split_once('=')?;
            (name == *key).then(|| normalize_ethernet_label_text(value))
        })
    })
}

fn normalize_ethernet_label_text(text: &str) -> String {
    text.trim().replace('_', " ")
}

fn apply_ema(previous: f64, sample: f64, alpha: f64) -> f64 {
    if !sample.is_finite() || sample < 0.0 {
        return 0.0;
    }
    if !previous.is_finite() || previous <= 0.0 {
        return sample;
    }
    let alpha = alpha.clamp(0.01, 0.99);
    previous * (1.0 - alpha) + sample * alpha
}

impl TrafficState {
    fn update(&mut self, rx_bytes: f64, tx_bytes: f64, now_ms: f64) -> TrafficRates {
        if !self.baseline_ready || self.last_sample_ms <= 0.0 || now_ms <= self.last_sample_ms {
            self.last_rx_bytes = rx_bytes;
            self.last_tx_bytes = tx_bytes;
            self.last_sample_ms = now_ms;
            self.baseline_ready = true;
            return self.rates(0.0, 0.0);
        }

        let delta_ms = now_ms - self.last_sample_ms;
        if delta_ms < MIN_TRAFFIC_SAMPLE_DELTA_MS {
            self.last_rx_bytes = rx_bytes;
            self.last_tx_bytes = tx_bytes;
            self.last_sample_ms = now_ms;
            return self.rates_from_history();
        }

        let delta_seconds = delta_ms / 1000.0;
        let rx_delta = rx_bytes - self.last_rx_bytes;
        let tx_delta = tx_bytes - self.last_tx_bytes;
        let (rx_rate, tx_rate) = if rx_delta >= 0.0 && tx_delta >= 0.0 && delta_seconds > 0.0 {
            let current = self.rates_from_history();
            (
                apply_ema(
                    current.rx_bytes_per_sec,
                    rx_delta / delta_seconds,
                    TRAFFIC_EMA_ALPHA,
                ),
                apply_ema(
                    current.tx_bytes_per_sec,
                    tx_delta / delta_seconds,
                    TRAFFIC_EMA_ALPHA,
                ),
            )
        } else {
            (0.0, 0.0)
        };

        self.push(rx_rate, tx_rate);
        self.last_rx_bytes = rx_bytes;
        self.last_tx_bytes = tx_bytes;
        self.last_sample_ms = now_ms;
        self.rates(rx_rate, tx_rate)
    }

    fn push(&mut self, rx_rate: f64, tx_rate: f64) {
        self.rx_history.push(sane_rate(rx_rate));
        self.tx_history.push(sane_rate(tx_rate));
        trim_history(&mut self.rx_history);
        trim_history(&mut self.tx_history);
    }

    fn rates(&self, rx_bytes_per_sec: f64, tx_bytes_per_sec: f64) -> TrafficRates {
        TrafficRates {
            rx_bytes_per_sec,
            tx_bytes_per_sec,
            traffic_scale_max: self.traffic_scale_max(),
        }
    }

    fn rates_from_history(&self) -> TrafficRates {
        self.rates(
            *self.rx_history.last().unwrap_or(&0.0),
            *self.tx_history.last().unwrap_or(&0.0),
        )
    }

    fn traffic_scale_max(&self) -> f64 {
        self.rx_history
            .iter()
            .chain(self.tx_history.iter())
            .copied()
            .fold(TRAFFIC_SCALE_FLOOR, f64::max)
    }
}

fn trim_history(history: &mut Vec<f64>) {
    if history.len() > TRAFFIC_HISTORY_SIZE {
        history.drain(0..history.len() - TRAFFIC_HISTORY_SIZE);
    }
}

fn sane_rate(rate: f64) -> f64 {
    if rate.is_finite() && rate > 0.0 {
        rate
    } else {
        0.0
    }
}

#[cfg(test)]
mod tests {
    use super::{
        parse_gateway_json, parse_ip_address_json, parse_udev_label, sample_for_interface,
        sort_source_entries, sysfs_net_path, DeviceStatus, HashMap, SourceEntry, TrafficState,
    };

    #[test]
    fn selects_interface_counters_from_procfs_status() {
        let devices = HashMap::from([(
            "enp0s20f0u2i1".to_owned(),
            device_status("enp0s20f0u2i1", 123_456, 654_321),
        )]);
        let sample = sample_for_interface(&devices, "enp0s20f0u2i1").expect("sample");

        assert_eq!(sample.rx_bytes, 123_456);
        assert_eq!(sample.tx_bytes, 654_321);
    }

    #[test]
    fn reports_missing_interface() {
        let devices = HashMap::from([("lo".to_owned(), device_status("lo", 10, 20))]);
        let error = sample_for_interface(&devices, "wlan0").expect_err("missing interface");

        assert!(error.contains("interface wlan0 not found"));
    }

    #[test]
    fn parses_ip_addr_json() {
        let raw = r#"[{"addr_info":[{"family":"inet6","local":"fe80::1"},{"family":"inet","local":"192.168.1.5","prefixlen":24}]}]"#;
        assert_eq!(parse_ip_address_json(raw), "192.168.1.5/24");
    }

    #[test]
    fn parses_default_gateway_json() {
        let raw = r#"[{"dst":"default","gateway":"192.168.1.1"}]"#;
        assert_eq!(parse_gateway_json(raw), "192.168.1.1");
    }

    #[test]
    fn sorts_sources_active_first_then_name() {
        let raw = r#"[
            {"id":"wifi:wlan0:z","type":"wifi","name":"z","device":"wlan0","active":false,"connectable":true},
            {"id":"wifi:wlan0:a","type":"wifi","name":"a","device":"wlan0","active":true,"connectable":true}
        ]"#;
        let entries: Vec<SourceEntry> = serde_json::from_str(raw).expect("parses");
        let entries = sort_source_entries(entries);
        assert_eq!(entries[0].name, "a");
        assert!(entries[0].active);
    }

    #[test]
    fn rejects_unsafe_sysfs_interface_names() {
        assert!(sysfs_net_path("enp0s20f0u2i1").is_some());
        assert!(sysfs_net_path("../eth0").is_none());
        assert!(sysfs_net_path("nested/eth0").is_none());
        assert!(sysfs_net_path("").is_none());
    }

    #[test]
    fn picks_model_then_vendor_udev_label() {
        let raw = "\
ID_VENDOR_FROM_DATABASE=Fallback Vendor
ID_MODEL=USB_NIC_Model
ID_VENDOR=Raw_Vendor
";
        assert_eq!(parse_udev_label(raw).as_deref(), Some("USB NIC Model"));
    }

    #[test]
    #[expect(
        clippy::float_cmp,
        reason = "these EMA inputs yield exact f64 results (0.0 and 1024.0), so exact equality is the intended assertion"
    )]
    fn computes_traffic_rates_with_ema_history() {
        let mut state = TrafficState::default();
        let first = state.update(100.0, 50.0, 1000.0);
        assert_eq!(first.rx_bytes_per_sec, 0.0);

        let second = state.update(1124.0, 1074.0, 2000.0);
        assert_eq!(second.rx_bytes_per_sec, 1024.0);
        assert_eq!(second.tx_bytes_per_sec, 1024.0);
        assert_eq!(state.rx_history, vec![1024.0]);
    }

    fn device_status(name: &str, recv_bytes: u64, sent_bytes: u64) -> DeviceStatus {
        DeviceStatus {
            name: name.to_owned(),
            recv_bytes,
            recv_packets: 0,
            recv_errs: 0,
            recv_drop: 0,
            recv_fifo: 0,
            recv_frame: 0,
            recv_compressed: 0,
            recv_multicast: 0,
            sent_bytes,
            sent_packets: 0,
            sent_errs: 0,
            sent_drop: 0,
            sent_fifo: 0,
            sent_colls: 0,
            sent_carrier: 0,
            sent_compressed: 0,
        }
    }
}
