use cxx_qt::CxxQtType;
use std::ffi::CString;
use std::fs;
use std::path::Path;
use std::pin::Pin;
use std::process::Command;
use std::time::{Duration, Instant};

use crate::qobjects;

impl Default for crate::SysInfoProviderRust {
    fn default() -> Self {
        let device = default_disk_device();
        Self {
            cpu: 0.0,
            mem: 0,
            mem_used: cxx_qt_lib::QString::from("0.0GB"),
            mem_total: cxx_qt_lib::QString::from("0.0GB"),
            disk: 0,
            disk_health: cxx_qt_lib::QString::from(""),
            disk_wear: cxx_qt_lib::QString::from(""),
            temp: 0.0,
            uptime: cxx_qt_lib::QString::from(""),
            psi_cpu_some: 0.0,
            psi_cpu_full: 0.0,
            psi_mem_some: 0.0,
            psi_mem_full: 0.0,
            psi_io_some: 0.0,
            psi_io_full: 0.0,
            disk_device: cxx_qt_lib::QString::from(device),
            error: cxx_qt_lib::QString::from(""),
            last_cpu_total: 0,
            last_cpu_idle: 0,
            last_disk_health_at: None,
            disk_health_cache: String::new(),
            disk_wear_cache: String::new(),
        }
    }
}

impl qobjects::SysInfoProvider {
    pub fn refresh(self: Pin<&mut Self>) -> bool {
        let mut this = self;
        let mut errors: Vec<String> = Vec::new();

        if let Err(err) = update_cpu_usage(this.as_mut()) {
            errors.push(err);
        }

        if let Err(err) = update_memory(this.as_mut()) {
            errors.push(err);
        }

        if let Err(err) = update_disk_usage(this.as_mut()) {
            errors.push(err);
        }

        if let Err(err) = update_temperature(this.as_mut()) {
            errors.push(err);
        }

        if let Err(err) = update_uptime(this.as_mut()) {
            errors.push(err);
        }

        if let Err(err) = update_psi(this.as_mut()) {
            errors.push(err);
        }

        if let Err(err) = update_disk_health(this.as_mut()) {
            errors.push(err);
        }

        if errors.is_empty() {
            this.as_mut().set_error(cxx_qt_lib::QString::from(""));
            true
        } else {
            this.as_mut()
                .set_error(cxx_qt_lib::QString::from(errors.join("; ")));
            false
        }
    }
}

fn default_disk_device() -> String {
    let candidates = ["/dev/nvme0", "/dev/nvme0n1", "/dev/sda", "/dev/vda"];
    for candidate in candidates {
        if Path::new(candidate).exists() {
            return candidate.to_string();
        }
    }
    "/dev/nvme0".to_string()
}

fn update_cpu_usage(mut obj: Pin<&mut qobjects::SysInfoProvider>) -> Result<(), String> {
    let (total, idle) = read_cpu_totals()?;
    let (prev_total, prev_idle) = {
        let rust = obj.as_mut().rust_mut();
        let rust = rust.get_mut();
        (rust.last_cpu_total, rust.last_cpu_idle)
    };

    if prev_total != 0 && total > prev_total {
        let dt = total - prev_total;
        let didle = idle.saturating_sub(prev_idle);
        let usage = if dt == 0 {
            0.0
        } else {
            100.0 * (1.0 - (didle as f64 / dt as f64))
        };
        obj.as_mut().set_cpu(usage);
    }

    let rust = obj.as_mut().rust_mut();
    let rust = rust.get_mut();
    rust.last_cpu_total = total;
    rust.last_cpu_idle = idle;
    Ok(())
}

fn read_cpu_totals() -> Result<(u64, u64), String> {
    let content = fs::read_to_string("/proc/stat").map_err(|err| err.to_string())?;
    let mut lines = content.lines();
    let line = lines.next().ok_or("Missing /proc/stat cpu line")?;
    let mut parts = line.split_whitespace();
    if parts.next() != Some("cpu") {
        return Err("Malformed /proc/stat cpu line".to_string());
    }

    let mut values: Vec<u64> = Vec::new();
    for part in parts {
        if let Ok(value) = part.parse::<u64>() {
            values.push(value);
        }
    }
    if values.len() < 4 {
        return Err("Not enough cpu counters".to_string());
    }

    let idle = values.get(3).copied().unwrap_or(0) + values.get(4).copied().unwrap_or(0);
    let total: u64 = values.iter().sum();
    Ok((total, idle))
}

