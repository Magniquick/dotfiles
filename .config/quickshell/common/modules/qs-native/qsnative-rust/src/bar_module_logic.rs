use std::collections::HashSet;
use std::ffi::{c_char, CStr};

use crate::ffi::{from_cbor, into_cbor, QsNativeBytes};
use crate::utils::first_non_empty;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

/// Visits any CBOR numeric encoding and yields it as `f64`.
///
/// Numeric fields crossing the QML->Rust CBOR boundary (`qsn::toCbor` over a
/// `QVariantList`/`QVariantMap`) may arrive as either a CBOR integer or a CBOR
/// float: Qt's QML/JS engine represents most non-literal whole numbers
/// (anything reached through a variable, function parameter, or property
/// access, e.g. `.map((player, index) => ...)`) as a JS double rather than an
/// integer `QVariant`. The previous JSON `char*` path tolerated this
/// automatically (`serde_json` freely converts any JSON number into the
/// target Rust type); CBOR's integer and float major types are distinct, so
/// `usize`/`i64`/`f64` fields must opt into this lenient handling to match
/// the old behavior instead of hard-erroring (and dropping the whole
/// payload) whenever a value happens to cross as a float.
struct LenientNumberVisitor;

impl serde::de::Visitor<'_> for LenientNumberVisitor {
    type Value = f64;

    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("a number")
    }

    fn visit_f64<E: serde::de::Error>(self, value: f64) -> Result<f64, E> {
        Ok(value)
    }

    #[expect(
        clippy::cast_precision_loss,
        reason = "device/player indices and playback states are small enough that this cast is always exact"
    )]
    fn visit_i64<E: serde::de::Error>(self, value: i64) -> Result<f64, E> {
        Ok(value as f64)
    }

    #[expect(
        clippy::cast_precision_loss,
        reason = "device/player indices and playback states are small enough that this cast is always exact"
    )]
    fn visit_u64<E: serde::de::Error>(self, value: u64) -> Result<f64, E> {
        Ok(value as f64)
    }
}

fn deserialize_lenient_number<'de, D>(deserializer: D) -> Result<f64, D::Error>
where
    D: serde::Deserializer<'de>,
{
    deserializer.deserialize_any(LenientNumberVisitor)
}

/// Like [`deserialize_lenient_number`], but for an optional field (absent or
/// CBOR null both map to `None`).
fn deserialize_lenient_number_opt<'de, D>(deserializer: D) -> Result<Option<f64>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    struct OptVisitor;

    impl<'de> serde::de::Visitor<'de> for OptVisitor {
        type Value = Option<f64>;

        fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            formatter.write_str("an optional number")
        }

        fn visit_none<E: serde::de::Error>(self) -> Result<Self::Value, E> {
            Ok(None)
        }

        fn visit_unit<E: serde::de::Error>(self) -> Result<Self::Value, E> {
            Ok(None)
        }

        fn visit_some<D2: serde::Deserializer<'de>>(
            self,
            deserializer: D2,
        ) -> Result<Self::Value, D2::Error> {
            deserialize_lenient_number(deserializer).map(Some)
        }
    }

    deserializer.deserialize_option(OptVisitor)
}

/// Deserializes a required `usize` field that may cross as a CBOR integer or
/// float (see [`LenientNumberVisitor`]).
fn deserialize_lenient_usize<'de, D>(deserializer: D) -> Result<usize, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let value = deserialize_lenient_number(deserializer)?;
    #[expect(
        clippy::cast_sign_loss,
        clippy::cast_possible_truncation,
        reason = "value is clamped to 0.0.. before the cast, and indices never exceed usize range"
    )]
    Ok(value.max(0.0) as usize)
}

/// Deserializes a required `i64` field that may cross as a CBOR integer or
/// float (see [`LenientNumberVisitor`]).
fn deserialize_lenient_i64<'de, D>(deserializer: D) -> Result<i64, D::Error>
where
    D: serde::Deserializer<'de>,
{
    #[expect(
        clippy::cast_possible_truncation,
        reason = "playback state values are a small enum (0-2), so this cast is always exact"
    )]
    Ok(deserialize_lenient_number(deserializer)? as i64)
}

