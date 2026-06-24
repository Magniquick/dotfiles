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
use std::{
    collections::{BTreeMap, HashMap},
    env,
    fmt::Write as _,
    fs,
    path::{Path, PathBuf},
    pin::Pin,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, OnceLock,
    },
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use url::Url;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};

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

type QVariantList = QList<QVariant>;
type QVariantMap = QMap<QMapPair_QString_QVariant>;

#[derive(Clone, Default)]
pub struct UnifiedLyricsClientRust {
    busy: bool,
    loaded: bool,
    status: QString,
    error: QString,
    source: QString,
    sync_type: QString,
    metadata: QVariantMap,
    lines: QVariantList,
    request_id: u64,
    current_request: Arc<AtomicU64>,
}

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;

        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;

        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<QVariant>;

        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;

        include!("unifiedlyrics_qt_helpers.h");
        fn unifiedlyrics_variant_from_map(map: &QMap_QString_QVariant) -> QVariant;
        fn unifiedlyrics_variant_from_list(list: &QList_QVariant) -> QVariant;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, busy, READ, NOTIFY)]
        #[qproperty(bool, loaded, READ, NOTIFY)]
        #[qproperty(QString, status, READ, NOTIFY)]
        #[qproperty(QString, error, READ, NOTIFY)]
        #[qproperty(QString, source, READ, NOTIFY)]
        #[qproperty(QString, sync_type, cxx_name = "syncType", READ, NOTIFY)]
        #[qproperty(QMap_QString_QVariant, metadata, READ, NOTIFY)]
        #[qproperty(QList_QVariant, lines, READ, NOTIFY)]
        type UnifiedLyricsClient = super::UnifiedLyricsClientRust;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qinvokable]
        fn refresh(
            self: Pin<&mut UnifiedLyricsClient>,
            spotify_track_ref: &QString,
            track_name: &QString,
            artist_name: &QString,
            album_name: &QString,
            length_micros: &QString,
        ) -> bool;
    }

    impl cxx_qt::Threading for UnifiedLyricsClient {}

    impl cxx_qt::Initialize for UnifiedLyricsClient {}
}

impl cxx_qt::Initialize for ffi::UnifiedLyricsClient {
    fn initialize(self: Pin<&mut Self>) {}
}

