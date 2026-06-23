use core::pin::Pin;
use std::ffi::CString;
use std::fs::{read_dir, read_to_string, File};
use std::mem::size_of;
use std::os::fd::AsRawFd;
use std::path::Path;
use std::process::Command;
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use procfs::process::Process;
use procfs::{
    CpuPressure, Current, CurrentSI, IoPressure, KernelStats, Meminfo, MemoryPressure, Uptime,
};
use serde_json::Value;

const BTRFS_MIN_UNALLOCATED_THRESH: u64 = 16 * 1024 * 1024;
const BTRFS_IOCTL_MAGIC: u32 = 0x94;
const BTRFS_UUID_SIZE: usize = 16;
const BTRFS_FSID_SIZE: usize = 16;
const BTRFS_DEVICE_PATH_NAME_MAX: usize = 1024;

const BTRFS_BLOCK_GROUP_DATA: u64 = 1;
const BTRFS_BLOCK_GROUP_SYSTEM: u64 = 1 << 1;
const BTRFS_BLOCK_GROUP_METADATA: u64 = 1 << 2;
const BTRFS_BLOCK_GROUP_RAID1: u64 = 1 << 4;
const BTRFS_BLOCK_GROUP_DUP: u64 = 1 << 5;
const BTRFS_BLOCK_GROUP_RAID10: u64 = 1 << 6;
const BTRFS_BLOCK_GROUP_RAID5: u64 = 1 << 7;
const BTRFS_BLOCK_GROUP_RAID6: u64 = 1 << 8;
const BTRFS_BLOCK_GROUP_RAID1C3: u64 = 1 << 9;
const BTRFS_BLOCK_GROUP_RAID1C4: u64 = 1 << 10;
const BTRFS_BLOCK_GROUP_RAID56_MASK: u64 = BTRFS_BLOCK_GROUP_RAID5 | BTRFS_BLOCK_GROUP_RAID6;
const BTRFS_SPACE_INFO_GLOBAL_RSV: u64 = 1 << 49;

#[derive(Default)]
pub struct SysInfoProviderRust {
    cpu: f64,
    mem: i32,
    mem_used: QString,
    mem_total: QString,
    disk: i32,
    disk_worst_case: i32,
    disk_btrfs_available: bool,
    disk_btrfs_free_est_gib: f64,
    disk_btrfs_free_min_gib: f64,
    disk_health: QString,
    disk_wear: QString,
    disk_device: QString,
    temp: f64,
    uptime: QString,
    psi_cpu_some: f64,
    psi_cpu_full: f64,
    psi_mem_some: f64,
    psi_mem_full: f64,
    psi_io_some: f64,
    psi_io_full: f64,
    error: QString,
    last_cpu_total: f64,
    last_cpu_idle: f64,
    last_disk_health_ms: i64,
    disk_health_cache: String,
    disk_wear_cache: String,
    last_btrfs_ms: i64,
    btrfs_available_cache: bool,
    btrfs_disk_cache: i32,
    btrfs_free_est_cache: f64,
    btrfs_free_min_cache: f64,
    btrfs_worst_case_cache: i32,
}

#[derive(Debug, Clone)]
struct SysInfoSnapshot {
    cpu: f64,
    mem: i32,
    mem_used: String,
    mem_total: String,
    disk: i32,
    disk_worst_case: i32,
    disk_btrfs_available: bool,
    disk_btrfs_free_est_gib: f64,
    disk_btrfs_free_min_gib: f64,
    disk_device: String,
    temp: f64,
    uptime: String,
    psi_cpu_some: f64,
    psi_cpu_full: f64,
    psi_mem_some: f64,
    psi_mem_full: f64,
    psi_io_some: f64,
    psi_io_full: f64,
    error: String,
    cpu_total: f64,
    cpu_idle: f64,
    last_disk_health_ms: i64,
    disk_health_cache: String,
    disk_wear_cache: String,
    last_btrfs_ms: i64,
    btrfs_available_cache: bool,
    btrfs_disk_cache: i32,
    btrfs_free_est_cache: f64,
    btrfs_free_min_cache: f64,
    btrfs_worst_case_cache: i32,
}

#[derive(Debug, Clone)]
struct SysInfoState {
    disk_device: String,
    previous_cpu: f64,
    last_cpu_total: f64,
    last_cpu_idle: f64,
    last_disk_health_ms: i64,
    disk_health_cache: String,
    disk_wear_cache: String,
    last_btrfs_ms: i64,
    btrfs_available_cache: bool,
    btrfs_disk_cache: i32,
    btrfs_free_est_cache: f64,
    btrfs_free_min_cache: f64,
    btrfs_worst_case_cache: i32,
}