/// Deserializes an optional `i64` field that may be absent, null, or cross as
/// a CBOR integer or float (see [`LenientNumberVisitor`]).
fn deserialize_lenient_i64_opt<'de, D>(deserializer: D) -> Result<Option<i64>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    #[expect(
        clippy::cast_possible_truncation,
        reason = "playback state rank values are a small enum (0-2), so this cast is always exact"
    )]
    Ok(deserialize_lenient_number_opt(deserializer)?.map(|value| value as i64))
}

#[derive(Debug, Clone, Default, Deserialize)]
struct BluetoothDeviceInput {
    #[serde(default, deserialize_with = "deserialize_lenient_usize")]
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
    #[serde(
        default,
        rename = "batteryPercentage",
        deserialize_with = "deserialize_lenient_number_opt"
    )]
    battery_percentage: Option<f64>,
    #[serde(default, deserialize_with = "deserialize_lenient_number_opt")]
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
    #[serde(default, deserialize_with = "deserialize_lenient_usize")]
    index: usize,
    #[serde(
        default,
        rename = "playbackState",
        deserialize_with = "deserialize_lenient_i64"
    )]
    playback_state: i64,
    #[serde(
        default,
        rename = "stateRank",
        deserialize_with = "deserialize_lenient_i64_opt"
    )]
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
struct LyricsSourceInfo {
    icon: &'static str,
    label: &'static str,
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
        .filter(char::is_ascii_hexdigit)
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
        #[expect(
            clippy::cast_possible_truncation,
            reason = "value is clamped to 0.0..=100.0 before the cast, so it always fits in i32"
        )]
        Some(value) if value.is_finite() => value.round().clamp(0.0, 100.0) as i32,
        _ => -1,
    }
}

fn bluetooth_device_key(device: &BluetoothDeviceInput, label: &str) -> String {
    first_non_empty([device.dbus_path.trim(), device.address.trim(), label])
}

fn bluetooth_device_infos(devices: Vec<BluetoothDeviceInput>) -> Vec<BluetoothDeviceInfo> {
    let mut infos: Vec<_> = devices
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
        let sum: i32 = values.iter().sum();
        let count = i32::try_from(values.len()).unwrap_or(1).max(1);
        // Integer round-half-up: equivalent to `(sum as f64 / count as f64).round()`
        // because every value is a positive integer in 1..=100.
        (sum + count / 2) / count
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

fn active_mpris_player_index(players: &[MprisPlayerInput]) -> i64 {
    let candidates: Vec<_> = players.iter().filter(|player| !is_playerctld(player)).collect();
    for rank in [0_i64, 1_i64, 2_i64] {
        if let Some(player) = candidates.iter().find(|player| {
            player.state_rank == Some(rank)
                || (player.state_rank.is_none() && rank == 0 && player.playback_state == 1)
                || (player.state_rank.is_none() && rank == 1 && player.playback_state == 2)
        }) {
            return i64::try_from(player.index).unwrap_or(-1);
        }
    }
    candidates
        .first()
        .map_or(-1, |player| i64::try_from(player.index).unwrap_or(-1))
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

fn spotify_track_ref(player: &MprisPlayerInput) -> String {
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
        return player.unique_id.clone();
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
            icon: "",
            label: "Spotify",
        }
    } else if value.starts_with("netease") {
        LyricsSourceInfo {
            icon: "󰋋",
            label: "NetEase",
        }
    } else if value.starts_with("lrclib") {
        LyricsSourceInfo {
            icon: "",
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

/// # Safety
///
/// `(devices_ptr, devices_len)` must describe a readable CBOR byte range for the call, or
/// `devices_ptr` may be null. The returned buffer must be released with `QsNative_FreeBytes`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_BluetoothDevices(
    devices_ptr: *const u8,
    devices_len: usize,
) -> QsNativeBytes {
    let devices: Vec<BluetoothDeviceInput> =
        from_cbor(devices_ptr, devices_len).unwrap_or_default();
    into_cbor(&bluetooth_device_infos(devices))
}

/// # Safety
///
/// `text` must be null or point to a valid NUL-terminated UTF-8 C string.
/// The returned buffer must be released with `QsNative_FreeBytes`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_ParseLibrepodsTooltip(
    text: *const c_char,
) -> QsNativeBytes {
    let input = cstr_value(text);
    into_cbor(&parse_librepods_tooltip(&input))
}

/// # Safety
///
/// `(players_ptr, players_len)` must describe a readable CBOR byte range for the call, or
/// `players_ptr` may be null. The returned buffer must be released with `QsNative_FreeBytes`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_ActiveMprisPlayer(
    players_ptr: *const u8,
    players_len: usize,
) -> QsNativeBytes {
    let players: Vec<MprisPlayerInput> = from_cbor(players_ptr, players_len).unwrap_or_default();
    into_cbor(&active_mpris_player_index(&players))
}