impl ffi::UnifiedLyricsClient {
    pub fn refresh(
        mut self: Pin<&mut Self>,
        spotify_track_ref: &QString,
        track_name: &QString,
        artist_name: &QString,
        album_name: &QString,
        length_micros: &QString,
    ) -> bool {
        let spotify_track_ref = spotify_track_ref.to_string().trim().to_owned();
        let track_name = track_name.to_string().trim().to_owned();
        let artist_name = artist_name.to_string().trim().to_owned();
        let album_name = album_name.to_string().trim().to_owned();
        let length_micros = length_micros.to_string().trim().to_owned();

        if track_name.is_empty() || artist_name.is_empty() {
            self.as_mut()
                .set_error_state(QString::from("trackName and artistName required"));
            self.as_mut().set_status_state(QString::from("Error"));
            self.as_mut().set_loaded_state(false);
            return false;
        }

        println!(
            "UnifiedLyricsClient refresh track= {track_name} artist= {artist_name} album= {album_name} spotifyRef= {spotify_track_ref} lengthMicros= {length_micros}"
        );

        let request_id = {
            let mut rust = self.as_mut().rust_mut();
            let rust = rust.as_mut().get_mut();
            rust.request_id = rust.request_id.wrapping_add(1);
            rust.current_request
                .store(rust.request_id, Ordering::SeqCst);
            rust.request_id
        };
        let current_request = Arc::clone(&self.as_ref().rust().current_request);

        self.as_mut().set_busy_state(true);
        self.as_mut().set_loaded_state(false);
        self.as_mut().set_error_state(QString::default());
        self.as_mut()
            .set_status_state(QString::from("Fetching lyrics..."));
        self.as_mut().set_source_state(QString::default());
        self.as_mut().set_sync_type_state(QString::default());
        self.as_mut().set_metadata_state(QVariantMap::default());
        self.as_mut().set_lines_state(QVariantList::default());

        let qt_thread = self.as_ref().qt_thread();
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_secs(30));
            let current_request = Arc::clone(&current_request);
            let _ = qt_thread.queue(move |mut client| {
                if current_request.load(Ordering::SeqCst) != request_id || !*client.busy() {
                    return;
                }
                current_request.store(request_id.wrapping_add(1), Ordering::SeqCst);
                client
                    .as_mut()
                    .set_error_state(QString::from("Timeout while fetching lyrics"));
                client.as_mut().set_status_state(QString::from("Timed out"));
                client.as_mut().set_busy_state(false);
                client.as_mut().set_loaded_state(false);
            });
        });

        let qt_thread = self.as_ref().qt_thread();
        let current_request = Arc::clone(&self.as_ref().rust().current_request);
        std::thread::spawn(move || {
            let req = Request {
                spdc: lookup_secret("SP_DC").unwrap_or_default(),
                spotify_track_ref,
                track_name,
                artist_name,
                album_name,
                length_micros,
            };
            let result = fetch(req);
            let _ = qt_thread.queue(move |mut client| {
                if current_request.load(Ordering::SeqCst) != request_id {
                    return;
                }
                match result {
                    Ok(result) => client.as_mut().publish_result(result),
                    Err(error) => client.as_mut().publish_error(error),
                }
            });
        });

        true
    }

    fn publish_result(mut self: Pin<&mut Self>, result: ResultData) {
        let line_count = result.lines.len();
        let lines = lines_to_qvariant_list(result.lines);
        let mut metadata = QVariantMap::default();
        metadata.insert(
            QString::from("provider"),
            QVariant::from(&QString::from(result.metadata.provider.as_str())),
        );

        println!(
            "UnifiedLyricsClient loaded source= {} provider= {} syncType= {} lines= {}",
            result.source, result.metadata.provider, result.sync_type, line_count
        );

        self.as_mut()
            .set_source_state(QString::from(result.source.as_str()));
        self.as_mut()
            .set_sync_type_state(QString::from(result.sync_type.as_str()));
        self.as_mut().set_metadata_state(metadata);
        self.as_mut().set_lines_state(lines);
        self.as_mut().set_status_state(QString::from("OK"));
        self.as_mut().set_busy_state(false);
        self.as_mut().set_loaded_state(true);
    }

    fn publish_error(mut self: Pin<&mut Self>, error: String) {
        let message = if error.is_empty() {
            "Unknown error".to_owned()
        } else {
            error
        };
        eprintln!("UnifiedLyricsClient backend error message= {message}");
        self.as_mut()
            .set_error_state(QString::from(message.as_str()));
        self.as_mut().set_status_state(QString::from("Error"));
        self.as_mut().set_busy_state(false);
        self.as_mut().set_loaded_state(false);
    }

    fn set_busy_state(mut self: Pin<&mut Self>, value: bool) {
        if *self.busy() == value {
            return;
        }
        self.as_mut().rust_mut().as_mut().get_mut().busy = value;
        self.as_mut().busy_changed();
    }

    fn set_loaded_state(mut self: Pin<&mut Self>, value: bool) {
        if *self.loaded() == value {
            return;
        }
        self.as_mut().rust_mut().as_mut().get_mut().loaded = value;
        self.as_mut().loaded_changed();
    }

    fn set_status_state(mut self: Pin<&mut Self>, value: QString) {
        if *self.status() == value {
            return;
        }
        self.as_mut().rust_mut().as_mut().get_mut().status = value;
        self.as_mut().status_changed();
    }

    fn set_error_state(mut self: Pin<&mut Self>, value: QString) {
        if *self.error() == value {
            return;
        }
        self.as_mut().rust_mut().as_mut().get_mut().error = value;
        self.as_mut().error_changed();
    }

    fn set_source_state(mut self: Pin<&mut Self>, value: QString) {
        if *self.source() == value {
            return;
        }
        self.as_mut().rust_mut().as_mut().get_mut().source = value;
        self.as_mut().source_changed();
    }

    fn set_sync_type_state(mut self: Pin<&mut Self>, value: QString) {
        if *self.sync_type() == value {
            return;
        }
        self.as_mut().rust_mut().as_mut().get_mut().sync_type = value;
        self.as_mut().sync_type_changed();
    }

    fn set_metadata_state(mut self: Pin<&mut Self>, value: QVariantMap) {
        if *self.metadata() == value {
            return;
        }
        self.as_mut().rust_mut().as_mut().get_mut().metadata = value;
        self.as_mut().metadata_changed();
    }

    fn set_lines_state(mut self: Pin<&mut Self>, value: QVariantList) {
        self.as_mut().rust_mut().as_mut().get_mut().lines = value;
        self.as_mut().lines_changed();
    }
}