#[derive(Default, Debug, Clone, Copy)]
struct BtrfsUsageMetrics {
    available: bool,
    free_est_gib: f64,
    free_min_gib: f64,
    used_pct: i32,
    worst_pct: i32,
}

#[repr(C)]
#[derive(Default, Clone, Copy)]
struct BtrfsIoctlSpaceInfo {
    flags: u64,
    total_bytes: u64,
    used_bytes: u64,
}

#[repr(C)]
#[derive(Default, Clone, Copy)]
struct BtrfsIoctlSpaceArgs {
    space_slots: u64,
    total_spaces: u64,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct BtrfsIoctlDevInfoArgs {
    devid: u64,
    uuid: [u8; BTRFS_UUID_SIZE],
    bytes_used: u64,
    total_bytes: u64,
    fsid: [u8; BTRFS_UUID_SIZE],
    unused: [u64; 377],
    path: [u8; BTRFS_DEVICE_PATH_NAME_MAX],
}

impl Default for BtrfsIoctlDevInfoArgs {
    fn default() -> Self {
        Self {
            devid: 0,
            uuid: [0; BTRFS_UUID_SIZE],
            bytes_used: 0,
            total_bytes: 0,
            fsid: [0; BTRFS_UUID_SIZE],
            unused: [0; 377],
            path: [0; BTRFS_DEVICE_PATH_NAME_MAX],
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
struct BtrfsIoctlFsInfoArgs {
    max_id: u64,
    num_devices: u64,
    fsid: [u8; BTRFS_FSID_SIZE],
    nodesize: u32,
    sectorsize: u32,
    clone_alignment: u32,
    csum_type: u16,
    csum_size: u16,
    flags: u64,
    generation: u64,
    metadata_uuid: [u8; BTRFS_FSID_SIZE],
    reserved: [u8; 944],
}

impl Default for BtrfsIoctlFsInfoArgs {
    fn default() -> Self {
        Self {
            max_id: 0,
            num_devices: 0,
            fsid: [0; BTRFS_FSID_SIZE],
            nodesize: 0,
            sectorsize: 0,
            clone_alignment: 0,
            csum_type: 0,
            csum_size: 0,
            flags: 0,
            generation: 0,
            metadata_uuid: [0; BTRFS_FSID_SIZE],
            reserved: [0; 944],
        }
    }
}

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    impl cxx_qt::Threading for SysInfoProvider {}

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qobject]
        #[qproperty(f64, cpu)]
        #[qproperty(i32, mem)]
        #[qproperty(QString, mem_used, cxx_name = "mem_used")]
        #[qproperty(QString, mem_total, cxx_name = "mem_total")]
        #[qproperty(i32, disk)]
        #[qproperty(i32, disk_worst_case, cxx_name = "disk_worst_case")]
        #[qproperty(bool, disk_btrfs_available, cxx_name = "disk_btrfs_available")]
        #[qproperty(f64, disk_btrfs_free_est_gib, cxx_name = "disk_btrfs_free_est_gib")]
        #[qproperty(f64, disk_btrfs_free_min_gib, cxx_name = "disk_btrfs_free_min_gib")]
        #[qproperty(QString, disk_health, cxx_name = "disk_health")]
        #[qproperty(QString, disk_wear, cxx_name = "disk_wear")]
        #[qproperty(QString, disk_device, cxx_name = "disk_device")]
        #[qproperty(f64, temp)]
        #[qproperty(QString, uptime)]
        #[qproperty(f64, psi_cpu_some, cxx_name = "psi_cpu_some")]
        #[qproperty(f64, psi_cpu_full, cxx_name = "psi_cpu_full")]
        #[qproperty(f64, psi_mem_some, cxx_name = "psi_mem_some")]
        #[qproperty(f64, psi_mem_full, cxx_name = "psi_mem_full")]
        #[qproperty(f64, psi_io_some, cxx_name = "psi_io_some")]
        #[qproperty(f64, psi_io_full, cxx_name = "psi_io_full")]
        #[qproperty(QString, error)]
        type SysInfoProvider = super::SysInfoProviderRust;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qinvokable]
        fn refresh(self: Pin<&mut SysInfoProvider>) -> bool;
    }