/// # Safety
///
/// `(player_ptr, player_len)` must describe a readable CBOR byte range for the call, or
/// `player_ptr` may be null. The returned buffer must be released with `QsNative_FreeBytes`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_SpotifyTrackRef(
    player_ptr: *const u8,
    player_len: usize,
) -> QsNativeBytes {
    let player: MprisPlayerInput = from_cbor(player_ptr, player_len).unwrap_or_default();
    into_cbor(&spotify_track_ref(&player))
}

/// # Safety
///
/// Arguments must be null or point to valid NUL-terminated UTF-8 C strings.
/// The returned buffer must be released with `QsNative_FreeBytes`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_LyricsLookupKey(
    track: *const c_char,
    artist: *const c_char,
    album: *const c_char,
    length_micros: *const c_char,
) -> QsNativeBytes {
    into_cbor(&lyrics_lookup_key(
        &cstr_value(track),
        &cstr_value(artist),
        &cstr_value(album),
        &cstr_value(length_micros),
    ))
}

/// # Safety
///
/// `error_text` must be null or point to a valid NUL-terminated UTF-8 C string.
/// The returned buffer must be released with `QsNative_FreeBytes`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_IsNoLyricsError(
    error_text: *const c_char,
) -> QsNativeBytes {
    into_cbor(&is_no_lyrics_error(&cstr_value(error_text)))
}

/// # Safety
///
/// `source` must be null or point to a valid NUL-terminated UTF-8 C string.
/// The returned buffer must be released with `QsNative_FreeBytes`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_LyricsSourceInfo(
    source: *const c_char,
) -> QsNativeBytes {
    into_cbor(&lyrics_source_info(&cstr_value(source)))
}

/// # Safety
///
/// `output` must be null or point to a valid NUL-terminated UTF-8 C string.
/// The returned buffer must be released with `QsNative_FreeBytes`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_ParseSystemdIdleInhibitors(
    output: *const c_char,
) -> QsNativeBytes {
    into_cbor(&parse_systemd_idle_inhibitors(&cstr_value(output)))
}

