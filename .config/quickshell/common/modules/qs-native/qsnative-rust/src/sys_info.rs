use std::ffi::CString;
use std::fs::{read_dir, read_to_string, File};
use std::mem::size_of;
use std::os::fd::AsRawFd;
use std::os::raw::{c_char, c_void};
use std::path::Path;
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

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

impl SysInfoState {
    fn initial() -> Self {
        SysInfoState {
            disk_device: default_disk_device(),
            previous_cpu: 0.0,
            last_cpu_total: 0.0,
            last_cpu_idle: 0.0,
            last_disk_health_ms: 0,
            disk_health_cache: String::new(),
            disk_wear_cache: String::new(),
            last_btrfs_ms: 0,
            btrfs_available_cache: false,
            btrfs_disk_cache: 0,
            btrfs_free_est_cache: 0.0,
            btrfs_free_min_cache: 0.0,
            btrfs_worst_case_cache: 0,
        }
    }

    /// Folds the freshly-read caches back into the persistent state so the next
    /// refresh sees the previous CPU sample and the throttled disk/btrfs caches.
    fn absorb(&mut self, snapshot: &SysInfoSnapshot) {
        self.disk_device.clone_from(&snapshot.disk_device);
        self.previous_cpu = snapshot.cpu;
        self.last_cpu_total = snapshot.cpu_total;
        self.last_cpu_idle = snapshot.cpu_idle;
        self.last_disk_health_ms = snapshot.last_disk_health_ms;
        self.disk_health_cache.clone_from(&snapshot.disk_health_cache);
        self.disk_wear_cache.clone_from(&snapshot.disk_wear_cache);
        self.last_btrfs_ms = snapshot.last_btrfs_ms;
        self.btrfs_available_cache = snapshot.btrfs_available_cache;
        self.btrfs_disk_cache = snapshot.btrfs_disk_cache;
        self.btrfs_free_est_cache = snapshot.btrfs_free_est_cache;
        self.btrfs_free_min_cache = snapshot.btrfs_free_min_cache;
        self.btrfs_worst_case_cache = snapshot.btrfs_worst_case_cache;
    }
}

/// Zero-copy snapshot handed to the C++ side. The `*const c_char` fields borrow
/// `CString`s that live on the worker stack **only for the duration of the
/// callback**; C++ must copy them (`QString::fromUtf8`) synchronously and must
/// not retain the pointers. Fields map 1:1 to `SysInfoProvider` QML properties.
#[repr(C)]
pub struct SysInfoSnapshotC {
    pub cpu: f64,
    pub mem: i32,
    pub mem_used: *const c_char,
    pub mem_total: *const c_char,
    pub disk: i32,
    pub disk_worst_case: i32,
    pub disk_btrfs_available: bool,
    pub disk_btrfs_free_est_gib: f64,
    pub disk_btrfs_free_min_gib: f64,
    pub disk_health: *const c_char,
    pub disk_wear: *const c_char,
    pub disk_device: *const c_char,
    pub temp: f64,
    pub uptime: *const c_char,
    pub psi_cpu_some: f64,
    pub psi_cpu_full: f64,
    pub psi_mem_some: f64,
    pub psi_mem_full: f64,
    pub psi_io_some: f64,
    pub psi_io_full: f64,
    pub error: *const c_char,
}

/// Delivers a `SysInfoSnapshotC` (borrowed for the call only) to the C++ side.
pub type SysInfoSnapshotFn = unsafe extern "C" fn(*mut c_void, *const SysInfoSnapshotC);

/// Builds a `CString`, falling back to empty on an interior NUL.
fn cstr(value: &str) -> CString {
    CString::new(value).unwrap_or_default()
}

/// Opaque per-instance handle owned by the C++ `QsNativeSysInfo` `QObject`.
pub struct SysInfoHandle {
    state: Arc<Mutex<SysInfoState>>,
}

#[no_mangle]
pub extern "C" fn QsNative_SysInfo_New() -> *mut SysInfoHandle {
    Box::into_raw(Box::new(SysInfoHandle {
        state: Arc::new(Mutex::new(SysInfoState::initial())),
    }))
}