    impl cxx_qt::Initialize for SysInfoProvider {}
}

impl cxx_qt::Initialize for ffi::SysInfoProvider {
    fn initialize(mut self: Pin<&mut Self>) {
        if self.disk_device().to_string().is_empty() {
            self.as_mut()
                .set_disk_device(QString::from(default_disk_device()));
        }
    }
}

impl ffi::SysInfoProvider {
    pub fn refresh(self: Pin<&mut Self>) -> bool {
        let state = self.as_ref().snapshot_state();
        let qt_thread = self.as_ref().qt_thread();

        thread::spawn(move || {
            let snapshot = read_snapshot(state);
            let _ = qt_thread.queue(move |mut provider| {
                provider.as_mut().apply_snapshot(snapshot);
            });
        });

        true
    }

    fn snapshot_state(self: Pin<&Self>) -> SysInfoState {
        let rust = self.rust();
        let disk_device = self.disk_device().to_string();
        SysInfoState {
            disk_device: if disk_device.is_empty() {
                default_disk_device()
            } else {
                disk_device
            },
            previous_cpu: rust.cpu,
            last_cpu_total: rust.last_cpu_total,
            last_cpu_idle: rust.last_cpu_idle,
            last_disk_health_ms: rust.last_disk_health_ms,
            disk_health_cache: rust.disk_health_cache.clone(),
            disk_wear_cache: rust.disk_wear_cache.clone(),
            last_btrfs_ms: rust.last_btrfs_ms,
            btrfs_available_cache: rust.btrfs_available_cache,
            btrfs_disk_cache: rust.btrfs_disk_cache,
            btrfs_free_est_cache: rust.btrfs_free_est_cache,
            btrfs_free_min_cache: rust.btrfs_free_min_cache,
            btrfs_worst_case_cache: rust.btrfs_worst_case_cache,
        }
    }

    fn apply_snapshot(mut self: Pin<&mut Self>, snapshot: SysInfoSnapshot) {
        self.as_mut().set_cpu(snapshot.cpu);
        self.as_mut().set_mem(snapshot.mem);
        self.as_mut().set_mem_used(QString::from(snapshot.mem_used));
        self.as_mut()
            .set_mem_total(QString::from(snapshot.mem_total));
        self.as_mut().set_disk(snapshot.disk);
        self.as_mut().set_disk_worst_case(snapshot.disk_worst_case);
        self.as_mut()
            .set_disk_btrfs_available(snapshot.disk_btrfs_available);
        self.as_mut()
            .set_disk_btrfs_free_est_gib(snapshot.disk_btrfs_free_est_gib);
        self.as_mut()
            .set_disk_btrfs_free_min_gib(snapshot.disk_btrfs_free_min_gib);
        self.as_mut()
            .set_disk_health(QString::from(snapshot.disk_health_cache.clone()));
        self.as_mut()
            .set_disk_wear(QString::from(snapshot.disk_wear_cache.clone()));
        self.as_mut()
            .set_disk_device(QString::from(snapshot.disk_device));
        self.as_mut().set_temp(snapshot.temp);
        self.as_mut().set_uptime(QString::from(snapshot.uptime));
        self.as_mut().set_psi_cpu_some(snapshot.psi_cpu_some);
        self.as_mut().set_psi_cpu_full(snapshot.psi_cpu_full);
        self.as_mut().set_psi_mem_some(snapshot.psi_mem_some);
        self.as_mut().set_psi_mem_full(snapshot.psi_mem_full);
        self.as_mut().set_psi_io_some(snapshot.psi_io_some);
        self.as_mut().set_psi_io_full(snapshot.psi_io_full);
        self.as_mut().set_error(QString::from(snapshot.error));

        let mut rust = self.rust_mut();
        let rust = rust.as_mut().get_mut();
        rust.last_cpu_total = snapshot.cpu_total;
        rust.last_cpu_idle = snapshot.cpu_idle;
        rust.last_disk_health_ms = snapshot.last_disk_health_ms;
        rust.disk_health_cache = snapshot.disk_health_cache;
        rust.disk_wear_cache = snapshot.disk_wear_cache;
        rust.last_btrfs_ms = snapshot.last_btrfs_ms;
        rust.btrfs_available_cache = snapshot.btrfs_available_cache;
        rust.btrfs_disk_cache = snapshot.btrfs_disk_cache;
        rust.btrfs_free_est_cache = snapshot.btrfs_free_est_cache;
        rust.btrfs_free_min_cache = snapshot.btrfs_free_min_cache;
        rust.btrfs_worst_case_cache = snapshot.btrfs_worst_case_cache;
    }
}