fn lines_to_qvariant_list(lines: Vec<Line>) -> QVariantList {
    let mut out = QVariantList::default();
    out.reserve(lines.len().try_into().unwrap_or(isize::MAX));
    for line in lines {
        let mut row = QVariantMap::default();
        row.insert(
            QString::from("startTimeMs"),
            QVariant::from(&QString::from(line.start_time_ms.as_str())),
        );
        row.insert(
            QString::from("endTimeMs"),
            QVariant::from(&QString::from(line.end_time_ms.as_str())),
        );
        row.insert(
            QString::from("words"),
            QVariant::from(&QString::from(line.words.as_str())),
        );
        row.insert(
            QString::from("segments"),
            ffi::unifiedlyrics_variant_from_list(&segments_to_qvariant_list(line.segments)),
        );
        out.append(ffi::unifiedlyrics_variant_from_map(&row));
    }
    out
}

fn segments_to_qvariant_list(segments: Vec<Segment>) -> QVariantList {
    let mut out = QVariantList::default();
    out.reserve(segments.len().try_into().unwrap_or(isize::MAX));
    for segment in segments {
        let mut row = QVariantMap::default();
        row.insert(
            QString::from("startTimeMs"),
            QVariant::from(&QString::from(segment.start_time_ms.as_str())),
        );
        row.insert(
            QString::from("endTimeMs"),
            QVariant::from(&QString::from(segment.end_time_ms.as_str())),
        );
        row.insert(
            QString::from("text"),
            QVariant::from(&QString::from(segment.text.as_str())),
        );
        out.append(ffi::unifiedlyrics_variant_from_map(&row));
    }
    out
}

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

fn fetch(req: Request) -> Result<ResultData, String> {
    if req.track_name.trim().is_empty() || req.artist_name.trim().is_empty() {
        return Err("no lyrics available".to_owned());
    }

    let tuple = identity_tuple(&req);
    if let Some(cached) = read_final_cache(&tuple) {
        if !spotify_supported(&req)
            || cached.metadata.provider == "spotify"
            || cached.sync_type == SYNC_WORD
        {
            return Ok(cached);
        }
    }

    let providers = [fetch_spotify(&req), fetch_netease(&req), fetch_lrclib(&req)];
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
    let track_id = match spotify_supported(req).then(|| spotify_track_id(&req.spotify_track_ref)) {
        Some(Some(id)) => id,
        _ => return Ok(None),
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
        let _ = write!(secret, "{}", value ^ ((idx as i64 % 33) + 9));
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
    mac.update(&((server_time / 30) as u64).to_be_bytes());
    let sum = mac.finalize().into_bytes();
    let offset = (sum[sum.len() - 1] & 0x0f) as usize;
    let bin = ((sum[offset] as i32 & 0x7f) << 24)
        | ((sum[offset + 1] as i32 & 0xff) << 16)
        | ((sum[offset + 2] as i32 & 0xff) << 8)
        | (sum[offset + 3] as i32 & 0xff);
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
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or_default()
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
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
            duration: 123000,
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
        assert_eq!(secret, format!("{}", 73 ^ 9));
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
