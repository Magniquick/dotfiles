use alpm;
use chrono::Local;
use cxx_qt::Threading;
use serde::Deserialize;
use std::cmp::Ordering;
use std::pin::Pin;
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering as AtomicOrdering};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use crate::qobjects;

#[derive(Deserialize)]
struct AurResponse {
    results: Vec<AurPackage>,
}

#[derive(Deserialize)]
struct AurPackage {
    #[serde(rename = "Name")]
    name: String,
    #[serde(rename = "Version")]
    version: String,
}

struct AurCache {
    last_update: Option<std::time::SystemTime>,
    update_count: u16,
    output: String,
}

impl Default for AurCache {
    fn default() -> Self {
        Self {
            last_update: None,
            update_count: 0,
            output: String::new(),
        }
    }
}

fn aur_cache() -> &'static Mutex<AurCache> {
    static CACHE: OnceLock<Mutex<AurCache>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(AurCache::default()))
}

fn is_version_newer(aur_version: &str, local_version: &str) -> bool {
    matches!(alpm::vercmp(aur_version, local_version), Ordering::Greater)
}

fn now_label() -> String {
    Local::now().format("%I:%M %p").to_string().to_lowercase()
}

fn sync_database() -> Result<(), String> {
    let output = Command::new("checkupdates")
        .args(["--nocolor"])
        .output()
        .map_err(|err| format!("checkupdates sync failed: {err}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if stderr.is_empty() {
            return Err("checkupdates sync failed".to_string());
        }
        return Err(format!("checkupdates sync failed: {stderr}"));
    }
    Ok(())
}

fn query_aur_api(package_names: &[&str]) -> Result<Vec<AurPackage>, String> {
    if package_names.is_empty() {
        return Ok(Vec::new());
    }
    let mut url = "https://aur.archlinux.org/rpc/?v=5&type=info".to_string();
    for name in package_names {
        url.push_str("&arg[]=");
        url.push_str(name);
    }
    let client = reqwest::blocking::Client::builder()
        .connect_timeout(Duration::from_secs(4))
        .timeout(Duration::from_secs(8))
        .build()
        .map_err(|err| format!("AUR client init failed: {err}"))?;
    let response = client
        .get(url)
        .send()
        .and_then(|r| r.error_for_status())
        .map_err(|err| format!("AUR request failed: {err}"))?;
    let parsed: AurResponse = response
        .json()
        .map_err(|err| format!("AUR parse failed: {err}"))?;
    Ok(parsed.results)
}

