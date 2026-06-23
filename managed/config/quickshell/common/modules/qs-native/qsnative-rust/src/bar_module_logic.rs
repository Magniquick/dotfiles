use std::collections::HashSet;
use std::ffi::{c_char, CStr, CString};

use crate::utils::first_non_empty;

use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};

#[derive(Debug, Clone, Default, Deserialize)]
struct BluetoothDeviceInput {
    #[serde(default)]
    index: usize,
    #[serde(default)]
    alias: String,
    #[serde(default)]
    name: String,
    #[serde(default)]
    address: String,
    #[serde(default, rename = "dbusPath")]
    dbus_path: String,
    #[serde(default)]
    icon: String,
    #[serde(default)]
    connected: bool,
    #[serde(default)]
    paired: bool,
    #[serde(default, rename = "batteryPercentage")]
    battery_percentage: Option<f64>,
    #[serde(default)]
    battery: Option<f64>,
}

#[derive(Debug, Clone, Serialize)]
struct BluetoothDeviceInfo {
    index: usize,
    key: String,
    label: String,
    icon: String,
    battery: i32,
    airpods: bool,
    connected: bool,
    paired: bool,
}

#[derive(Debug, Clone, Default, Serialize)]
struct LibrepodsBattery {
    left: i32,
    right: i32,
    #[serde(rename = "caseBattery")]
    case_battery: i32,
    average: i32,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct MprisPlayerInput {
    #[serde(default)]
    index: usize,
    #[serde(default, rename = "playbackState")]
    playback_state: i64,
    #[serde(default, rename = "stateRank")]
    state_rank: Option<i64>,
    #[serde(default, rename = "dbusName")]
    dbus_name: String,
    #[serde(default)]
    identity: String,
    #[serde(default, rename = "desktopEntry")]
    desktop_entry: String,
    #[serde(default, rename = "uniqueId")]
    unique_id: String,
    #[serde(default)]
    metadata: Map<String, Value>,
}

#[derive(Debug, Clone, Serialize)]
struct MprisSelection {
    index: i64,
}

#[derive(Debug, Clone, Serialize)]
struct LyricsSourceInfo {
    icon: &'static str,
    label: &'static str,
}

#[derive(Debug, Clone, Serialize)]
struct ChargeControlConfig {
    mode: String,
}

#[derive(Debug, Clone, Serialize)]
struct ChargeControlCommand {
    command: Vec<&'static str>,
}

fn json_c_string(value: Value) -> *mut c_char {
    CString::new(value.to_string())
        .unwrap_or_else(|_| CString::new("{}").expect("static JSON has no NUL"))
        .into_raw()
}

unsafe fn cstr_value(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    CStr::from_ptr(ptr).to_string_lossy().into_owned()
}

fn normalize_bluetooth_id(text: &str) -> String {
    text.trim()
        .chars()
        .filter(|c| c.is_ascii_hexdigit())
        .flat_map(char::to_uppercase)
        .collect()
}

fn is_raw_bluetooth_id(text: &str, address: &str) -> bool {
    let value = text.trim();
    if value.is_empty() {
        return true;
    }

    let normalized = normalize_bluetooth_id(value);
    let address_normalized = normalize_bluetooth_id(address);
    address_normalized.len() == 12 && normalized == address_normalized
}

fn is_readable_bluetooth_name(text: &str, address: &str) -> bool {
    let value = text.trim();
    !value.is_empty()
        && !is_raw_bluetooth_id(value, address)
        && !value.eq_ignore_ascii_case("unknown device")
}

fn bluetooth_device_label(device: &BluetoothDeviceInput) -> String {
    let alias = device.alias.trim();
    let name = device.name.trim();
    if is_readable_bluetooth_name(alias, &device.address) {
        return alias.to_owned();
    }
    if is_readable_bluetooth_name(name, &device.address) {
        return name.to_owned();
    }
    String::new()
}

fn bluetooth_device_icon(icon_name: &str) -> &'static str {
    let name = icon_name.to_lowercase();
    if name.contains("headset") {
        "󰋎"
    } else if name.contains("headphone") || name.contains("watch") {
        "󰋋"
    } else if name.contains("audio") || name.contains("speaker") {
        "󰓃"
    } else if name.contains("phone") {
        "󰄜"
    } else if name.contains("keyboard") {
        "󰌌"
    } else if name.contains("mouse") {
        "󰍽"
    } else if name.contains("gamepad") || name.contains("joystick") {
        "󰊗"
    } else if name.contains("tablet") {
        "󰓷"
    } else if name.contains("camera") {
        "󰄀"
    } else if name.contains("computer") || name.contains("laptop") {
        "󰌢"
    } else {
        "󰂯"
    }
}