fn read_snapshot(mut state: SysInfoState) -> SysInfoSnapshot {
    let mut errors = Vec::new();
    let mut cpu_total = 0.0;
    let mut cpu_idle = 0.0;
    let mut cpu = state.previous_cpu;

    match KernelStats::current() {
        Ok(stats) => {
            cpu_total = cpu_total_ticks(&stats.total);
            cpu_idle = (stats.total.idle + stats.total.iowait.unwrap_or(0)) as f64;
            if state.last_cpu_total != 0.0 && cpu_total > state.last_cpu_total {
                let dt = cpu_total - state.last_cpu_total;
                let di = (cpu_idle - state.last_cpu_idle).clamp(0.0, dt);
                cpu = 100.0 * (1.0 - (di / dt));
            }
        }
        Err(error) => errors.push(format!("stat: {error}")),
    }

    let (mem, mem_used, mem_total) = match Meminfo::current() {
        Ok(meminfo) if meminfo.mem_total > 0 => {
            let total_kib = meminfo.mem_total;
            let avail_kib = meminfo.mem_available.unwrap_or(meminfo.mem_free);
            let used_kib = total_kib.saturating_sub(avail_kib);
            (
                ((100.0 * used_kib as f64) / total_kib as f64) as i32,
                format_gib(used_kib as f64),
                format_gib(total_kib as f64),
            )
        }
        Ok(_) => {
            errors.push("MemTotal is zero".to_owned());
            (0, String::new(), String::new())
        }
        Err(error) => {
            errors.push(format!("meminfo: {error}"));
            (0, String::new(), String::new())
        }
    };

    let root_fs_type = root_fs_type(&mut errors);
    let mut disk = read_disk_percent(&mut errors);
    let mut disk_worst_case = disk;
    let mut disk_btrfs_available = false;
    let mut disk_btrfs_free_est_gib = 0.0;
    let mut disk_btrfs_free_min_gib = 0.0;

    if root_fs_type == "btrfs" {
        let now = now_ms();
        if now - state.last_btrfs_ms > 30_000 {
            let metrics = read_btrfs_usage_metrics();
            state.btrfs_available_cache = metrics.available;
            if metrics.available {
                state.btrfs_disk_cache = metrics.used_pct;
                state.btrfs_free_est_cache = metrics.free_est_gib;
                state.btrfs_free_min_cache = metrics.free_min_gib;
                state.btrfs_worst_case_cache = metrics.worst_pct;
            }
            state.last_btrfs_ms = now;
        }

        disk_btrfs_available = state.btrfs_available_cache;
        disk_btrfs_free_est_gib = state.btrfs_free_est_cache;
        disk_btrfs_free_min_gib = state.btrfs_free_min_cache;
        if state.btrfs_available_cache {
            disk = state.btrfs_disk_cache;
            disk_worst_case = state.btrfs_worst_case_cache;
        }
    }

    let temp = read_temperature();
    let uptime = match Uptime::current() {
        Ok(uptime) => format_uptime(uptime.uptime.max(0.0) as u64),
        Err(error) => {
            errors.push(format!("uptime: {error}"));
            format_uptime(0)
        }
    };

    let (psi_cpu_some, psi_cpu_full) = match CpuPressure::current() {
        Ok(pressure) => (pressure.some.avg10 as f64, pressure.full.avg10 as f64),
        Err(error) => {
            push_missing_tolerant_error(&mut errors, "psi cpu", error);
            (0.0, 0.0)
        }
    };
    let (psi_mem_some, psi_mem_full) = match MemoryPressure::current() {
        Ok(pressure) => (pressure.some.avg10 as f64, pressure.full.avg10 as f64),
        Err(error) => {
            push_missing_tolerant_error(&mut errors, "psi memory", error);
            (0.0, 0.0)
        }
    };
    let (psi_io_some, psi_io_full) = match IoPressure::current() {
        Ok(pressure) => (pressure.some.avg10 as f64, pressure.full.avg10 as f64),
        Err(error) => {
            push_missing_tolerant_error(&mut errors, "psi io", error);
            (0.0, 0.0)
        }
    };

    let now = now_ms();
    if state.disk_health_cache.is_empty() || now - state.last_disk_health_ms > 6 * 60 * 60 * 1000 {
        match run_smartctl_json(&state.disk_device) {
            Some(smart) => {
                state.disk_health_cache = smart_health_label(&smart);
                state.disk_wear_cache = smart_wear_label(&smart);
            }
            None => {
                state.disk_health_cache = "Unknown (smartctl missing)".to_owned();
                state.disk_wear_cache = "Unknown".to_owned();
            }
        }
        state.last_disk_health_ms = now;
    }

    SysInfoSnapshot {
        cpu,
        mem,
        mem_used,
        mem_total,
        disk,
        disk_worst_case,
        disk_btrfs_available,
        disk_btrfs_free_est_gib,
        disk_btrfs_free_min_gib,
        disk_device: state.disk_device,
        temp,
        uptime,
        psi_cpu_some,
        psi_cpu_full,
        psi_mem_some,
        psi_mem_full,
        psi_io_some,
        psi_io_full,
        error: errors.join("; "),
        cpu_total,
        cpu_idle,
        last_disk_health_ms: state.last_disk_health_ms,
        disk_health_cache: state.disk_health_cache,
        disk_wear_cache: state.disk_wear_cache,
        last_btrfs_ms: state.last_btrfs_ms,
        btrfs_available_cache: state.btrfs_available_cache,
        btrfs_disk_cache: state.btrfs_disk_cache,
        btrfs_free_est_cache: state.btrfs_free_est_cache,
        btrfs_free_min_cache: state.btrfs_free_min_cache,
        btrfs_worst_case_cache: state.btrfs_worst_case_cache,
    }
}