fn sync_aur_database(network_interval_seconds: u32) -> Result<(), String> {
    let mut cache = aur_cache()
        .lock()
        .map_err(|_| "AUR cache lock failed".to_string())?;
    let now = std::time::SystemTime::now();

    if let Some(last_update) = cache.last_update {
        if let Ok(elapsed) = now.duration_since(last_update) {
            if elapsed.as_secs() < network_interval_seconds as u64 {
                return Ok(());
            }
        }
    }

    let output = Command::new("pacman")
        .args(["-Qm"])
        .output()
        .map_err(|err| format!("pacman -Qm failed: {err}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if stderr.is_empty() {
            return Err("pacman -Qm failed".to_string());
        }
        return Err(format!("pacman -Qm failed: {stderr}"));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let local_packages: Vec<(String, String)> = stdout
        .lines()
        .filter_map(|line| {
            let mut parts = line.split_whitespace();
            let name = parts.next()?.to_string();
            let version = parts.next()?.to_string();
            Some((name, version))
        })
        .collect();

    if local_packages.is_empty() {
        cache.last_update = Some(now);
        cache.update_count = 0;
        cache.output.clear();
        return Ok(());
    }

    let package_names: Vec<&str> = local_packages
        .iter()
        .map(|(name, _)| name.as_str())
        .collect();
    match query_aur_api(&package_names) {
        Ok(aur_packages) => {
            let mut updates = Vec::new();
            for (local_name, local_version) in &local_packages {
                if let Some(aur_pkg) = aur_packages.iter().find(|pkg| pkg.name == *local_name) {
                    if is_version_newer(&aur_pkg.version, local_version) {
                        updates.push(format!(
                            "{} {} -> {}",
                            local_name, local_version, aur_pkg.version
                        ));
                    }
                }
            }
            cache.last_update = Some(now);
            cache.update_count = updates.len() as u16;
            cache.output = updates.join("\n");
        }
        Err(err) => {
            cache.last_update = Some(now);
            return Err(err);
        }
    }

    Ok(())
}

fn get_aur_updates() -> Result<(u16, String), String> {
    let cache = aur_cache()
        .lock()
        .map_err(|_| "AUR cache lock failed".to_string())?;
    Ok((cache.update_count, cache.output.clone()))
}

fn get_updates() -> Result<(u16, String), String> {
    let output = Command::new("checkupdates")
        .args(["--nosync", "--nocolor"])
        .output()
        .map_err(|err| format!("checkupdates failed: {err}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if stderr.is_empty() {
            return Err("checkupdates failed".to_string());
        }
        return Err(format!("checkupdates failed: {stderr}"));
    }
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    if stdout.trim().is_empty() {
        return Ok((0, String::new()));
    }
    let count = stdout.split(" -> ").count().saturating_sub(1) as u16;
    Ok((count, stdout.trim_end().to_string()))
}

fn pacman_refresh_inflight() -> &'static AtomicBool {
    static INFLIGHT: OnceLock<AtomicBool> = OnceLock::new();
    INFLIGHT.get_or_init(|| AtomicBool::new(false))
}

impl qobjects::PacmanUpdatesProvider {
    pub fn refresh(self: Pin<&mut Self>, no_aur: bool) -> bool {
        if pacman_refresh_inflight()
            .compare_exchange(false, true, AtomicOrdering::SeqCst, AtomicOrdering::SeqCst)
            .is_err()
        {
            // Coalesce bursty refresh() calls (timers, UI open/close, etc).
            return true;
        }

        let qt_thread = self.qt_thread();
        std::thread::spawn(move || {
            struct ResetInFlight;
            impl Drop for ResetInFlight {
                fn drop(&mut self) {
                    pacman_refresh_inflight().store(false, AtomicOrdering::SeqCst);
                }
            }
            let _guard = ResetInFlight;

            let mut errors: Vec<String> = Vec::new();
            let mut aur_count: u16 = 0;
            let mut aur_text = String::new();
            let now = now_label();

            let (updates_count, updates_text) = match get_updates() {
                Ok(value) => value,
                Err(err) => {
                    errors.push(err);
                    (0, String::new())
                }
            };

            if !no_aur {
                if let Err(err) = sync_aur_database(300) {
                    errors.push(err);
                }
                if let Ok((count, text)) = get_aur_updates() {
                    aur_count = count;
                    aur_text = text;
                }
            }

            let total = updates_count as i32 + aur_count as i32;
            let has_updates = total > 0;
            let error = errors.join(" | ");

            qt_thread
                .queue(move |mut obj| {
                    obj.as_mut().set_updates_count(updates_count as i32);
                    obj.as_mut().set_aur_updates_count(aur_count as i32);
                    obj.as_mut()
                        .set_updates_text(cxx_qt_lib::QString::from(updates_text));
                    obj.as_mut()
                        .set_aur_updates_text(cxx_qt_lib::QString::from(aur_text));
                    obj.as_mut()
                        .set_last_checked(cxx_qt_lib::QString::from(now));
                    obj.as_mut().set_error(cxx_qt_lib::QString::from(error));
                    obj.as_mut().set_has_updates(has_updates);
                })
                .ok();
        });
        true
    }

    pub fn sync(self: Pin<&mut Self>) -> bool {
        std::thread::spawn(move || {
            let _ = sync_database();
            let _ = sync_aur_database(300);
        });
        true
    }
}