fn bluetooth_battery_value(device: &BluetoothDeviceInput) -> i32 {
    let value = device.battery_percentage.or(device.battery);
    match value {
        Some(value) if value.is_finite() => value.round().clamp(0.0, 100.0) as i32,
        _ => -1,
    }
}

fn bluetooth_device_key(device: &BluetoothDeviceInput, label: &str) -> String {
    first_non_empty([device.dbus_path.trim(), device.address.trim(), label])
}

fn bluetooth_device_infos(input: &str) -> Vec<BluetoothDeviceInfo> {
    let mut infos: Vec<_> = serde_json::from_str::<Vec<BluetoothDeviceInput>>(input)
        .unwrap_or_default()
        .into_iter()
        .filter_map(|device| {
            let label = bluetooth_device_label(&device);
            if label.is_empty() {
                return None;
            }
            Some(BluetoothDeviceInfo {
                index: device.index,
                key: bluetooth_device_key(&device, &label),
                icon: bluetooth_device_icon(&device.icon).to_owned(),
                battery: bluetooth_battery_value(&device),
                airpods: label.to_lowercase().contains("airpods"),
                connected: device.connected,
                paired: device.paired,
                label,
            })
        })
        .collect();

    infos.sort_by(|a, b| {
        b.connected
            .cmp(&a.connected)
            .then_with(|| b.paired.cmp(&a.paired))
            .then_with(|| a.label.to_lowercase().cmp(&b.label.to_lowercase()))
            .then_with(|| a.index.cmp(&b.index))
    });
    infos
}

fn parse_librepods_tooltip(text: &str) -> LibrepodsBattery {
    let Some(start) = text.to_lowercase().find("l:") else {
        return LibrepodsBattery {
            left: -1,
            right: -1,
            case_battery: -1,
            average: -1,
        };
    };
    let compact = text[start..].replace('%', " ");
    let mut left = -1;
    let mut right = -1;
    let mut case_battery = -1;
    let parts: Vec<_> = compact.split_whitespace().collect();
    for window in parts.windows(2) {
        let key = window[0].trim_end_matches(':').to_ascii_lowercase();
        let parsed = window[1].parse::<i32>().unwrap_or(-1);
        let value = if (1..=100).contains(&parsed) {
            parsed
        } else {
            -1
        };
        match key.as_str() {
            "l" => left = value,
            "r" => right = value,
            "c" => case_battery = value,
            _ => {}
        }
    }
    let values: Vec<_> = [left, right, case_battery]
        .into_iter()
        .filter(|value| *value > 0)
        .collect();
    let average = if values.is_empty() {
        -1
    } else {
        ((values.iter().sum::<i32>() as f64) / (values.len() as f64)).round() as i32
    };
    LibrepodsBattery {
        left,
        right,
        case_battery,
        average,
    }
}

fn is_playerctld(player: &MprisPlayerInput) -> bool {
    player.dbus_name.to_lowercase().contains("playerctld")
        || player.identity.eq_ignore_ascii_case("playerctld")
        || player.desktop_entry.eq_ignore_ascii_case("playerctld")
}

fn active_mpris_player_index(input: &str) -> i64 {
    let players = serde_json::from_str::<Vec<MprisPlayerInput>>(input).unwrap_or_default();
    let candidates: Vec<_> = players
        .iter()
        .filter(|player| !is_playerctld(player))
        .collect();
    for rank in [0_i64, 1_i64, 2_i64] {
        if let Some(player) = candidates.iter().find(|player| {
            player.state_rank == Some(rank)
                || (player.state_rank.is_none() && rank == 0 && player.playback_state == 1)
                || (player.state_rank.is_none() && rank == 1 && player.playback_state == 2)
        }) {
            return player.index as i64;
        }
    }
    candidates.first().map_or(-1, |player| player.index as i64)
}

fn metadata_string(metadata: &Map<String, Value>, key: &str) -> String {
    match metadata.get(key) {
        Some(Value::String(value)) => value.trim().to_owned(),
        Some(Value::Array(values)) => values
            .first()
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .to_owned(),
        Some(Value::Number(value)) => value.to_string(),
        _ => String::new(),
    }
}

