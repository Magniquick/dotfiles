//! Extern-C surface for the `UnifiedLyricsClient` QML type.
//!
//! Fetches synced lyrics from Spotify (needs an `SP_DC` cookie in the Secret
//! Service), `NetEase` Cloud Music (anonymous session + eapi crypto), and LRCLIB,
//! ranking by sync granularity (word > line > none) and caching the winning
//! result to disk. All network/D-Bus work happens on background threads.
//!
//! Wire format: scalar outcome fields (loaded/status/error/source/syncType/
//! provider) travel as borrowed `*const c_char` in `UnifiedLyricsResultC`,
//! following the `SysInfoSnapshotC` pattern (`CStrings` bound in the worker scope,
//! `cb` called once, strings dropped when the scope ends). `lines` is a
//! variable-depth structure (each line optionally carries a variable number of
//! word-level segments), which is not a homogeneous row array, so it is
//! delivered as a JSON `*const c_char` (`lines_json`) instead; the C++ side
//! parses it into the `lines` `QVariantList` property synchronously during the
//! callback.
//!
//! This crate has no dependency on `qsnative-rust`/`QsNativeGlue.h` (separate
//! `CMake` target, no shared link), so its C++ glue does its own JSON parsing and
//! queued-invoke marshaling rather than reusing `qsn::takeList`/`postToObject`.

use std::{
    collections::{BTreeMap, HashMap},
    env,
    ffi::{CStr, CString},
    fmt::Write as _,
    fs,
    os::raw::{c_char, c_void},
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, OnceLock,
    },
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use aes::Aes128;
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use cipher::{block_padding::Pkcs7, BlockModeDecrypt, BlockModeEncrypt, KeyInit as _};
use cookie::Cookie;
use hmac::{Hmac, Mac};
use md5::{Digest as _, Md5};
use rand::RngExt;
use regex::Regex;
use secret_service::{blocking::SecretService, EncryptionType};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha1::Sha1;
use sha2::Sha256;
use url::Url;

const SYNC_WORD: &str = "WORD_SYNCED";
const SYNC_LINE: &str = "LINE_SYNCED";
const SYNC_NONE: &str = "UNSYNCED";
const TUPLE_SEP: &str = "\u{241e}";
const SPOTIFY_TOKEN_URL: &str = "https://open.spotify.com/api/token";
const SPOTIFY_SERVER_TIME_URL: &str = "https://open.spotify.com/api/server-time";
const SPOTIFY_SECRET_DICT_URL: &str =
    "https://github.com/xyloflake/spot-secrets-go/blob/main/secrets/secretDict.json?raw=true";
const SPOTIFY_LYRICS_BASE_URL: &str = "https://spclient.wg.spotify.com/color-lyrics/v2/track/";
const SPOTIFY_TOKEN_USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) \
AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
const SPOTIFY_LYRICS_USER_AGENT: &str = "Mozilla/5.0 (X11; Linux x86_64) \
AppleWebKit/537.36 (KHTML, like Gecko) Chrome/101.0.0.0 Safari/537.36";

// ---------------------------------------------------------------------------
// extern "C" surface
// ---------------------------------------------------------------------------

/// Reads a borrowed C string into an owned `String` (empty on null). The
/// caller must ensure `ptr` is null or a valid NUL-terminated string for the
/// call duration; that precondition always holds for our `extern "C"` args.
fn c_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned()
}

/// Builds a `CString`, falling back to empty on an interior NUL.
fn cstr(value: &str) -> CString {
    CString::new(value).unwrap_or_default()
}

/// Opaque per-instance handle owned by the C++ `QsNativeUnifiedLyrics` `QObject`.
///
/// Coalesces overlapping `refresh()` calls: each call claims a new monotonic
/// request id and publishes it as `current_request`. The 30s watchdog thread
/// and the fetch thread spawned by the same call each try to atomically CAS
/// `current_request` from `request_id` to `request_id + 1` before delivering;
/// only one of the two can ever win, so a fetch that completes before the
/// watchdog fires can never be clobbered by a spurious timeout, and a
/// superseded/late-arriving outcome from an old refresh is silently dropped
/// instead of clobbering a newer one.
pub struct UnifiedLyricsHandle {
    request_id: AtomicU64,
    current_request: Arc<AtomicU64>,
}

#[no_mangle]
pub extern "C" fn QsNative_UnifiedLyrics_New() -> *mut UnifiedLyricsHandle {
    Box::into_raw(Box::new(UnifiedLyricsHandle {
        request_id: AtomicU64::new(0),
        current_request: Arc::new(AtomicU64::new(0)),
    }))
}