fn cpu_total_ticks(cpu: &procfs::CpuTime) -> f64 {
    (cpu.user
        + cpu.nice
        + cpu.system
        + cpu.idle
        + cpu.iowait.unwrap_or(0)
        + cpu.irq.unwrap_or(0)
        + cpu.softirq.unwrap_or(0)
        + cpu.steal.unwrap_or(0)
        + cpu.guest.unwrap_or(0)
        + cpu.guest_nice.unwrap_or(0)) as f64
}

fn root_fs_type(errors: &mut Vec<String>) -> String {
    match Process::myself().and_then(|process| process.mountinfo()) {
        Ok(mounts) => mounts
            .into_iter()
            .find(|mount| mount.mount_point == Path::new("/"))
            .map(|mount| mount.fs_type)
            .unwrap_or_default(),
        Err(error) => {
            errors.push(format!("mountinfo: {error}"));
            String::new()
        }
    }
}

fn read_disk_percent(errors: &mut Vec<String>) -> i32 {
    let path = CString::new("/").expect("literal path has no nul");
    let mut stats = std::mem::MaybeUninit::<libc::statvfs>::uninit();
    let result = unsafe { libc::statvfs(path.as_ptr(), stats.as_mut_ptr()) };
    if result != 0 {
        errors.push("failed to stat filesystem".to_owned());
        return 0;
    }

    let stats = unsafe { stats.assume_init() };
    let total = stats.f_blocks as f64 * stats.f_frsize as f64;
    let avail = stats.f_bavail as f64 * stats.f_frsize as f64;
    if total > 0.0 {
        ((100.0 * (total - avail)) / total) as i32
    } else {
        0
    }
}

fn read_temperature() -> f64 {
    let zones = match read_dir("/sys/class/thermal") {
        Ok(entries) => entries
            .filter_map(Result::ok)
            .filter(|entry| {
                entry
                    .file_name()
                    .to_str()
                    .is_some_and(|name| name.starts_with("thermal_zone"))
            })
            .map(|entry| entry.path())
            .collect::<Vec<_>>(),
        Err(_) => return 0.0,
    };

    for zone in &zones {
        if read_trimmed(zone.join("type")).as_deref() == Some("x86_pkg_temp") {
            let temp = read_zone_temp(zone);
            if temp > 0.0 {
                return temp;
            }
        }
    }

    zones
        .iter()
        .map(|zone| read_zone_temp(zone))
        .find(|temp| *temp > 0.0)
        .unwrap_or(0.0)
}

fn read_zone_temp(zone: &Path) -> f64 {
    read_trimmed(zone.join("temp"))
        .and_then(|raw| raw.parse::<f64>().ok())
        .map(|raw| raw / 1000.0)
        .unwrap_or(0.0)
}

fn read_trimmed(path: impl AsRef<Path>) -> Option<String> {
    read_to_string(path)
        .ok()
        .map(|value| value.trim().to_owned())
}