fn spotify_track_ref(input: &str) -> String {
    let player = serde_json::from_str::<MprisPlayerInput>(input).unwrap_or_default();
    let desktop_entry = player.desktop_entry.to_lowercase();
    let identity = player.identity.to_lowercase();
    if !desktop_entry.contains("spotify") && !identity.contains("spotify") {
        return String::new();
    }

    let xesam_url = metadata_string(&player.metadata, "xesam:url");
    if !xesam_url.is_empty() {
        return xesam_url;
    }

    let mpris_track_id = metadata_string(&player.metadata, "mpris:trackid");
    if !mpris_track_id.is_empty() {
        if let Some(last) = mpris_track_id.split('/').next_back() {
            if !last.is_empty() {
                return last.to_owned();
            }
        }
    }

    if player.unique_id.len() == 22 && player.unique_id.chars().all(|c| c.is_ascii_alphanumeric()) {
        return player.unique_id;
    }

    String::new()
}

fn lyrics_lookup_key(track: &str, artist: &str, album: &str, length_micros: &str) -> String {
    [
        track.trim(),
        artist.trim(),
        album.trim(),
        length_micros.trim(),
    ]
    .join("\u{241E}")
}

fn is_no_lyrics_error(error_text: &str) -> bool {
    let msg = error_text.trim().to_lowercase();
    !msg.is_empty()
        && (msg.contains("no lyrics")
            || msg.contains("lyrics not found")
            || msg.contains("spotify and lrclib failed"))
}

fn lyrics_source_info(source: &str) -> LyricsSourceInfo {
    let value = source.to_lowercase();
    if value.starts_with("spotify") {
        LyricsSourceInfo {
            icon: "",
            label: "Spotify",
        }
    } else if value.starts_with("netease") {
        LyricsSourceInfo {
            icon: "󰋋",
            label: "NetEase",
        }
    } else if value.starts_with("lrclib") {
        LyricsSourceInfo {
            icon: "",
            label: "LRCLIB",
        }
    } else {
        LyricsSourceInfo {
            icon: "",
            label: "",
        }
    }
}

fn parse_systemd_idle_inhibitors(output: &str) -> Vec<String> {
    let mut names = Vec::new();
    let mut seen = HashSet::new();

    for raw_line in output.lines() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with("WHO") || line.contains("inhibitors listed.") {
            continue;
        }

        let parts: Vec<_> = line.split_whitespace().collect();
        if parts.len() < 6 {
            continue;
        }
        let mode_index = parts
            .iter()
            .rposition(|part| *part == "block" || *part == "delay");
        let Some(mode_index) = mode_index else {
            continue;
        };
        if mode_index < 2 {
            continue;
        }
        let what = parts[mode_index - 2].to_ascii_lowercase();
        if !what.split(':').any(|part| part == "idle") {
            continue;
        }
        let who = parts[0].to_owned();
        if seen.insert(who.clone()) {
            names.push(who);
        }
    }

    names
}

fn parse_portal_session_count(output: &str) -> usize {
    output
        .lines()
        .map(str::trim)
        .filter(|line| {
            line.contains("/org/freedesktop/portal/desktop/session/")
                && *line != "/org/freedesktop/portal/desktop/session"
        })
        .count()
}

fn charge_control_config(output: &str) -> ChargeControlConfig {
    let mode = output
        .lines()
        .find_map(|line| line.strip_prefix("MODE="))
        .unwrap_or_default()
        .trim()
        .to_lowercase();
    ChargeControlConfig { mode }
}

fn charge_control_command(target_mode: &str) -> ChargeControlCommand {
    if target_mode == "auto" {
        ChargeControlCommand {
            command: vec![
                "sh",
                "-c",
                "/usr/local/bin/hp-charge-control config auto --now",
            ],
        }
    } else {
        ChargeControlCommand {
            command: vec![
                "sh",
                "-c",
                "/usr/local/bin/hp-charge-control config limit 50 30 --now",
            ],
        }
    }
}

/// # Safety
///
/// `devices_json` must be null or point to a valid NUL-terminated UTF-8 C string.
/// The returned pointer must be released with `QsNative_Free`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_BluetoothDevices(
    devices_json: *const c_char,
) -> *mut c_char {
    let input = cstr_value(devices_json);
    json_c_string(json!(bluetooth_device_infos(&input)))
}

/// # Safety
///
/// `text` must be null or point to a valid NUL-terminated UTF-8 C string.
/// The returned pointer must be released with `QsNative_Free`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_ParseLibrepodsTooltip(
    text: *const c_char,
) -> *mut c_char {
    let input = cstr_value(text);
    json_c_string(json!(parse_librepods_tooltip(&input)))
}

/// # Safety
///
/// `players_json` must be null or point to a valid NUL-terminated UTF-8 C string.
/// The returned pointer must be released with `QsNative_Free`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_ActiveMprisPlayer(
    players_json: *const c_char,
) -> *mut c_char {
    let input = cstr_value(players_json);
    json_c_string(json!(MprisSelection {
        index: active_mpris_player_index(&input),
    }))
}