/// # Safety
/// `handle` must be null or a pointer from `QsNative_UnifiedLyrics_New` not yet freed.
#[no_mangle]
pub unsafe extern "C" fn QsNative_UnifiedLyrics_Delete(handle: *mut UnifiedLyricsHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Terminal outcome of a `refresh()` call (success, provider failure, or a 30s
/// timeout), borrowed for the duration of the callback only. `provider` feeds
/// the `metadata` map's sole `"provider"` key; `lines_json` is a JSON-encoded
/// `Vec<Line>` (see module docs for why lines travel as JSON).
#[repr(C)]
pub struct UnifiedLyricsResultC {
    pub loaded: bool,
    pub status: *const c_char,
    pub error: *const c_char,
    pub source: *const c_char,
    pub sync_type: *const c_char,
    pub provider: *const c_char,
    pub lines_json: *const c_char,
}

/// Delivers a `UnifiedLyricsResultC` (borrowed for the call only) to the C++ side.
pub type UnifiedLyricsResultFn = unsafe extern "C" fn(*mut c_void, *const UnifiedLyricsResultC);

/// Validates the request and, if valid, kicks off the background fetch (plus a
/// 30s watchdog) and returns `true` immediately; `cb` fires exactly once, later,
/// with the outcome. Returns `false` without touching any state or spawning
/// anything when `track_name`/`artist_name` is empty after trimming (mirrors
/// the original early-return validation).
///
/// # Safety
/// `handle` must be valid; the string args must be null or valid NUL-terminated
/// strings for the duration of the call; `ctx`/`cb` must remain valid until `cb`
/// fires (or forever, if it never does).
#[no_mangle]
pub unsafe extern "C" fn QsNative_UnifiedLyrics_Refresh(
    handle: *mut UnifiedLyricsHandle,
    ctx: *mut c_void,
    cb: UnifiedLyricsResultFn,
    spotify_track_ref: *const c_char,
    track_name: *const c_char,
    artist_name: *const c_char,
    album_name: *const c_char,
    length_micros: *const c_char,
) -> bool {
    if handle.is_null() {
        return false;
    }

    let spotify_track_ref = c_string(spotify_track_ref).trim().to_owned();
    let track_name = c_string(track_name).trim().to_owned();
    let artist_name = c_string(artist_name).trim().to_owned();
    let album_name = c_string(album_name).trim().to_owned();
    let length_micros = c_string(length_micros).trim().to_owned();

    if track_name.is_empty() || artist_name.is_empty() {
        return false;
    }

    println!(
        "UnifiedLyricsClient refresh track= {track_name} artist= {artist_name} album= {album_name} spotifyRef= {spotify_track_ref} lengthMicros= {length_micros}"
    );

    let request_id = (*handle).request_id.fetch_add(1, Ordering::SeqCst) + 1;
    (*handle).current_request.store(request_id, Ordering::SeqCst);
    let ctx = ctx as usize;

    // Both the watchdog and the fetch thread race to deliver a terminal
    // outcome for `request_id`. Only one may ever win: each side atomically
    // claims delivery by CASing `current_request` from `request_id` to
    // `request_id + 1` before calling `cb`. This reproduces the original
    // cxx-qt code's `current_request != request_id || !*client.busy()` guard
    // (there, a fetch that already completed left `busy() == false`, so a
    // later-firing watchdog closure was a no-op) without needing to read the
    // QObject's `busy` state from Rust: whichever side (timeout or
    // success/error) delivers first invalidates `request_id` for the other,
    // so a fetch that completes before 30s can never be clobbered by a
    // spurious timeout, and a superseded/late result from an old refresh()
    // is dropped instead of overwriting a newer one.
    let watchdog_current = Arc::clone(&(*handle).current_request);
    thread::spawn(move || {
        thread::sleep(Duration::from_secs(30));
        if watchdog_current
            .compare_exchange(
                request_id,
                request_id.wrapping_add(1),
                Ordering::SeqCst,
                Ordering::SeqCst,
            )
            .is_err()
        {
            return;
        }
        deliver_timeout(ctx, cb);
    });

    let fetch_current = Arc::clone(&(*handle).current_request);
    thread::spawn(move || {
        let req = Request {
            spdc: lookup_secret("SP_DC").unwrap_or_default(),
            spotify_track_ref,
            track_name,
            artist_name,
            album_name,
            length_micros,
        };
        let result = fetch(&req);
        if fetch_current
            .compare_exchange(
                request_id,
                request_id.wrapping_add(1),
                Ordering::SeqCst,
                Ordering::SeqCst,
            )
            .is_err()
        {
            return;
        }
        match result {
            Ok(result) => deliver_result(ctx, cb, &result),
            Err(error) => deliver_error(ctx, cb, error),
        }
    });

    true
}

fn deliver_timeout(ctx: usize, cb: UnifiedLyricsResultFn) {
    let status = cstr("Timed out");
    let error = cstr("Timeout while fetching lyrics");
    let empty = cstr("");
    let lines_json = cstr("[]");
    let c = UnifiedLyricsResultC {
        loaded: false,
        status: status.as_ptr(),
        error: error.as_ptr(),
        source: empty.as_ptr(),
        sync_type: empty.as_ptr(),
        provider: empty.as_ptr(),
        lines_json: lines_json.as_ptr(),
    };
    unsafe { cb(ctx as *mut c_void, &raw const c) };
}

fn deliver_error(ctx: usize, cb: UnifiedLyricsResultFn, error: String) {
    let message = if error.is_empty() {
        "Unknown error".to_owned()
    } else {
        error
    };
    eprintln!("UnifiedLyricsClient backend error message= {message}");

    let status = cstr("Error");
    let error = cstr(&message);
    let empty = cstr("");
    let lines_json = cstr("[]");
    let c = UnifiedLyricsResultC {
        loaded: false,
        status: status.as_ptr(),
        error: error.as_ptr(),
        source: empty.as_ptr(),
        sync_type: empty.as_ptr(),
        provider: empty.as_ptr(),
        lines_json: lines_json.as_ptr(),
    };
    unsafe { cb(ctx as *mut c_void, &raw const c) };
}

fn deliver_result(ctx: usize, cb: UnifiedLyricsResultFn, result: &ResultData) {
    let line_count = result.lines.len();
    println!(
        "UnifiedLyricsClient loaded source= {} provider= {} syncType= {} lines= {}",
        result.source, result.metadata.provider, result.sync_type, line_count
    );

    let lines_json = serde_json::to_string(&result.lines).unwrap_or_else(|_| "[]".to_owned());
    let status = cstr("OK");
    let error = cstr("");
    let source = cstr(&result.source);
    let sync_type = cstr(&result.sync_type);
    let provider = cstr(&result.metadata.provider);
    let lines_json = cstr(&lines_json);
    let c = UnifiedLyricsResultC {
        loaded: true,
        status: status.as_ptr(),
        error: error.as_ptr(),
        source: source.as_ptr(),
        sync_type: sync_type.as_ptr(),
        provider: provider.as_ptr(),
        lines_json: lines_json.as_ptr(),
    };
    unsafe { cb(ctx as *mut c_void, &raw const c) };
}

// ---------------------------------------------------------------------------
// Fetch pipeline (provider-agnostic)
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct Segment {
    start_time_ms: String,
    end_time_ms: String,
    text: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct Line {
    start_time_ms: String,
    end_time_ms: String,
    words: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    segments: Vec<Segment>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct ResultData {
    source: String,
    #[serde(rename = "syncType")]
    sync_type: String,
    lines: Vec<Line>,
    metadata: Metadata,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct Metadata {
    provider: String,
}

#[derive(Clone, Debug)]
struct ProviderResult {
    provider: &'static str,
    sync_type: &'static str,
    lines: Vec<Line>,
}

#[derive(Default)]
struct Request {
    spdc: String,
    spotify_track_ref: String,
    track_name: String,
    artist_name: String,
    album_name: String,
    length_micros: String,
}

fn lookup_secret(key: &str) -> Option<String> {
    let key = key.trim();
    if key.is_empty() {
        return None;
    }
    let service = SecretService::connect(EncryptionType::Dh).ok()?;
    let attrs = HashMap::from([("service", "quickshell"), ("key", key)]);
    let items = service.search_items(attrs).ok()?;
    if !items.locked.is_empty() {
        let locked = items.locked.iter().collect::<Vec<_>>();
        service.unlock_all(&locked).ok()?;
    }
    items
        .unlocked
        .iter()
        .chain(items.locked.iter())
        .next()
        .and_then(|item| item.get_secret().ok())
        .and_then(|secret| String::from_utf8(secret).ok())
}

fn fetch(req: &Request) -> Result<ResultData, String> {
    if req.track_name.trim().is_empty() || req.artist_name.trim().is_empty() {
        return Err("no lyrics available".to_owned());
    }

    let tuple = identity_tuple(req);
    if let Some(cached) = read_final_cache(&tuple) {
        if !spotify_supported(req)
            || cached.metadata.provider == "spotify"
            || cached.sync_type == SYNC_WORD
        {
            return Ok(cached);
        }
    }

    let providers = [fetch_spotify(req), fetch_netease(req), fetch_lrclib(req)];
    let mut best: Option<ResultData> = None;
    let mut best_rank = 0;
    let mut errors = Vec::new();
    for (idx, candidate) in providers.into_iter().enumerate() {
        match candidate {
            Ok(Some(provider)) => {
                let rank = rank_sync(provider.sync_type);
                if best.as_ref().is_none_or(|_| rank > best_rank) {
                    best_rank = rank;
                    best = Some(new_result(provider));
                    if best_rank >= rank_sync(SYNC_WORD) {
                        break;
                    }
                }
                if best_rank >= max_remaining_rank(idx + 1) {
                    break;
                }
            }
            Ok(None) => {}
            Err(provider) => errors.push(provider),
        }
    }

    if let Some(result) = best {
        write_final_cache(&tuple, &result);
        return Ok(result);
    }
    match errors.len() {
        0 => Err("no lyrics available".to_owned()),
        1 => Err(format!("{} failed", errors[0])),
        _ => Err(format!("{} failed", errors.join(" and "))),
    }
}

fn max_remaining_rank(start: usize) -> i32 {
    match start {
        0 | 1 => rank_sync(SYNC_WORD),
        2 => rank_sync(SYNC_LINE),
        _ => 0,
    }
}

fn new_result(provider: ProviderResult) -> ResultData {
    ResultData {
        source: source_for(provider.provider, provider.sync_type),
        sync_type: provider.sync_type.to_owned(),
        lines: provider.lines,
        metadata: Metadata {
            provider: provider.provider.to_owned(),
        },
    }
}

fn source_for(provider: &str, sync_type: &str) -> String {
    match sync_type {
        SYNC_WORD => format!("{provider}_word"),
        SYNC_LINE => format!("{provider}_synced"),
        _ => format!("{provider}_normal"),
    }
}

fn rank_sync(sync_type: &str) -> i32 {
    match sync_type {
        SYNC_WORD => 3,
        SYNC_LINE => 2,
        _ => 1,
    }
}

// ---------------------------------------------------------------------------
// Spotify provider
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SpotifyServerTime {
    server_time: i64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SpotifyToken {
    access_token: String,
    access_token_expiration_timestamp_ms: i64,
    is_anonymous: bool,
}

#[derive(Deserialize)]
struct SpotifyLyricsResponse {
    lyrics: SpotifyLyrics,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SpotifyLyrics {
    sync_type: String,
    #[serde(default)]
    lines: Vec<SpotifyLine>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SpotifyLine {
    #[serde(default)]
    start_time_ms: String,
    #[serde(default)]
    end_time_ms: String,
    words: String,
}

fn fetch_spotify(req: &Request) -> Result<Option<ProviderResult>, String> {
    let Some(Some(track_id)) =
        spotify_supported(req).then(|| spotify_track_id(&req.spotify_track_ref))
    else {
        return Ok(None);
    };
    let spdc = req.spdc.trim();
    let token = spotify_token(spdc).map_err(|_| "spotify".to_owned())?;
    let mut response = http_agent()
        .get(&format!(
            "{SPOTIFY_LYRICS_BASE_URL}{track_id}?format=json&market=from_token"
        ))
        .header("User-Agent", SPOTIFY_LYRICS_USER_AGENT)
        .header("App-platform", "WebPlayer")
        .header("authorization", format!("Bearer {}", token.access_token))
        .call()
        .map_err(|_| "spotify".to_owned())?;
    if !response.status().is_success() {
        return Err("spotify".to_owned());
    }
    let payload: SpotifyLyricsResponse = response
        .body_mut()
        .read_json()
        .map_err(|_| "spotify".to_owned())?;
    let lines = payload
        .lyrics
        .lines
        .into_iter()
        .map(|line| Line {
            start_time_ms: line.start_time_ms.trim().to_owned(),
            end_time_ms: line.end_time_ms.trim().to_owned(),
            words: line.words,
            ..Line::default()
        })
        .filter(|line| !line.words.trim().is_empty())
        .collect::<Vec<_>>();
    if lines.is_empty() {
        return Ok(None);
    }
    Ok(Some(ProviderResult {
        provider: "spotify",
        sync_type: spotify_sync_type(&payload.lyrics.sync_type, &lines),
        lines,
    }))
}

fn spotify_supported(req: &Request) -> bool {
    !req.spdc.trim().is_empty() && spotify_track_id(&req.spotify_track_ref).is_some()
}

fn spotify_token(spdc: &str) -> Result<SpotifyToken, String> {
    let params = spotify_token_params()?;
    let mut response = http_agent()
        .get(&format!("{SPOTIFY_TOKEN_URL}?{params}"))
        .header("User-Agent", SPOTIFY_TOKEN_USER_AGENT)
        .header("Cookie", format!("sp_dc={spdc}"))
        .call()
        .map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err("spotify token request failed".to_owned());
    }
    let token: SpotifyToken = response.body_mut().read_json().map_err(|e| e.to_string())?;
    if token.access_token.trim().is_empty()
        || token.is_anonymous
        || token.access_token_expiration_timestamp_ms <= now_millis()
    {
        return Err("invalid spotify token".to_owned());
    }
    Ok(token)
}

fn spotify_token_params() -> Result<String, String> {
    let server_time = spotify_server_time()?;
    let (secret, version) = spotify_latest_secret()?;
    let totp = spotify_totp(server_time, &secret)?;
    Ok(format!(
        "reason=transport&productType=web-player&totp={totp}&totpVer={version}&ts={}",
        now_secs()
    ))
}

fn spotify_server_time() -> Result<i64, String> {
    let mut response = http_agent()
        .get(SPOTIFY_SERVER_TIME_URL)
        .header("User-Agent", SPOTIFY_TOKEN_USER_AGENT)
        .call()
        .map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err("spotify server time failed".to_owned());
    }
    let payload: SpotifyServerTime = response.body_mut().read_json().map_err(|e| e.to_string())?;
    (payload.server_time > 0)
        .then_some(payload.server_time)
        .ok_or_else(|| "invalid spotify server time".to_owned())
}

fn spotify_latest_secret() -> Result<(String, String), String> {
    let mut response = http_agent()
        .get(SPOTIFY_SECRET_DICT_URL)
        .call()
        .map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err("spotify secret dict failed".to_owned());
    }
    let body = response
        .body_mut()
        .read_to_vec()
        .map_err(|e| e.to_string())?;
    decode_spotify_secret_dict(&body)
}

fn decode_spotify_secret_dict(body: &[u8]) -> Result<(String, String), String> {
    let mut dec = serde_json::Deserializer::from_slice(body);
    let entries = BTreeMap::<String, Vec<i64>>::deserialize(&mut dec).map_err(|e| e.to_string())?;
    let (version, encoded) = entries
        .into_iter()
        .max_by_key(|(version, _)| version.parse::<i64>().unwrap_or_default())
        .ok_or_else(|| "empty spotify secret dict".to_owned())?;
    let mut secret = String::new();
    for (idx, value) in encoded.into_iter().enumerate() {
        let idx = i64::try_from(idx).unwrap_or(i64::MAX);
        let _ = write!(secret, "{}", value ^ ((idx % 33) + 9));
    }
    if version.is_empty() || secret.is_empty() {
        return Err("invalid spotify secret dict".to_owned());
    }
    Ok((secret, version))
}

fn spotify_totp(server_time: i64, secret: &str) -> Result<String, String> {
    if server_time <= 0 {
        return Err("invalid spotify server time".to_owned());
    }
    let mut mac = Hmac::<Sha1>::new_from_slice(secret.as_bytes()).map_err(|e| e.to_string())?;
    // `server_time > 0` was checked above, so the counter is non-negative.
    let counter = u64::try_from(server_time / 30).unwrap_or(0);
    mac.update(&counter.to_be_bytes());
    let sum = mac.finalize().into_bytes();
    let offset = (sum[sum.len() - 1] & 0x0f) as usize;
    let bin = ((i32::from(sum[offset]) & 0x7f) << 24)
        | ((i32::from(sum[offset + 1]) & 0xff) << 16)
        | ((i32::from(sum[offset + 2]) & 0xff) << 8)
        | (i32::from(sum[offset + 3]) & 0xff);
    Ok(format!("{:06}", bin % 1_000_000))
}

fn spotify_track_id(value: &str) -> Option<String> {
    let value = value.trim();
    if value.len() == 22 && value.bytes().all(|b| b.is_ascii_alphanumeric()) {
        return Some(value.to_owned());
    }
    let marker = if let Some((_, tail)) = value.split_once("track/") {
        tail
    } else if let Some((_, tail)) = value.split_once("track:") {
        tail
    } else {
        return None;
    };
    let id = marker
        .split(|ch: char| !ch.is_ascii_alphanumeric())
        .next()
        .unwrap_or_default();
    (id.len() == 22).then(|| id.to_owned())
}

fn spotify_sync_type(sync_type: &str, lines: &[Line]) -> &'static str {
    match sync_type.trim().to_ascii_uppercase().as_str() {
        SYNC_LINE => SYNC_LINE,
        SYNC_NONE => SYNC_NONE,
        _ if lines
            .iter()
            .any(|line| !line.start_time_ms.trim().is_empty()) =>
        {
            SYNC_LINE
        }
        _ => SYNC_NONE,
    }
}

// ---------------------------------------------------------------------------
// LRCLIB provider
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LrcLibResponse {
    synced_lyrics: Option<String>,
    plain_lyrics: Option<String>,
}

fn fetch_lrclib(req: &Request) -> Result<Option<ProviderResult>, String> {
    let url = lrclib_get_url(req).map_err(|_| "lrclib".to_owned())?;

    let mut response = http_agent()
        .get(url.as_str())
        .header("User-Agent", "quickshell-unified-lyrics-api v1.0.0")
        .call()
        .map_err(|_| "lrclib".to_owned())?;
    if !response.status().is_success() {
        return Err("lrclib".to_owned());
    }
    let payload: LrcLibResponse = response
        .body_mut()
        .read_json()
        .map_err(|_| "lrclib".to_owned())?;

    let lines = parse_lrc(payload.synced_lyrics.as_deref().unwrap_or_default());
    if !lines.is_empty() {
        return Ok(Some(ProviderResult {
            provider: "lrclib",
            sync_type: SYNC_LINE,
            lines,
        }));
    }
    let lines = parse_plain(payload.plain_lyrics.as_deref().unwrap_or_default());
    if lines.is_empty() {
        return Ok(None);
    }
    Ok(Some(ProviderResult {
        provider: "lrclib",
        sync_type: SYNC_NONE,
        lines,
    }))
}

fn lrclib_get_url(req: &Request) -> Result<Url, url::ParseError> {
    let mut url = Url::parse("https://lrclib.net/api/get")?;
    {
        let mut query = url.query_pairs_mut();
        query.append_pair("track_name", req.track_name.trim());
        query.append_pair("artist_name", req.artist_name.trim());
        if !req.album_name.trim().is_empty() {
            query.append_pair("album_name", req.album_name.trim());
        }
        if let Some(duration) = duration_seconds(&req.length_micros) {
            query.append_pair("duration", &duration.to_string());
        }
    }
    Ok(url)
}

// ---------------------------------------------------------------------------
// NetEase provider
// ---------------------------------------------------------------------------

#[derive(Default, Deserialize, Serialize)]
struct Session {
    #[serde(rename = "userId")]
    user_id: i64,
    cookie: BTreeMap<String, String>,
    expire: i64,
}

#[derive(Deserialize)]
struct ApiResponse {
    code: Option<i64>,
    message: Option<String>,
}

#[derive(Deserialize)]
struct AnonymousResponse {
    code: i64,
    #[serde(default, rename = "userId")]
    user_id: i64,
}

#[derive(Deserialize)]
struct SearchResponse {
    data: Option<SearchData>,
}

#[derive(Deserialize)]
struct SearchData {
    #[serde(default)]
    resources: Vec<SearchResource>,
}

#[derive(Deserialize)]
struct SearchResource {
    #[serde(rename = "baseInfo")]
    base_info: BaseInfo,
}

#[derive(Deserialize)]
struct BaseInfo {
    #[serde(rename = "simpleSongData")]
    simple_song_data: Song,
}

#[derive(Deserialize)]
struct Song {
    id: i64,
    name: String,
    #[serde(default, rename = "dt")]
    duration: i64,
    #[serde(default, rename = "ar")]
    artists: Vec<Named>,
    #[serde(default, rename = "al")]
    album: Named,
}

#[derive(Default, Deserialize)]
struct Named {
    #[serde(default)]
    name: String,
}

#[derive(Default, Deserialize)]
struct LyricsBlock {
    #[serde(default)]
    lyric: String,
}

#[derive(Deserialize)]
struct LyricsResponse {
    #[serde(default, rename = "yrc")]
    yrc: LyricsBlock,
    #[serde(default, rename = "lrc")]
    lrc: LyricsBlock,
}

fn fetch_netease(req: &Request) -> Result<Option<ProviderResult>, String> {
    let song = search_netease(req).map_err(|_| "netease".to_owned())?;
    let lyrics = netease_request(
        "/eapi/song/lyric/v1",
        json!({"id": song.id, "lv": "-1", "tv": "-1", "rv": "-1", "yv": "-1"}),
    )
    .and_then(|value| serde_json::from_value::<LyricsResponse>(value).map_err(|e| e.to_string()))
    .map_err(|_| "netease".to_owned())?;

    let lines = parse_yrc(&lyrics.yrc.lyric);
    if !lines.is_empty() {
        return Ok(Some(ProviderResult {
            provider: "netease",
            sync_type: SYNC_WORD,
            lines,
        }));
    }
    let lines = parse_lrc(&lyrics.lrc.lyric);
    if !lines.is_empty() {
        return Ok(Some(ProviderResult {
            provider: "netease",
            sync_type: SYNC_LINE,
            lines,
        }));
    }
    let lines = parse_plain(&lyrics.lrc.lyric);
    if lines.is_empty() {
        return Ok(None);
    }
    Ok(Some(ProviderResult {
        provider: "netease",
        sync_type: SYNC_NONE,
        lines,
    }))
}

fn search_netease(req: &Request) -> Result<Song, String> {
    let keyword = format!("{} {}", req.track_name.trim(), req.artist_name.trim());
    let value = netease_request(
        "/eapi/search/song/list/page",
        json!({"limit": "20", "offset": "0", "keyword": keyword, "scene": "NORMAL", "needCorrect": "true"}),
    )?;
    let payload: SearchResponse = serde_json::from_value(value).map_err(|e| e.to_string())?;
    let mut scored = payload
        .data
        .map(|data| data.resources)
        .unwrap_or_default()
        .into_iter()
        .filter_map(|resource| {
            let song = resource.base_info.simple_song_data;
            let score = score_song(req, &song)?;
            (score >= 100).then_some((score, song))
        })
        .collect::<Vec<_>>();
    scored.sort_by_key(|score| std::cmp::Reverse(score.0));
    scored
        .into_iter()
        .next()
        .map(|(_, song)| song)
        .ok_or_else(|| "lyrics not found".to_owned())
}

fn netease_request(path: &str, mut params: Value) -> Result<Value, String> {
    let session = ensure_session()?;
    let obj = params
        .as_object_mut()
        .ok_or_else(|| "invalid netease params".to_owned())?;
    obj.insert("e_r".to_owned(), Value::Bool(true));
    obj.insert(
        "header".to_owned(),
        Value::String(params_header(&session.cookie)),
    );

    let api_path = path.replacen("eapi", "api", 1);
    let body = encrypt_eapi(&api_path, &params)?;
    let mut response = netease_post(path, &body, &session.cookie)?;
    let raw = response
        .body_mut()
        .read_to_vec()
        .map_err(|e| e.to_string())?;
    let plain = decrypt_eapi(&raw)?;
    let value: Value = serde_json::from_slice(&plain).map_err(|e| e.to_string())?;
    if let Ok(api) = serde_json::from_value::<ApiResponse>(value.clone()) {
        if matches!(api.code, Some(code) if code != 0 && code != 200) {
            return Err(api
                .message
                .unwrap_or_else(|| "netease api error".to_owned()));
        }
    }
    Ok(value)
}

fn ensure_session() -> Result<Session, String> {
    if let Some(session) = read_session_cache() {
        return Ok(session);
    }
    let session = bootstrap_session()?;
    write_session_cache(&session);
    Ok(session)
}

fn bootstrap_session() -> Result<Session, String> {
    let device_id = DEVICE_IDS[random_index(DEVICE_IDS.len())];
    let mut precookie = BTreeMap::from([
        ("os".to_owned(), "pc".to_owned()),
        ("deviceId".to_owned(), device_id.to_owned()),
        ("osver".to_owned(), DEFAULT_OS_VERSION.to_owned()),
        ("clientSign".to_owned(), random_client_sign()),
        ("channel".to_owned(), "netease".to_owned()),
        ("mode".to_owned(), DEFAULT_MODEL.to_owned()),
        ("appver".to_owned(), APP_VERSION.to_owned()),
    ]);
    let params = json!({
        "username": anonymous_username(device_id),
        "e_r": true,
        "header": params_header(&precookie),
    });
    let body = encrypt_eapi("/api/register/anonimous", &params)?;
    let mut response = netease_post("/eapi/register/anonimous", &body, &precookie)?;
    let set_cookies = response
        .headers()
        .get_all("set-cookie")
        .iter()
        .filter_map(|value| value.to_str().ok())
        .filter_map(parse_set_cookie)
        .collect::<Vec<_>>();
    let raw = response
        .body_mut()
        .read_to_vec()
        .map_err(|e| e.to_string())?;
    let plain = decrypt_eapi(&raw)?;
    let payload: AnonymousResponse = serde_json::from_slice(&plain).map_err(|e| e.to_string())?;
    if payload.code != 200 {
        return Err("netease anonymous login failed".to_owned());
    }
    precookie.insert("WEVNSM".to_owned(), "1.0.0".to_owned());
    for (key, value) in set_cookies {
        precookie.insert(key, value);
    }
    if !precookie.contains_key("WNMCID") {
        precookie.insert("WNMCID".to_owned(), random_wnmcid());
    }
    Ok(Session {
        user_id: payload.user_id,
        cookie: precookie,
        expire: now_secs() + 10 * 24 * 60 * 60,
    })
}

fn netease_post(
    path: &str,
    body: &str,
    cookie: &BTreeMap<String, String>,
) -> Result<ureq::http::Response<ureq::Body>, String> {
    let url = format!("https://interface.music.163.com{path}");
    let mut request = http_agent().post(&url);
    let values = [
        ("Accept", "*/*"),
        ("Content-Type", "application/x-www-form-urlencoded"),
        (
            "Mconfig-Info",
            r#"{"IuRPVVmc3WWul9fT":{"version":733184,"appver":"3.1.3.203419"}}"#,
        ),
        ("Origin", "orpheus://orpheus"),
        ("User-Agent", DEFAULT_USER_AGENT),
        ("Sec-Ch-Ua", r#""Chromium";v="91""#),
        ("Sec-Ch-Ua-Mobile", "?0"),
        ("Sec-Fetch-Site", "cross-site"),
        ("Sec-Fetch-Mode", "cors"),
        ("Sec-Fetch-Dest", "empty"),
        ("Accept-Language", "en-US,en;q=0.9"),
    ];
    for (key, value) in values {
        request = request.header(key, value);
    }
    if !cookie.is_empty() {
        let cookie = cookie
            .iter()
            .filter(|(_, value)| !value.trim().is_empty())
            .map(|(key, value)| format!("{key}={value}"))
            .collect::<Vec<_>>()
            .join("; ");
        request = request.header("Cookie", cookie);
    }
    request.send(body).map_err(|e| e.to_string())
}

fn params_header(cookie: &BTreeMap<String, String>) -> String {
    json!({
        "clientSign": cookie.get("clientSign").cloned().unwrap_or_default(),
        "os": cookie.get("os").cloned().unwrap_or_default(),
        "appver": cookie.get("appver").cloned().unwrap_or_default(),
        "deviceId": cookie.get("deviceId").cloned().unwrap_or_default(),
        "requestId": 0,
        "osver": cookie.get("osver").cloned().unwrap_or_default(),
    })
    .to_string()
}

fn parse_set_cookie(raw: &str) -> Option<(String, String)> {
    let cookie = Cookie::parse(raw).ok()?;
    let key = cookie.name().trim();
    let value = cookie.value().trim();
    (!key.is_empty() && !value.is_empty()).then(|| (key.to_owned(), value.to_owned()))
}

const APP_VERSION: &str = "3.1.3.203419";
const DEFAULT_MODEL: &str = "ASUS ROG STRIX Z790";
const DEFAULT_OS_VERSION: &str = "Microsoft-Windows-10--build-22631-64bit";
const DEFAULT_USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/3.1.3.203419";
const EAPI_KEY: &[u8; 16] = b"e82ckenh8dichen8";
const DEVICE_XOR_KEY: &[u8] = b"3go8&$8*3*3h0k(2)2";
const DEVICE_IDS: &[&str] = &[
    "AA9955F5FE37BA7EAF48F8EF0C9966B28293CC8D6415CCD93549",
    "C4BE5BA8E337E26A1ECA938DAF7DDC6D99AA353D9E2E69F5DE2A",
    "2A6626990ED0B095ADBF14D63D91C6F8AE4CF352FF9BD1FE724E",
    "184117F946D9CF013300B74BAAFF42C04B74CE59EDA3A7B31C8E",
    "7051B0BEB96D5DC0DA8C17A034008DE086A21AB833EA41D321FF",
    "90D08AFA4FD3368D3ADD9C7BEB9D40B38066E55B4B2E9C123A26",
];

fn encrypt_eapi(path: &str, params: &Value) -> Result<String, String> {
    let payload = serde_json::to_vec(params).map_err(|e| e.to_string())?;
    let mut hasher = Md5::new();
    hasher.update(b"nobody");
    hasher.update(path.as_bytes());
    hasher.update(b"use");
    hasher.update(&payload);
    hasher.update(b"md5forencrypt");
    let sign = hex::encode(hasher.finalize());
    let plain = [
        path.as_bytes(),
        b"-36cd479b6b5-",
        &payload,
        b"-36cd479b6b5-",
        sign.as_bytes(),
    ]
    .concat();
    Ok(format!(
        "params={}",
        hex::encode_upper(aes_ecb_encrypt(&plain)?)
    ))
}

fn decrypt_eapi(ciphertext: &[u8]) -> Result<Vec<u8>, String> {
    if !ciphertext.len().is_multiple_of(16) {
        return Err("invalid eapi block length".to_owned());
    }
    ecb::Decryptor::<Aes128>::new_from_slice(EAPI_KEY)
        .map_err(|e| e.to_string())?
        .decrypt_padded_vec::<Pkcs7>(ciphertext)
        .map_err(|_| "invalid pkcs7 padding".to_owned())
}

fn aes_ecb_encrypt(plain: &[u8]) -> Result<Vec<u8>, String> {
    ecb::Encryptor::<Aes128>::new_from_slice(EAPI_KEY)
        .map_err(|e| e.to_string())
        .map(|cipher| cipher.encrypt_padded_vec::<Pkcs7>(plain))
}

fn anonymous_username(device_id: &str) -> String {
    let xored = device_id
        .bytes()
        .enumerate()
        .map(|(idx, byte)| byte ^ DEVICE_XOR_KEY[idx % DEVICE_XOR_KEY.len()])
        .collect::<Vec<_>>();
    let digest = Md5::digest(&xored);
    BASE64.encode(format!("{device_id} {}", BASE64.encode(digest)))
}

fn random_client_sign() -> String {
    let mac = (0..6)
        .map(|_| format!("{:02X}", rand::random::<u8>()))
        .collect::<Vec<_>>()
        .join(":");
    let letters = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    let random = random_letters(letters, 8);
    format!("{mac}@@@{random}@@@@@@{}", random_hex(32))
}

fn random_hex(bytes: usize) -> String {
    let mut out = vec![0; bytes];
    rand::rng().fill(&mut out);
    hex::encode(out)
}

fn random_wnmcid() -> String {
    let letters = b"abcdefghijklmnopqrstuvwxyz";
    let prefix = random_letters(letters, 6);
    format!("{prefix}.{}.01.0", now_millis().saturating_sub(5000))
}

fn random_index(len: usize) -> usize {
    rand::rng().random_range(0..len)
}

fn random_letters(letters: &[u8], count: usize) -> String {
    (0..count)
        .map(|_| letters[random_index(letters.len())] as char)
        .collect()
}

// ---------------------------------------------------------------------------
// Lyric text parsing
// ---------------------------------------------------------------------------

fn parse_lrc(text: &str) -> Vec<Line> {
    let re = lrc_re();
    let mut out = Vec::new();
    for row in text
        .trim()
        .lines()
        .map(str::trim)
        .filter(|row| !row.is_empty())
    {
        let tags = re.captures_iter(row).collect::<Vec<_>>();
        if tags.is_empty() {
            continue;
        }
        let words = {
            let stripped = re.replace_all(row, "");
            let stripped = stripped.trim();
            if stripped.is_empty() {
                "♪".to_owned()
            } else {
                stripped.to_owned()
            }
        };
        for tag in tags {
            if let Some(ms) = parse_lrc_time(&tag[1]) {
                out.push(Line {
                    start_time_ms: ms.to_string(),
                    words: words.clone(),
                    ..Line::default()
                });
            }
        }
    }
    out.sort_by_key(|line| line.start_time_ms.parse::<i64>().unwrap_or_default());
    out
}

fn parse_yrc(text: &str) -> Vec<Line> {
    let mut out = Vec::new();
    for raw in text
        .trim()
        .lines()
        .map(str::trim)
        .filter(|row| !row.is_empty())
    {
        let Some(line) = yrc_line_re().captures(raw) else {
            continue;
        };
        let (Ok(start), Ok(duration)) = (line[1].parse::<i64>(), line[2].parse::<i64>()) else {
            continue;
        };
        if start < 0 || duration < 0 {
            continue;
        }
        let content = &line[3];
        let mut segments = Vec::new();
        let mut words = String::new();
        for word in yrc_word_re().captures_iter(content) {
            let (Ok(word_start), Ok(word_duration)) =
                (word[1].parse::<i64>(), word[2].parse::<i64>())
            else {
                continue;
            };
            if word_duration < 0 {
                continue;
            }
            let text = word[3].to_owned();
            words.push_str(&text);
            segments.push(Segment {
                start_time_ms: word_start.to_string(),
                end_time_ms: (word_start + word_duration).to_string(),
                text,
            });
        }
        let words = match words.trim() {
            "" => match content.trim() {
                "" => "♪".to_owned(),
                value => value.to_owned(),
            },
            value => value.to_owned(),
        };
        out.push(Line {
            start_time_ms: start.to_string(),
            end_time_ms: (start + duration).to_string(),
            words,
            segments,
        });
    }
    out
}

fn parse_plain(text: &str) -> Vec<Line> {
    text.trim()
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(|words| Line {
            words: words.to_owned(),
            ..Line::default()
        })
        .collect()
}

fn parse_lrc_time(tag: &str) -> Option<i64> {
    let (minutes, rest) = tag.split_once(':')?;
    let (seconds, frac) = rest.split_once('.').unwrap_or((rest, ""));
    let minutes = minutes.parse::<i64>().ok()?;
    let seconds = seconds.parse::<i64>().ok()?;
    if minutes < 0 || !(0..60).contains(&seconds) {
        return None;
    }
    let mut frac = frac.chars().take(3).collect::<String>();
    while frac.len() < 3 {
        frac.push('0');
    }
    Some((minutes * 60 + seconds) * 1000 + frac.parse::<i64>().unwrap_or_default())
}

// ---------------------------------------------------------------------------
// NetEase search scoring
// ---------------------------------------------------------------------------

fn score_song(req: &Request, song: &Song) -> Option<i32> {
    let want_title = normalize_match(&req.track_name);
    let want_artist = normalize_match(&req.artist_name);
    if want_title.is_empty() || want_artist.is_empty() {
        return None;
    }
    let title_score = score_string(&want_title, &normalize_match(&song.name), 100, 60);
    let artist_score = song
        .artists
        .iter()
        .map(|artist| score_string(&want_artist, &normalize_match(&artist.name), 80, 40))
        .max()
        .unwrap_or_default();
    if title_score == 0 || artist_score == 0 {
        return None;
    }
    let mut score = title_score + artist_score;
    let want_album = normalize_match(&req.album_name);
    if !want_album.is_empty() {
        score += score_string(&want_album, &normalize_match(&song.album.name), 20, 10);
    }
    if let (Some(want_ms), true) = (
        duration_seconds(&req.length_micros).map(|s| s * 1000),
        song.duration > 0,
    ) {
        let delta = (song.duration - want_ms).abs();
        score += if delta <= 2000 {
            20
        } else if delta <= 5000 {
            10
        } else if delta <= 10000 {
            5
        } else {
            0
        };
    }
    Some(score)
}

fn score_string(want: &str, have: &str, exact: i32, fuzzy: i32) -> i32 {
    if want.is_empty() || have.is_empty() {
        0
    } else if want == have {
        exact
    } else if want.contains(have) || have.contains(want) {
        fuzzy
    } else {
        0
    }
}

fn normalize_match(input: &str) -> String {
    let lower = input.trim().to_lowercase();
    let no_feat = feat_re().replace_all(&lower, "");
    let alnum = non_alnum_re().replace_all(&no_feat, " ");
    whitespace_re().replace_all(alnum.trim(), " ").to_string()
}

fn duration_seconds(value: &str) -> Option<i64> {
    let us = value.trim().parse::<i64>().ok()?;
    (us > 0).then_some(us / 1_000_000)
}

fn identity_tuple(req: &Request) -> String {
    format!(
        "{}{TUPLE_SEP}{}{TUPLE_SEP}{}{TUPLE_SEP}{}",
        req.track_name.trim(),
        req.artist_name.trim(),
        req.album_name.trim(),
        req.length_micros
            .trim()
            .parse::<i64>()
            .ok()
            .filter(|value| *value >= 0)
            .map(|value| value.to_string())
            .unwrap_or_default()
    )
}

// ---------------------------------------------------------------------------
// Disk cache (final results + NetEase session)
// ---------------------------------------------------------------------------

#[derive(Deserialize, Serialize)]
struct CacheEnvelope<T> {
    key: String,
    #[serde(rename = "savedAt")]
    saved_at: i64,
    payload: T,
}

#[derive(Deserialize, Serialize)]
struct FinalCache {
    result: ResultData,
    #[serde(rename = "identityTuple")]
    identity_tuple: String,
}

fn read_final_cache(tuple: &str) -> Option<ResultData> {
    let key = final_cache_key(tuple);
    let env = fs::read(cache_path(&key)).ok()?;
    let env: CacheEnvelope<FinalCache> = serde_json::from_slice(&env).ok()?;
    (env.key == key && !env.payload.result.lines.is_empty()).then_some(env.payload.result)
}

fn write_final_cache(tuple: &str, result: &ResultData) {
    if tuple.trim().is_empty() || result.lines.is_empty() {
        return;
    }
    let key = final_cache_key(tuple);
    let env = CacheEnvelope {
        key: key.clone(),
        saved_at: now_secs(),
        payload: FinalCache {
            result: result.clone(),
            identity_tuple: tuple.to_owned(),
        },
    };
    write_cache_json(&key, &env);
}

fn read_session_cache() -> Option<Session> {
    let key = provider_session_key("netease", "anonymous");
    let env = fs::read(cache_path(&key)).ok()?;
    let env: CacheEnvelope<Session> = serde_json::from_slice(&env).ok()?;
    (env.key == key && env.payload.expire > now_secs() && !env.payload.cookie.is_empty())
        .then_some(env.payload)
}

fn write_session_cache(session: &Session) {
    let key = provider_session_key("netease", "anonymous");
    let env = CacheEnvelope {
        key: key.clone(),
        saved_at: now_secs(),
        payload: session,
    };
    write_cache_json(&key, &env);
}

fn write_cache_json<T: Serialize>(key: &str, value: &T) {
    let path = cache_path(key);
    let Some(parent) = path.parent() else { return };
    if fs::create_dir_all(parent).is_err() {
        return;
    }
    let Ok(data) = serde_json::to_vec(value) else {
        return;
    };
    let _ = fs::write(path, data);
}

fn final_cache_key(tuple: &str) -> String {
    logical_key("final_lyrics", "global", &format!("meta:{tuple}"))
}

fn provider_session_key(provider: &str, scope: &str) -> String {
    logical_key(&format!("{provider}_session"), "global", scope)
}

fn logical_key(kind: &str, scope: &str, id: &str) -> String {
    format!("unifiedlyrics:v1:{kind}:{scope}:{id}")
}

fn cache_path(key: &str) -> PathBuf {
    cache_dir()
        .join("entries")
        .join(format!("{}.json", sha256_hex(key)))
}

fn cache_dir() -> PathBuf {
    if let Some(path) = env::var_os("UNIFIED_LYRICS_CACHE_DIR").filter(|value| !value.is_empty()) {
        return PathBuf::from(path);
    }
    if let Some(path) = env::var_os("XDG_CACHE_HOME").filter(|value| !value.is_empty()) {
        return Path::new(&path).join("quickshell/unified-lyrics-api");
    }
    if let Some(home) = env::var_os("HOME").filter(|value| !value.is_empty()) {
        return Path::new(&home).join(".cache/quickshell/unified-lyrics-api");
    }
    PathBuf::from(".cache/quickshell/unified-lyrics-api")
}

fn sha256_hex(value: &str) -> String {
    hex::encode(Sha256::digest(value.as_bytes()))
}

fn http_agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(15)))
        .build()
        .new_agent()
}

fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| i64::try_from(duration.as_secs()).unwrap_or(i64::MAX))
        .unwrap_or_default()
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| i64::try_from(duration.as_millis()).unwrap_or(i64::MAX))
        .unwrap_or_default()
}