/// # Safety
///
/// `output` must be null or point to a valid NUL-terminated UTF-8 C string.
/// The returned buffer must be released with `QsNative_FreeBytes`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_BarModuleLogic_ParsePortalSessionCount(
    output: *const c_char,
) -> QsNativeBytes {
    into_cbor(&parse_portal_session_count(&cstr_value(output)))
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
        let parsed: Vec<BluetoothDeviceInput> = serde_json::from_str(devices).unwrap();
        let sorted = bluetooth_device_infos(parsed);
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
    fn bluetooth_device_input_accepts_float_or_int_numbers() {
        // Simulates the real QML crossing: index/battery arrive as CBOR
        // doubles (computed JS numbers), batteryPercentage arrives as null.
        let val = ciborium::value::Value::Array(vec![ciborium::value::Value::Map(vec![
            (
                ciborium::value::Value::Text("index".into()),
                ciborium::value::Value::Float(0.0),
            ),
            (
                ciborium::value::Value::Text("alias".into()),
                ciborium::value::Value::Text("Headset".into()),
            ),
            (
                ciborium::value::Value::Text("battery".into()),
                ciborium::value::Value::Float(87.0),
            ),
            (
                ciborium::value::Value::Text("batteryPercentage".into()),
                ciborium::value::Value::Null,
            ),
        ])]);
        let mut buf = Vec::new();
        ciborium::ser::into_writer(&val, &mut buf).unwrap();
        let parsed: Vec<BluetoothDeviceInput> = ciborium::de::from_reader(&buf[..]).unwrap();
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].index, 0);
        assert_eq!(parsed[0].battery, Some(87.0));
        assert_eq!(parsed[0].battery_percentage, None);

        // Also still accepts plain CBOR integers (literal-encoded values).
        let val2 = ciborium::value::Value::Array(vec![ciborium::value::Value::Map(vec![
            (
                ciborium::value::Value::Text("index".into()),
                ciborium::value::Value::Integer(2.into()),
            ),
            (
                ciborium::value::Value::Text("battery".into()),
                ciborium::value::Value::Integer(55.into()),
            ),
        ])]);
        let mut buf2 = Vec::new();
        ciborium::ser::into_writer(&val2, &mut buf2).unwrap();
        let parsed2: Vec<BluetoothDeviceInput> = ciborium::de::from_reader(&buf2[..]).unwrap();
        assert_eq!(parsed2[0].index, 2);
        assert_eq!(parsed2[0].battery, Some(55.0));
    }

    #[test]
    fn mpris_player_input_accepts_float_or_int_numbers() {
        let val = ciborium::value::Value::Map(vec![
            (
                ciborium::value::Value::Text("index".into()),
                ciborium::value::Value::Float(1.0),
            ),
            (
                ciborium::value::Value::Text("playbackState".into()),
                ciborium::value::Value::Float(2.0),
            ),
            (
                ciborium::value::Value::Text("stateRank".into()),
                ciborium::value::Value::Null,
            ),
        ]);
        let mut buf = Vec::new();
        ciborium::ser::into_writer(&val, &mut buf).unwrap();
        let parsed: MprisPlayerInput = ciborium::de::from_reader(&buf[..]).unwrap();
        assert_eq!(parsed.index, 1);
        assert_eq!(parsed.playback_state, 2);
        assert_eq!(parsed.state_rank, None);
    }

    #[test]
    fn spotify_track_ref_via_cbor_metadata() {
        use ciborium::value::Value as CborValue;

        let metadata = CborValue::Map(vec![(
            CborValue::Text("xesam:url".into()),
            CborValue::Text("https://open.spotify.com/track/abc123".into()),
        )]);
        let player = CborValue::Map(vec![
            (
                CborValue::Text("desktopEntry".into()),
                CborValue::Text("spotify".into()),
            ),
            (CborValue::Text("metadata".into()), metadata),
        ]);
        let mut buf = Vec::new();
        ciborium::ser::into_writer(&player, &mut buf).unwrap();
        let parsed: MprisPlayerInput = ciborium::de::from_reader(&buf[..]).unwrap();
        assert_eq!(
            spotify_track_ref(&parsed),
            "https://open.spotify.com/track/abc123"
        );
    }

    #[test]
    fn spotify_track_ref_via_cbor_metadata_numeric_trackid_length() {
        // mpris:length is commonly an int64 in real players; make sure a
        // Number-typed metadata value round-trips fine even though it isn't
        // the field under test here.
        use ciborium::value::Value as CborValue;

        let metadata = CborValue::Map(vec![
            (
                CborValue::Text("mpris:trackid".into()),
                CborValue::Text("/org/mpris/MediaPlayer2/Track/1234567890123456789012".into()),
            ),
            (
                CborValue::Text("mpris:length".into()),
                CborValue::Integer(123_456_789.into()),
            ),
        ]);
        let player = CborValue::Map(vec![
            (
                CborValue::Text("identity".into()),
                CborValue::Text("Spotify".into()),
            ),
            (CborValue::Text("metadata".into()), metadata),
        ]);
        let mut buf = Vec::new();
        ciborium::ser::into_writer(&player, &mut buf).unwrap();
        let parsed: MprisPlayerInput = ciborium::de::from_reader(&buf[..]).unwrap();
        assert_eq!(spotify_track_ref(&parsed), "1234567890123456789012");
    }
}