fn default_disk_device() -> String {
    ["/dev/nvme0n1", "/dev/nvme0", "/dev/sda", "/dev/vda"]
        .into_iter()
        .find(|path| Path::new(path).exists())
        .unwrap_or("/dev/nvme0n1")
        .to_owned()
}

fn format_gib(kib: f64) -> String {
    format!("{:.1}GB", kib / 1024.0 / 1024.0)
}

fn format_uptime(total: u64) -> String {
    let days = total / 86_400;
    let rem = total % 86_400;
    let hours = rem / 3_600;
    let minutes = (rem % 3_600) / 60;
    let mut parts = Vec::new();

    if days > 0 {
        parts.push(format!("{days} {}", if days == 1 { "day" } else { "days" }));
    }
    if hours > 0 {
        parts.push(format!(
            "{hours} {}",
            if hours == 1 { "hour" } else { "hours" }
        ));
    }
    if minutes > 0 || parts.is_empty() {
        parts.push(format!(
            "{minutes} {}",
            if minutes == 1 { "minute" } else { "minutes" }
        ));
    }

    parts.join(", ")
}

fn push_missing_tolerant_error(errors: &mut Vec<String>, prefix: &str, error: procfs::ProcError) {
    if !matches!(error, procfs::ProcError::NotFound(_)) {
        errors.push(format!("{prefix}: {error}"));
    }
}

fn run_smartctl_json(disk_device: &str) -> Option<Value> {
    let args = [
        "-j",
        "--attributes",
        "--health",
        "--tolerance=conservative",
        disk_device,
    ];
    let sudo_args: Vec<&str> = ["-n", "smartctl"].iter().copied().chain(args).collect();
    let output = run_successful_command("smartctl", &args)
        .or_else(|| run_successful_command("sudo", &sudo_args))?;
    serde_json::from_slice::<Value>(&output).ok()
}

fn run_successful_command(program: &str, args: &[&str]) -> Option<Vec<u8>> {
    match Command::new(program).args(args).output() {
        Ok(output) if output.status.success() && !output.stdout.is_empty() => Some(output.stdout),
        _ => None,
    }
}

fn json_number_string(value: Option<&Value>) -> String {
    match value {
        Some(Value::Number(number)) => number
            .as_i64()
            .map(|value| value.to_string())
            .unwrap_or_else(|| number.to_string()),
        Some(Value::String(value)) => value.trim().to_owned(),
        _ => String::new(),
    }
}

fn json_int_value(value: Option<&Value>) -> i32 {
    match value {
        Some(Value::Number(number)) => number.as_i64().unwrap_or(0) as i32,
        Some(Value::String(value)) => {
            let trimmed = value.trim();
            if let Some(hex) = trimmed
                .strip_prefix("0x")
                .or_else(|| trimmed.strip_prefix("0X"))
            {
                i32::from_str_radix(hex, 16).unwrap_or(0)
            } else {
                trimmed.parse().unwrap_or(0)
            }
        }
        _ => 0,
    }
}

fn smart_wear_label(smart: &Value) -> String {
    if let Some(value) = smart
        .get("nvme_smart_health_information_log")
        .and_then(|nvme| nvme.get("percentage_used"))
    {
        return format!("{}%", json_number_string(Some(value)));
    }

    let table = smart
        .get("ata_smart_attributes")
        .and_then(|attrs| attrs.get("table"))
        .and_then(Value::as_array);
    if let Some(table) = table {
        for attr in table {
            let name = attr.get("name").and_then(Value::as_str).unwrap_or_default();
            if !name.to_ascii_lowercase().contains("percentage_used")
                && !name.to_ascii_lowercase().contains("percent_lifetime")
            {
                continue;
            }

            let raw_value = json_number_string(attr.get("raw").and_then(|raw| raw.get("value")));
            if !raw_value.is_empty() {
                return format!("{raw_value}%");
            }
        }
    }

    "Unknown".to_owned()
}

fn smart_health_label(smart: &Value) -> String {
    let status = smart.get("smart_status");
    let passed_flag = status
        .and_then(|s| s.get("passed"))
        .and_then(Value::as_bool);
    let has_passed = passed_flag.is_some();
    let passed = passed_flag.unwrap_or(false);
    let critical_warning = json_int_value(
        smart
            .get("nvme_smart_health_information_log")
            .and_then(|nvme| nvme.get("critical_warning")),
    );

    if has_passed && passed && critical_warning == 0 {
        "Healthy".to_owned()
    } else if has_passed && !passed {
        "Failed".to_owned()
    } else if critical_warning != 0 {
        format!("Warning ({critical_warning})")
    } else {
        "Unknown".to_owned()
    }
}

