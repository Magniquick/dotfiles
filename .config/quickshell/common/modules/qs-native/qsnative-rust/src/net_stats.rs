use core::pin::Pin;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use cxx_qt::CxxQtType;
use cxx_qt_lib::QString;
use procfs::net::DeviceStatus;
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Default)]
pub struct NetStatsProviderRust {
    device: QString,
    rx_bytes: f64,
    tx_bytes: f64,
    rx_bytes_per_sec: f64,
    tx_bytes_per_sec: f64,
    rx_history_json: QString,
    tx_history_json: QString,
    traffic_scale_max: f64,
    source_entries_json: QString,
    source_switching: bool,
    source_switching_name: QString,
    source_error: QString,
    error: QString,
    traffic: TrafficState,
}

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

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qobject]
        #[qproperty(QString, device)]
        #[qproperty(f64, rx_bytes, cxx_name = "rx_bytes")]
        #[qproperty(f64, tx_bytes, cxx_name = "tx_bytes")]
        #[qproperty(f64, rx_bytes_per_sec, cxx_name = "rxBytesPerSec")]
        #[qproperty(f64, tx_bytes_per_sec, cxx_name = "txBytesPerSec")]
        #[qproperty(QString, rx_history_json, cxx_name = "rxHistoryJson")]
        #[qproperty(QString, tx_history_json, cxx_name = "txHistoryJson")]
        #[qproperty(f64, traffic_scale_max, cxx_name = "trafficScaleMax")]
        #[qproperty(QString, source_entries_json, cxx_name = "sourceEntriesJson")]
        #[qproperty(bool, source_switching, cxx_name = "sourceSwitching")]
        #[qproperty(QString, source_switching_name, cxx_name = "sourceSwitchingName")]
        #[qproperty(QString, source_error, cxx_name = "sourceError")]
        #[qproperty(QString, error)]
        type NetStatsProvider = super::NetStatsProviderRust;

        #[qsignal]
        #[cxx_name = "sampleReady"]
        fn sample_ready(self: Pin<&mut Self>, rx_bytes: f64, tx_bytes: f64);
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qinvokable]
        fn refresh(self: Pin<&mut NetStatsProvider>) -> bool;

        #[qinvokable]
        #[cxx_name = "updateTrafficRates"]
        fn update_traffic_rates(
            self: Pin<&mut NetStatsProvider>,
            rx_bytes: f64,
            tx_bytes: f64,
            now_ms: f64,
        );

        #[qinvokable]
        #[cxx_name = "resetTraffic"]
        fn reset_traffic(self: Pin<&mut NetStatsProvider>);

        #[qinvokable]
        #[cxx_name = "setSourceEntries"]
        fn set_source_entries(self: Pin<&mut NetStatsProvider>, entries_json: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "beginSourceSwitch"]
        fn begin_source_switch(self: Pin<&mut NetStatsProvider>, name: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "failSourceSwitch"]
        fn fail_source_switch(self: Pin<&mut NetStatsProvider>, message: &QString);

        #[qinvokable]
        #[cxx_name = "clearSourceSwitch"]
        fn clear_source_switch(self: Pin<&mut NetStatsProvider>);

        #[qinvokable]
        #[cxx_name = "parseIpAddressJson"]
        fn parse_ip_address_json(self: &NetStatsProvider, text: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "parseGatewayJson"]
        fn parse_gateway_json(self: &NetStatsProvider, text: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "normalizeEthernetLabel"]
        fn normalize_ethernet_label(self: &NetStatsProvider, text: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "ethernetMetadataJson"]
        fn ethernet_metadata_json(self: &NetStatsProvider, device_name: &QString) -> QString;
    }

    impl cxx_qt::Initialize for NetStatsProvider {}
}

impl cxx_qt::Initialize for ffi::NetStatsProvider {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut().reset_traffic();
        self.as_mut().set_source_entries_json(QString::from("[]"));
    }
}

impl ffi::NetStatsProvider {
    pub fn refresh(mut self: Pin<&mut Self>) -> bool {
        let device = self.device().to_string();
        let device = device.trim();
        if device.is_empty() {
            self.as_mut().set_error(QString::from("interface is empty"));
            return false;
        }

        match read_net_dev(device) {
            Ok(sample) => {
                let rx_bytes = sample.rx_bytes as f64;
                let tx_bytes = sample.tx_bytes as f64;
                self.as_mut().set_error(QString::default());
                self.as_mut().set_rx_bytes(rx_bytes);
                self.as_mut().set_tx_bytes(tx_bytes);
                self.as_mut().sample_ready(rx_bytes, tx_bytes);
                true
            }
            Err(error) => {
                self.as_mut().set_error(QString::from(error.as_str()));
                false
            }
        }
    }