/// # Safety
/// `handle` must be null or a pointer from `QsNative_SysInfo_New` not yet freed.
#[no_mangle]
pub unsafe extern "C" fn QsNative_SysInfo_Delete(handle: *mut SysInfoHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Reads system metrics on a background thread and delivers a `SysInfoSnapshotC`
/// via `cb`. State (previous CPU sample, throttled disk/btrfs caches) lives in
/// the handle behind a mutex, so overlapping refreshes serialize safely.
///
/// # Safety
/// `handle` must be valid; `ctx`/`cb` must remain valid until `cb` fires.
///
/// # Panics
/// The worker thread panics if the shared state mutex has been poisoned by a
/// prior panic while holding the lock.
#[no_mangle]
pub unsafe extern "C" fn QsNative_SysInfo_Refresh(
    handle: *mut SysInfoHandle,
    ctx: *mut c_void,
    cb: SysInfoSnapshotFn,
) {
    if handle.is_null() {
        return;
    }
    let state = (*handle).state.clone();
    let ctx = ctx as usize;
    thread::spawn(move || {
        let input = state.lock().expect("sysinfo state poisoned").clone();
        let snapshot = read_snapshot(input);
        state
            .lock()
            .expect("sysinfo state poisoned")
            .absorb(&snapshot);

        // CStrings must outlive the callback; keep them bound in this scope.
        let mem_used = cstr(&snapshot.mem_used);
        let mem_total = cstr(&snapshot.mem_total);
        let disk_health = cstr(&snapshot.disk_health_cache);
        let disk_wear = cstr(&snapshot.disk_wear_cache);
        let disk_device = cstr(&snapshot.disk_device);
        let uptime = cstr(&snapshot.uptime);
        let error = cstr(&snapshot.error);
        let c = SysInfoSnapshotC {
            cpu: snapshot.cpu,
            mem: snapshot.mem,
            mem_used: mem_used.as_ptr(),
            mem_total: mem_total.as_ptr(),
            disk: snapshot.disk,
            disk_worst_case: snapshot.disk_worst_case,
            disk_btrfs_available: snapshot.disk_btrfs_available,
            disk_btrfs_free_est_gib: snapshot.disk_btrfs_free_est_gib,
            disk_btrfs_free_min_gib: snapshot.disk_btrfs_free_min_gib,
            disk_health: disk_health.as_ptr(),
            disk_wear: disk_wear.as_ptr(),
            disk_device: disk_device.as_ptr(),
            temp: snapshot.temp,
            uptime: uptime.as_ptr(),
            psi_cpu_some: snapshot.psi_cpu_some,
            psi_cpu_full: snapshot.psi_cpu_full,
            psi_mem_some: snapshot.psi_mem_some,
            psi_mem_full: snapshot.psi_mem_full,
            psi_io_some: snapshot.psi_io_some,
            psi_io_full: snapshot.psi_io_full,
            error: error.as_ptr(),
        };
        cb(ctx as *mut c_void, &raw const c);
    });
}

#[expect(
    clippy::cast_precision_loss,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    clippy::too_many_lines,
    reason = "percentage/size math over kernel counters deliberately narrows to display ints/floats; body is a linear metric gather"
)]
fn read_snapshot(mut state: SysInfoState) -> SysInfoSnapshot {
    let mut errors = Vec::new();
    let mut cpu_total = 0.0;
    let mut cpu_idle = 0.0;
    let mut cpu = state.previous_cpu;

    match KernelStats::current() {
        Ok(kernel_stats) => {
            cpu_total = cpu_total_ticks(&kernel_stats.total);
            cpu_idle = (kernel_stats.total.idle + kernel_stats.total.iowait.unwrap_or(0)) as f64;
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
        Ok(pressure) => (f64::from(pressure.some.avg10), f64::from(pressure.full.avg10)),
        Err(error) => {
            push_missing_tolerant_error(&mut errors, "psi cpu", &error);
            (0.0, 0.0)
        }
    };
    let (psi_mem_some, psi_mem_full) = match MemoryPressure::current() {
        Ok(pressure) => (f64::from(pressure.some.avg10), f64::from(pressure.full.avg10)),
        Err(error) => {
            push_missing_tolerant_error(&mut errors, "psi memory", &error);
            (0.0, 0.0)
        }
    };
    let (psi_io_some, psi_io_full) = match IoPressure::current() {
        Ok(pressure) => (f64::from(pressure.some.avg10), f64::from(pressure.full.avg10)),
        Err(error) => {
            push_missing_tolerant_error(&mut errors, "psi io", &error);
            (0.0, 0.0)
        }
    };

    let now = now_ms();
    if state.disk_health_cache.is_empty() || now - state.last_disk_health_ms > 6 * 60 * 60 * 1000 {
        if let Some(smart) = run_smartctl_json(&state.disk_device) {
            state.disk_health_cache = smart_health_label(&smart);
            state.disk_wear_cache = smart_wear_label(&smart);
        } else {
            "Unknown (smartctl missing)".clone_into(&mut state.disk_health_cache);
            "Unknown".clone_into(&mut state.disk_wear_cache);
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

#[expect(
    clippy::cast_precision_loss,
    reason = "summed jiffy counters are far below f64's exact-integer range in practice"
)]
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

#[expect(
    clippy::cast_precision_loss,
    clippy::cast_possible_truncation,
    reason = "byte counts widen to f64 for a percentage that intentionally narrows back to i32"
)]
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
        .map_or(0.0, |raw| raw / 1000.0)
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

fn push_missing_tolerant_error(errors: &mut Vec<String>, prefix: &str, error: &procfs::ProcError) {
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
            .map_or_else(|| number.to_string(), |value| value.to_string()),
        Some(Value::String(value)) => value.trim().to_owned(),
        _ => String::new(),
    }
}

fn json_int_value(value: Option<&Value>) -> i32 {
    match value {
        Some(Value::Number(number)) => {
            i32::try_from(number.as_i64().unwrap_or(0)).unwrap_or(i32::MAX)
        }
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
    } else {
        // RAID5/6 report 0 copies (unsupported here); everything else is single-copy.
        i32::from(flags & BTRFS_BLOCK_GROUP_RAID56_MASK == 0)
    }
}

fn read_btrfs_usage_metrics() -> BtrfsUsageMetrics {
    let Ok(file) = File::open("/") else {
        return BtrfsUsageMetrics::default();
    };
    let fd = file.as_raw_fd();

    let Some(spaces) = load_btrfs_space_info(fd) else {
        return BtrfsUsageMetrics::default();
    };
    let total_size = load_btrfs_device_size(fd);
    if total_size == 0 {
        return BtrfsUsageMetrics::default();
    }

    calculate_btrfs_usage_metrics(&spaces, total_size)
}

#[expect(
    clippy::cast_ptr_alignment,
    reason = "the u8 buffer is a heap Vec allocation (>=8-aligned) sized as a btrfs space-info ioctl arg"
)]
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

#[expect(
    clippy::cast_precision_loss,
    clippy::cast_possible_truncation,
    reason = "byte counts widen to f64 for ratio math and narrow back to display percentages"
)]
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
        let copies_u64 = u64::try_from(copies).unwrap_or(0);
        max_data_ratio = max_data_ratio.max(f64::from(copies));

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
        .map_or(0, |duration| duration.as_millis().try_into().unwrap_or(i64::MAX))
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