fn btrfs_copies_for_flags(flags: u64) -> i32 {
    if flags & BTRFS_BLOCK_GROUP_RAID1C4 != 0 {
        4
    } else if flags & BTRFS_BLOCK_GROUP_RAID1C3 != 0 {
        3
    } else if flags & BTRFS_BLOCK_GROUP_RAID10 != 0
        || flags & BTRFS_BLOCK_GROUP_RAID1 != 0
        || flags & BTRFS_BLOCK_GROUP_DUP != 0
    {
        2
    } else if flags & BTRFS_BLOCK_GROUP_RAID56_MASK != 0 {
        0
    } else {
        1
    }
}

fn read_btrfs_usage_metrics() -> BtrfsUsageMetrics {
    let file = match File::open("/") {
        Ok(file) => file,
        Err(_) => return BtrfsUsageMetrics::default(),
    };
    let fd = file.as_raw_fd();

    let spaces = match load_btrfs_space_info(fd) {
        Some(spaces) => spaces,
        None => return BtrfsUsageMetrics::default(),
    };
    let total_size = load_btrfs_device_size(fd);
    if total_size == 0 {
        return BtrfsUsageMetrics::default();
    }

    calculate_btrfs_usage_metrics(&spaces, total_size)
}

fn load_btrfs_space_info(fd: i32) -> Option<Vec<BtrfsIoctlSpaceInfo>> {
    let mut header = BtrfsIoctlSpaceArgs::default();
    if ioctl_btrfs_space_info(fd, &mut header) < 0 || header.total_spaces == 0 {
        return None;
    }

    let total_spaces = usize::try_from(header.total_spaces).ok()?;
    let header_size = size_of::<BtrfsIoctlSpaceArgs>();
    let spaces_size = total_spaces.checked_mul(size_of::<BtrfsIoctlSpaceInfo>())?;
    let mut storage = vec![0_u8; header_size.checked_add(spaces_size)?];
    let args = storage.as_mut_ptr().cast::<BtrfsIoctlSpaceArgs>();
    unsafe {
        (*args).space_slots = header.total_spaces;
    }
    if ioctl_btrfs_space_info(fd, unsafe { &mut *args }) < 0 {
        return None;
    }

    let total_spaces = usize::try_from(unsafe { (*args).total_spaces }).ok()?;
    let spaces_ptr = unsafe { storage.as_ptr().add(header_size) }.cast::<BtrfsIoctlSpaceInfo>();
    Some(unsafe { std::slice::from_raw_parts(spaces_ptr, total_spaces) }.to_vec())
}

fn load_btrfs_device_size(fd: i32) -> u64 {
    let mut fs_info = BtrfsIoctlFsInfoArgs::default();
    if unsafe {
        libc::ioctl(
            fd,
            libc::_IOR::<BtrfsIoctlFsInfoArgs>(BTRFS_IOCTL_MAGIC, 31),
            &mut fs_info,
        )
    } < 0
    {
        return 0;
    }

    (1..=fs_info.max_id)
        .filter_map(|devid| {
            let mut device_info = BtrfsIoctlDevInfoArgs {
                devid,
                ..Default::default()
            };
            let result = unsafe {
                libc::ioctl(
                    fd,
                    libc::_IOWR::<BtrfsIoctlDevInfoArgs>(BTRFS_IOCTL_MAGIC, 30),
                    &mut device_info,
                )
            };
            (result == 0).then_some(device_info.total_bytes)
        })
        .sum()
}

fn ioctl_btrfs_space_info(fd: i32, args: &mut BtrfsIoctlSpaceArgs) -> i32 {
    unsafe {
        libc::ioctl(
            fd,
            libc::_IOWR::<BtrfsIoctlSpaceArgs>(BTRFS_IOCTL_MAGIC, 20),
            args,
        )
    }
}