fn update_memory(mut obj: Pin<&mut qobjects::SysInfoProvider>) -> Result<(), String> {
    let (total_kb, available_kb) = read_meminfo()?;
    if total_kb == 0 {
        return Err("MemTotal is zero".to_string());
    }

    let used_kb = total_kb.saturating_sub(available_kb);
    let mem_pct = ((used_kb as f64 / total_kb as f64) * 100.0).round() as i32;
    let used_gb = used_kb as f64 / 1024.0 / 1024.0;
    let total_gb = total_kb as f64 / 1024.0 / 1024.0;

    obj.as_mut().set_mem(mem_pct);
    obj.as_mut()
        .set_mem_used(cxx_qt_lib::QString::from(format!("{:.1}GB", used_gb)));
    obj.as_mut()
        .set_mem_total(cxx_qt_lib::QString::from(format!("{:.1}GB", total_gb)));
    Ok(())
}

fn read_meminfo() -> Result<(u64, u64), String> {
    let content = fs::read_to_string("/proc/meminfo").map_err(|err| err.to_string())?;
    let mut total_kb = 0;
    let mut available_kb = 0;
    for line in content.lines() {
        if line.starts_with("MemTotal:") {
            total_kb = line
                .split_whitespace()
                .nth(1)
                .and_then(|v| v.parse::<u64>().ok())
                .unwrap_or(0);
        } else if line.starts_with("MemAvailable:") {
            available_kb = line
                .split_whitespace()
                .nth(1)
                .and_then(|v| v.parse::<u64>().ok())
                .unwrap_or(0);
        }
    }
    Ok((total_kb, available_kb))
}

fn update_disk_usage(mut obj: Pin<&mut qobjects::SysInfoProvider>) -> Result<(), String> {
    let mut stat = std::mem::MaybeUninit::<libc::statvfs>::uninit();
    let path = CString::new("/").map_err(|err| err.to_string())?;
    let ret = unsafe { libc::statvfs(path.as_ptr(), stat.as_mut_ptr()) };
    if ret != 0 {
        return Err(format!(
            "statvfs failed: {}",
            std::io::Error::last_os_error()
        ));
    }
    let stat = unsafe { stat.assume_init() };
    let total = stat.f_blocks as f64 * stat.f_frsize as f64;
    let avail = stat.f_bavail as f64 * stat.f_frsize as f64;
    let used = (total - avail).max(0.0);
    let pct = if total > 0.0 {
        (used / total) * 100.0
    } else {
        0.0
    };
    obj.as_mut().set_disk(pct.round() as i32);
    Ok(())
}

fn update_temperature(mut obj: Pin<&mut qobjects::SysInfoProvider>) -> Result<(), String> {
    let thermal_path = Path::new("/sys/class/thermal");
    let mut temp_c = None;
    if let Ok(entries) = fs::read_dir(thermal_path) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            if !name.to_string_lossy().starts_with("thermal_zone") {
                continue;
            }
            let temp_path = entry.path().join("temp");
            if let Ok(contents) = fs::read_to_string(&temp_path) {
                if let Ok(value) = contents.trim().parse::<f64>() {
                    temp_c = Some(value / 1000.0);
                    break;
                }
            }
        }
    }

    obj.as_mut().set_temp(temp_c.unwrap_or(0.0));
    Ok(())
}

fn update_uptime(mut obj: Pin<&mut qobjects::SysInfoProvider>) -> Result<(), String> {
    let content = fs::read_to_string("/proc/uptime").map_err(|err| err.to_string())?;
    let secs = content
        .split_whitespace()
        .next()
        .and_then(|v| v.parse::<f64>().ok())
        .unwrap_or(0.0);
    let uptime = format_uptime(secs as u64);
    obj.as_mut().set_uptime(cxx_qt_lib::QString::from(uptime));
    Ok(())
}

fn format_uptime(total_seconds: u64) -> String {
    let mut remaining = total_seconds;
    let days = remaining / 86400;
    remaining %= 86400;
    let hours = remaining / 3600;
    remaining %= 3600;
    let minutes = remaining / 60;

    let mut parts = Vec::new();
    if days > 0 {
        parts.push(format!(
            "{} {}",
            days,
            if days == 1 { "day" } else { "days" }
        ));
    }
    if hours > 0 {
        parts.push(format!(
            "{} {}",
            hours,
            if hours == 1 { "hour" } else { "hours" }
        ));
    }
    if minutes > 0 || parts.is_empty() {
        parts.push(format!(
            "{} {}",
            minutes,
            if minutes == 1 { "minute" } else { "minutes" }
        ));
    }
    parts.join(", ")
}

fn update_psi(mut obj: Pin<&mut qobjects::SysInfoProvider>) -> Result<(), String> {
    let (cpu_some, cpu_full) = read_psi("/proc/pressure/cpu");
    let (mem_some, mem_full) = read_psi("/proc/pressure/memory");
    let (io_some, io_full) = read_psi("/proc/pressure/io");

    obj.as_mut().set_psi_cpu_some(cpu_some);
    obj.as_mut().set_psi_cpu_full(cpu_full);
    obj.as_mut().set_psi_mem_some(mem_some);
    obj.as_mut().set_psi_mem_full(mem_full);
    obj.as_mut().set_psi_io_some(io_some);
    obj.as_mut().set_psi_io_full(io_full);
    Ok(())
}