fn lrc_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"\[(\d{1,2}:\d{2}(?:\.\d{1,3})?)\]").unwrap())
}

fn yrc_line_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"^\[(\d+),(\d+)\](.*)$").unwrap())
}

fn yrc_word_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"(?:\[\d+,\d+\])?\((\d+),(\d+),\d+\)([^()]*)").unwrap())
}

fn feat_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"(?i)\s*[\(\[]\s*(feat|ft|with|remaster|version|live|edit)[^)\]]*[\)\]]")
            .unwrap()
    })
}

fn non_alnum_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"[^\p{L}\p{N}]+").unwrap())
}

fn whitespace_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"\s+").unwrap())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aes_ecb_round_trips_and_rejects_bad_tail() {
        let padded = aes_ecb_encrypt(b"hello").unwrap();
        assert_eq!(padded.len(), 16);
        assert_eq!(decrypt_eapi(&padded).unwrap(), b"hello");

        let full_block = aes_ecb_encrypt(b"1234567890abcdef").unwrap();
        assert_eq!(full_block.len(), 32);
        assert_eq!(decrypt_eapi(&full_block).unwrap(), b"1234567890abcdef");

        assert!(decrypt_eapi(&[]).is_err());
        assert!(decrypt_eapi(&[0; 15]).is_err());

        let mut invalid = aes_ecb_encrypt(b"hello").unwrap();
        let last = invalid.len() - 1;
        invalid[last] = 0;
        assert!(decrypt_eapi(&invalid).is_err());
    }

    #[test]
    fn parses_lrc_and_yrc() {
        let lrc = parse_lrc("[00:01.20]hello\n[00:00.50]first");
        assert_eq!(lrc[0].start_time_ms, "500");
        assert_eq!(lrc[1].words, "hello");

        let yrc = parse_yrc("[1000,2000](1000,500,0)Hel(1500,500,0)lo(2000,1000,0) world");
        assert_eq!(yrc[0].end_time_ms, "3000");
        assert_eq!(yrc[0].words, "Hello world");
        assert_eq!(yrc[0].segments[1].text, "lo");
    }

    #[test]
    fn lrclib_url_uses_query_pairs_for_track_identity() {
        let url = lrclib_get_url(&Request {
            track_name: "Sweet Child O' Mine".to_owned(),
            artist_name: "Guns N' Roses".to_owned(),
            album_name: "Appetite For Destruction".to_owned(),
            length_micros: "356000000".to_owned(),
            ..Request::default()
        })
        .expect("lrclib url");

        assert_eq!(
            url.as_str(),
            "https://lrclib.net/api/get?track_name=Sweet+Child+O%27+Mine&artist_name=Guns+N%27+Roses&album_name=Appetite+For+Destruction&duration=356"
        );
    }

    #[test]
    fn normalizes_and_scores_netease_matches() {
        let req = Request {
            spdc: String::new(),
            spotify_track_ref: String::new(),
            track_name: "Song (feat. Someone)".to_owned(),
            artist_name: "Artist".to_owned(),
            album_name: "Album".to_owned(),
            length_micros: "123000000".to_owned(),
        };
        let song = Song {
            id: 1,
            name: "song".to_owned(),
            duration: 123_000,
            artists: vec![Named {
                name: "artist".to_owned(),
            }],
            album: Named {
                name: "album deluxe".to_owned(),
            },
        };
        assert_eq!(normalize_match("Track [Live edit]!!"), "track");
        assert!(score_song(&req, &song).unwrap() >= 200);
    }

    #[test]
    fn spotify_track_id_accepts_bare_url_and_uri() {
        let id = "1QrbZhFYlViXd60g130vw1";
        assert_eq!(spotify_track_id(id).as_deref(), Some(id));
        assert_eq!(
            spotify_track_id("https://open.spotify.com/track/1QrbZhFYlViXd60g130vw1?si=x")
                .as_deref(),
            Some(id)
        );
        assert_eq!(
            spotify_track_id("spotify:track:1QrbZhFYlViXd60g130vw1").as_deref(),
            Some(id)
        );
    }

    #[test]
    fn spotify_secret_dict_uses_highest_numeric_version() {
        let (secret, version) = decode_spotify_secret_dict(br#"{"9":[72],"10":[73]}"#).unwrap();
        assert_eq!(version, "10");
        #[expect(
            clippy::decimal_bitwise_operands,
            reason = "mirrors decode_spotify_secret_dict's decimal XOR-with-offset encoding, not a bitmask"
        )]
        {
            assert_eq!(secret, format!("{}", 73 ^ 9));
        }
    }

    #[test]
    fn parses_set_cookie_with_attributes() {
        assert_eq!(
            parse_set_cookie("MUSIC_U=token; Max-Age=1296000; Path=/; HttpOnly"),
            Some(("MUSIC_U".to_owned(), "token".to_owned()))
        );
        assert_eq!(parse_set_cookie("empty=; Path=/"), None);
    }

    #[test]
    fn random_netease_identifiers_keep_wire_shape() {
        let sign = random_client_sign();
        let (mac, rest) = sign.split_once("@@@").expect("mac delimiter");
        let (letters, hex) = rest.split_once("@@@@@@").expect("hex delimiter");
        assert_eq!(mac.split(':').count(), 6);
        assert_eq!(letters.len(), 8);
        assert_eq!(hex.len(), 64);

        let wnmcid = random_wnmcid();
        assert!(wnmcid.ends_with(".01.0"));
        assert_eq!(wnmcid.split('.').next().unwrap_or_default().len(), 6);
    }
}