fn calculate_btrfs_usage_metrics(
    spaces: &[BtrfsIoctlSpaceInfo],
    total_size: u64,
) -> BtrfsUsageMetrics {
    let mut raw_data_used = 0_u64;
    let mut raw_data_chunks = 0_u64;
    let mut logical_data_chunks = 0_u64;
    let mut raw_metadata_used = 0_u64;
    let mut raw_metadata_chunks = 0_u64;
    let mut raw_system_used = 0_u64;
    let mut raw_system_chunks = 0_u64;
    let mut global_reserve = 0_u64;
    let mut global_reserve_used = 0_u64;
    let mut max_data_ratio = 1.0_f64;
    let mut mixed = false;

    for space in spaces {
        let flags = space.flags;
        let copies = btrfs_copies_for_flags(flags);
        if copies == 0 {
            return BtrfsUsageMetrics::default();
        }
        let copies_u64 = copies as u64;
        max_data_ratio = max_data_ratio.max(copies as f64);

        if flags & BTRFS_SPACE_INFO_GLOBAL_RSV != 0 {
            global_reserve = space.total_bytes;
            global_reserve_used = space.used_bytes;
        }
        if flags & (BTRFS_BLOCK_GROUP_DATA | BTRFS_BLOCK_GROUP_METADATA)
            == (BTRFS_BLOCK_GROUP_DATA | BTRFS_BLOCK_GROUP_METADATA)
        {
            mixed = true;
        }
        if flags & BTRFS_BLOCK_GROUP_DATA != 0 {
            raw_data_used = raw_data_used.saturating_add(space.used_bytes * copies_u64);
            raw_data_chunks = raw_data_chunks.saturating_add(space.total_bytes * copies_u64);
            logical_data_chunks = logical_data_chunks.saturating_add(space.total_bytes);
        }
        if flags & BTRFS_BLOCK_GROUP_METADATA != 0 {
            raw_metadata_used = raw_metadata_used.saturating_add(space.used_bytes * copies_u64);
            raw_metadata_chunks =
                raw_metadata_chunks.saturating_add(space.total_bytes * copies_u64);
        }
        if flags & BTRFS_BLOCK_GROUP_SYSTEM != 0 {
            raw_system_used = raw_system_used.saturating_add(space.used_bytes * copies_u64);
            raw_system_chunks = raw_system_chunks.saturating_add(space.total_bytes * copies_u64);
        }
    }

    let raw_total_chunks = raw_data_chunks
        .saturating_add(raw_system_chunks)
        .saturating_add(if mixed { 0 } else { raw_metadata_chunks });
    let raw_total_used = raw_data_used
        .saturating_add(raw_system_used)
        .saturating_add(if mixed { 0 } else { raw_metadata_used });
    let raw_total_unused = total_size.saturating_sub(raw_total_chunks);
    if logical_data_chunks == 0 || raw_data_chunks == 0 {
        return BtrfsUsageMetrics::default();
    }

    let data_ratio = raw_data_chunks as f64 / logical_data_chunks as f64;
    let mut free_estimated = (raw_data_chunks - raw_data_used) as f64 / data_ratio;
    if mixed {
        free_estimated -= global_reserve.saturating_sub(global_reserve_used) as f64;
    }
    let mut free_min = free_estimated;
    if raw_total_unused >= BTRFS_MIN_UNALLOCATED_THRESH {
        free_estimated += raw_total_unused as f64 / data_ratio;
        free_min += raw_total_unused as f64 / max_data_ratio;
    }

    free_estimated = free_estimated.max(0.0);
    free_min = free_min.max(0.0);
    BtrfsUsageMetrics {
        available: true,
        free_est_gib: free_estimated / 1024.0 / 1024.0 / 1024.0,
        free_min_gib: free_min / 1024.0 / 1024.0 / 1024.0,
        used_pct: ((100.0 * raw_total_used as f64) / total_size as f64).clamp(0.0, 100.0) as i32,
        worst_pct: ((1.0 - (free_min / total_size as f64)) * 100.0).clamp(0.0, 100.0) as i32,
    }
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis().try_into().unwrap_or(i64::MAX))
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::{format_uptime, smart_health_label, smart_wear_label};
    use serde_json::json;

    #[test]
    fn formats_uptime_like_qt_provider() {
        assert_eq!(format_uptime(0), "0 minutes");
        assert_eq!(format_uptime(60), "1 minute");
        assert_eq!(format_uptime(3_660), "1 hour, 1 minute");
        assert_eq!(format_uptime(90_000), "1 day, 1 hour");
    }

    #[test]
    fn parses_smartctl_health_and_wear_labels() {
        let smart = json!({
            "smart_status": {"passed": true},
            "nvme_smart_health_information_log": {
                "critical_warning": 0,
                "percentage_used": 7
            }
        });

        assert_eq!(smart_health_label(&smart), "Healthy");
        assert_eq!(smart_wear_label(&smart), "7%");
    }
}