/// # Safety
///
/// `player_json` must be null or point to a valid NUL-terminated UTF-8 C string.
/// The returned pointer must be released with `QsNative_Free`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_SpotifyTrackRef(
    player_json: *const c_char,
) -> *mut c_char {
    let input = cstr_value(player_json);
    json_c_string(json!({ "ref": spotify_track_ref(&input) }))
}

/// # Safety
///
/// Arguments must be null or point to valid NUL-terminated UTF-8 C strings.
/// The returned pointer must be released with `QsNative_Free`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_LyricsLookupKey(
    track: *const c_char,
    artist: *const c_char,
    album: *const c_char,
    length_micros: *const c_char,
) -> *mut c_char {
    json_c_string(json!({
        "key": lyrics_lookup_key(
            &cstr_value(track),
            &cstr_value(artist),
            &cstr_value(album),
            &cstr_value(length_micros),
        )
    }))
}

/// # Safety
///
/// `error_text` must be null or point to a valid NUL-terminated UTF-8 C string.
/// The returned pointer must be released with `QsNative_Free`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_IsNoLyricsError(
    error_text: *const c_char,
) -> *mut c_char {
    json_c_string(json!({ "value": is_no_lyrics_error(&cstr_value(error_text)) }))
}

/// # Safety
///
/// `source` must be null or point to a valid NUL-terminated UTF-8 C string.
/// The returned pointer must be released with `QsNative_Free`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_LyricsSourceInfo(
    source: *const c_char,
) -> *mut c_char {
    json_c_string(json!(lyrics_source_info(&cstr_value(source))))
}

/// # Safety
///
/// `output` must be null or point to a valid NUL-terminated UTF-8 C string.
/// The returned pointer must be released with `QsNative_Free`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_ParseSystemdIdleInhibitors(
    output: *const c_char,
) -> *mut c_char {
    json_c_string(json!(parse_systemd_idle_inhibitors(&cstr_value(output))))
}

/// # Safety
///
/// `output` must be null or point to a valid NUL-terminated UTF-8 C string.
/// The returned pointer must be released with `QsNative_Free`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_ParsePortalSessionCount(
    output: *const c_char,
) -> *mut c_char {
    json_c_string(json!({ "count": parse_portal_session_count(&cstr_value(output)) }))
}

/// # Safety
///
/// `output` must be null or point to a valid NUL-terminated UTF-8 C string.
/// The returned pointer must be released with `QsNative_Free`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_ParseChargeControlConfig(
    output: *const c_char,
) -> *mut c_char {
    json_c_string(json!(charge_control_config(&cstr_value(output))))
}

/// # Safety
///
/// `mode` must be null or point to a valid NUL-terminated UTF-8 C string.
/// The returned pointer must be released with `QsNative_Free`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_ChargeControlCommand(
    mode: *const c_char,
) -> *mut c_char {
    json_c_string(json!(charge_control_command(&cstr_value(mode))))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_librepods_battery() {
        let parsed = parse_librepods_tooltip("AirPods L: 80% R: 70% C: -1");
        assert_eq!(parsed.left, 80);
        assert_eq!(parsed.right, 70);
        assert_eq!(parsed.case_battery, -1);
        assert_eq!(parsed.average, 75);
    }

    #[test]
    fn sorts_bluetooth_devices_by_state_then_label() {
        let devices = r#"[
            {"index":0,"alias":"Mouse","connected":false,"paired":true},
            {"index":1,"alias":"Headset","connected":true,"paired":true},
            {"index":2,"alias":"Keyboard","connected":false,"paired":true}
        ]"#;
        let sorted = bluetooth_device_infos(devices);
        let indexes: Vec<_> = sorted.into_iter().map(|device| device.index).collect();
        assert_eq!(indexes, vec![1, 2, 0]);
    }

    #[test]
    fn detects_no_lyrics_errors() {
        assert!(is_no_lyrics_error("spotify and lrclib failed"));
        assert!(!is_no_lyrics_error("network failed"));
    }

    #[test]
    fn parses_idle_inhibitors() {
        let output = "WHO            UID USER PID COMM WHAT  WHY MODE\n\
                      firefox        1000 me   1 app  idle  video block\n\
                      powerdevil     1000 me   2 app  sleep lid delay\n";
        assert_eq!(parse_systemd_idle_inhibitors(output), vec!["firefox"]);
    }

    #[test]
    fn parses_charge_mode() {
        assert_eq!(charge_control_config("MODE=limit\n").mode, "limit");
        assert_eq!(
            charge_control_command("auto").command[2],
            "/usr/local/bin/hp-charge-control config auto --now"
        );
    }
}