fn read_psi(path: &str) -> (f64, f64) {
    let Ok(contents) = fs::read_to_string(path) else {
        return (0.0, 0.0);
    };
    let mut some = 0.0;
    let mut full = 0.0;
    for line in contents.lines() {
        if line.starts_with("some") {
            some = parse_psi_avg10(line);
        } else if line.starts_with("full") {
            full = parse_psi_avg10(line);
        }
    }
    (some, full)
}

fn parse_psi_avg10(line: &str) -> f64 {
    for part in line.split_whitespace() {
        if let Some(value) = part.strip_prefix("avg10=") {
            return value.parse::<f64>().unwrap_or(0.0);
        }
    }
    0.0
}

fn update_disk_health(mut obj: Pin<&mut qobjects::SysInfoProvider>) -> Result<(), String> {
    let device = obj.as_ref().disk_device().to_string();
    let device = if device.trim().is_empty() {
        default_disk_device()
    } else {
        device
    };

    let now = Instant::now();
    let cache_ttl = Duration::from_secs(6 * 60 * 60);

    let (needs_refresh, cached_health, cached_wear) = {
        let rust = obj.as_mut().rust_mut();
        let rust = rust.get_mut();
        let needs_refresh = rust
            .last_disk_health_at
            .map(|ts| now.duration_since(ts) > cache_ttl)
            .unwrap_or(true)
            || rust.disk_health_cache.is_empty();
        (
            needs_refresh,
            rust.disk_health_cache.clone(),
            rust.disk_wear_cache.clone(),
        )
    };

    if needs_refresh {
        let (health, wear) = read_disk_health(&device);
        let rust = obj.as_mut().rust_mut();
        let rust = rust.get_mut();
        rust.disk_health_cache = health.clone();
        rust.disk_wear_cache = wear.clone();
        rust.last_disk_health_at = Some(now);
        obj.as_mut()
            .set_disk_health(cxx_qt_lib::QString::from(health));
        obj.as_mut().set_disk_wear(cxx_qt_lib::QString::from(wear));
    } else {
        obj.as_mut()
            .set_disk_health(cxx_qt_lib::QString::from(cached_health));
        obj.as_mut()
            .set_disk_wear(cxx_qt_lib::QString::from(cached_wear));
    }
    Ok(())
}

fn read_disk_health(device: &str) -> (String, String) {
    let attrs = run_smartctl(&["--attributes", device]);
    let health = run_smartctl(&["--health", "--tolerance=conservative", device]);

    if attrs.is_none() && health.is_none() {
        return (
            "Unknown (smartctl missing)".to_string(),
            "Unknown".to_string(),
        );
    }

    let attrs_output = attrs.unwrap_or_default();
    let critical_warning = parse_smartctl_value(&attrs_output, "Critical Warning:")
        .unwrap_or_else(|| "unknown".to_string());
    let wear = parse_smartctl_value(&attrs_output, "Percentage Used:")
        .unwrap_or_else(|| "Unknown".to_string());

    let mut health_result = "unknown".to_string();
    if let Some(health_output) = health {
        if let Some(value) = parse_smartctl_value(&health_output, "result") {
            health_result = value;
        } else if let Some(value) = parse_smartctl_value(&health_output, "SMART Health Status:") {
            health_result = value;
        }
    }

    let health = if critical_warning == "0x00" && health_result == "PASSED" {
        "Healthy".to_string()
    } else if health_result != "unknown" {
        format!("{} ({})", health_result, critical_warning)
    } else {
        format!("Unknown ({})", critical_warning)
    };

    (health, wear)
}

fn run_smartctl(args: &[&str]) -> Option<String> {
    let output = Command::new("smartctl").args(args).output().ok();
    if let Some(out) = output {
        if out.status.success() {
            return Some(String::from_utf8_lossy(&out.stdout).to_string());
        }
    }

    let output = Command::new("sudo")
        .arg("-n")
        .arg("smartctl")
        .args(args)
        .output()
        .ok();

    if let Some(out) = output {
        if out.status.success() {
            return Some(String::from_utf8_lossy(&out.stdout).to_string());
        }
    }
    None
}

fn parse_smartctl_value(output: &str, needle: &str) -> Option<String> {
    for line in output.lines() {
        if line.contains(needle) {
            if let Some(value) = line.splitn(2, needle).nth(1) {
                return Some(value.trim().trim_matches(':').trim().to_string());
            }
        }
    }
    None
}