    pub fn update_traffic_rates(
        mut self: Pin<&mut Self>,
        rx_bytes: f64,
        tx_bytes: f64,
        now_ms: f64,
    ) {
        let rates = self
            .as_mut()
            .rust_mut()
            .as_mut()
            .get_mut()
            .traffic
            .update(rx_bytes, tx_bytes, now_ms);
        self.as_mut().set_rx_bytes_per_sec(rates.rx_bytes_per_sec);
        self.as_mut().set_tx_bytes_per_sec(rates.tx_bytes_per_sec);
        self.as_mut().set_traffic_scale_max(rates.traffic_scale_max);
        self.as_mut().sync_history_json();
    }

    pub fn reset_traffic(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().as_mut().get_mut().traffic = TrafficState::default();
        self.as_mut().set_rx_bytes_per_sec(0.0);
        self.as_mut().set_tx_bytes_per_sec(0.0);
        self.as_mut().set_traffic_scale_max(TRAFFIC_SCALE_FLOOR);
        self.as_mut().sync_history_json();
    }

    pub fn set_source_entries(mut self: Pin<&mut Self>, entries_json: &QString) -> bool {
        match normalize_source_entries(&entries_json.to_string()) {
            Ok(entries) => {
                let switching_name = self.source_switching_name().to_string();
                let switch_complete = *self.source_switching()
                    && !switching_name.is_empty()
                    && entries
                        .iter()
                        .any(|entry| entry.active && entry.name == switching_name);
                let json = serde_json::to_string(&entries).unwrap_or_else(|_| "[]".to_owned());
                self.as_mut().set_source_entries_json(QString::from(json));
                if switch_complete {
                    self.as_mut().clear_source_switch();
                }
                true
            }
            Err(error) => {
                self.as_mut().set_error(QString::from(error));
                false
            }
        }
    }

    pub fn begin_source_switch(mut self: Pin<&mut Self>, name: &QString) -> bool {
        let name = name.to_string().trim().to_owned();
        if name.is_empty() || *self.source_switching() {
            return false;
        }
        self.as_mut().set_source_switching(true);
        self.as_mut().set_source_switching_name(QString::from(name));
        self.as_mut().set_source_error(QString::default());
        true
    }

    pub fn fail_source_switch(mut self: Pin<&mut Self>, message: &QString) {
        self.as_mut()
            .set_source_error(QString::from(message.to_string().trim()));
        self.as_mut().set_source_switching(false);
        self.as_mut().set_source_switching_name(QString::default());
    }

    pub fn clear_source_switch(mut self: Pin<&mut Self>) {
        self.as_mut().set_source_switching(false);
        self.as_mut().set_source_switching_name(QString::default());
        self.as_mut().set_source_error(QString::default());
    }

    pub fn parse_ip_address_json(&self, text: &QString) -> QString {
        QString::from(parse_ip_address_json(&text.to_string()))
    }

    pub fn parse_gateway_json(&self, text: &QString) -> QString {
        QString::from(parse_gateway_json(&text.to_string()))
    }

    pub fn normalize_ethernet_label(&self, text: &QString) -> QString {
        QString::from(normalize_ethernet_label_text(&text.to_string()))
    }

    pub fn ethernet_metadata_json(&self, device_name: &QString) -> QString {
        let metadata = ethernet_metadata_for_device(&device_name.to_string()).unwrap_or_default();
        QString::from(serde_json::to_string(&metadata).unwrap_or_else(|_| "{}".to_owned()))
    }

    fn sync_history_json(mut self: Pin<&mut Self>) {
        let (rx_history_json, tx_history_json) = {
            let provider = self.as_ref();
            let rust = provider.rust();
            (
                serde_json::to_string(&rust.traffic.rx_history).unwrap_or_else(|_| "[]".to_owned()),
                serde_json::to_string(&rust.traffic.tx_history).unwrap_or_else(|_| "[]".to_owned()),
            )
        };
        self.as_mut()
            .set_rx_history_json(QString::from(rx_history_json));
        self.as_mut()
            .set_tx_history_json(QString::from(tx_history_json));
    }
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

fn normalize_source_entries(raw_json: &str) -> Result<Vec<SourceEntry>, String> {
    let mut entries: Vec<SourceEntry> =
        serde_json::from_str(raw_json).map_err(|error| format!("source entries: {error}"))?;
    entries.sort_by(|a, b| {
        b.active
            .cmp(&a.active)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
            .then_with(|| a.device.to_lowercase().cmp(&b.device.to_lowercase()))
            .then_with(|| a.id.cmp(&b.id))
    });
    Ok(entries)
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
        normalize_source_entries, parse_gateway_json, parse_ip_address_json, parse_udev_label,
        sample_for_interface, sysfs_net_path, DeviceStatus, HashMap, TrafficState,
    };

    #[test]
    fn selects_interface_counters_from_procfs_status() {
        let devices = HashMap::from([(
            "enp0s20f0u2i1".to_owned(),
            device_status("enp0s20f0u2i1", 123456, 654321),
        )]);
        let sample = sample_for_interface(&devices, "enp0s20f0u2i1").expect("sample");

        assert_eq!(sample.rx_bytes, 123456);
        assert_eq!(sample.tx_bytes, 654321);
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
        let entries = normalize_source_entries(raw).expect("entries");
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
