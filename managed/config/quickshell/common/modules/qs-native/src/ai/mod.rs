use base64::{engine::general_purpose::STANDARD as BASE64_STANDARD, Engine as _};
use chrono::{DateTime, Utc};
use rig::client::CompletionClient;
use rig::client::verify::VerifyClient;
use rig::completion::CompletionModel as _;
use rig::http_client::HttpClientExt;
use rig::message::{ImageMediaType, UserContent};
use rig::one_or_many::OneOrMany;
use rig::streaming::StreamedAssistantContent;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::time::{Duration, Instant};
use std::sync::Mutex;
use std::{process::Command, sync::OnceLock};

mod chat_session;
mod model_catalog;

fn image_media_type_from_mime(mime: &str) -> Option<ImageMediaType> {
  match mime.trim().to_lowercase().as_str() {
    "image/jpeg" | "image/jpg" => Some(ImageMediaType::JPEG),
    "image/png" => Some(ImageMediaType::PNG),
    "image/webp" => Some(ImageMediaType::WEBP),
    "image/heic" => Some(ImageMediaType::HEIC),
    "image/heif" => Some(ImageMediaType::HEIF),
    _ => None,
  }
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct UiModelOption {
  value: String,
  label: String,
  description: String,
  provider: String, // "openai" | "gemini"
  recommended: bool,
}

#[derive(Clone, Debug)]
pub(crate) struct ChatMessage {
  message_id: String,
  sender: String,
  body: String,
  kind: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct ChatAttachment {
  mime: String,
  b64: String,
  #[serde(default)]
  path: String,
}

#[derive(Clone)]
pub(crate) struct OpenAiCache {
  api_key: String,
  base_url: String,
  completions: rig::providers::openai::CompletionsClient<rig::http_client::ReqwestClient>,
}

#[derive(Clone)]
pub(crate) struct GeminiCache {
  api_key: String,
  client: rig::providers::gemini::Client<rig::http_client::ReqwestClient>,
}

const MODEL_CATALOG_TTL: Duration = Duration::from_secs(10 * 60);

struct PinnedModel {
  value: &'static str,
  label: &'static str,
  description: &'static str,
  provider: &'static str, // "openai" | "gemini"
}

const PINNED_MODELS: &[PinnedModel] = &[
  PinnedModel {
    value: "gemini-3-flash-preview",
    label: "Gemini 3 Flash",
    description: "gemini-3-flash-preview",
    provider: "gemini",
  },
  PinnedModel {
    value: "gpt-5.2",
    label: "gpt-5.2 (low reasoning)",
    description: "gpt-5.2 (note: reasoning effort is not currently set by qs-native)",
    provider: "openai",
  },
  PinnedModel {
    value: "gemini-2.5-flash-lite",
    label: "Gemini 2.5 Flash Lite",
    description: "gemini-2.5-flash-lite",
    provider: "gemini",
  },
  PinnedModel {
    value: "gpt-5-mini",
    label: "GPT-5 mini",
    description: "gpt-5-mini",
    provider: "openai",
  },
];

struct ModelCatalogCacheEntry {
  key_hash: u64,
  stored_at: Instant,
  models_json: String,
}

fn model_catalog_cache() -> &'static Mutex<Option<ModelCatalogCacheEntry>> {
  static CACHE: OnceLock<Mutex<Option<ModelCatalogCacheEntry>>> = OnceLock::new();
  CACHE.get_or_init(|| Mutex::new(None))
}

fn model_catalog_key_hash(openai_key: &str, gemini_key: &str, openai_base_url: &str) -> u64 {
  let mut hasher = std::collections::hash_map::DefaultHasher::new();
  openai_key.hash(&mut hasher);
  gemini_key.hash(&mut hasher);
  openai_base_url.hash(&mut hasher);
  hasher.finish()
}

fn clean_provider_message(msg: &str) -> String {
  let mut out = msg.trim().to_string();
  if let Some(idx) = out.find("For more information") {
    out = out[..idx].trim().to_string();
  }
  if let Some(idx) = out.find("for more information") {
    out = out[..idx].trim().to_string();
  }
  if let Some(idx) = out.find("http://") {
    out = out[..idx].trim().to_string();
  }
  if let Some(idx) = out.find("https://") {
    out = out[..idx].trim().to_string();
  }
  out.trim_end_matches('.').trim().to_string()
}

fn try_extract_error_message_from_json(body: &[u8]) -> Option<String> {
  let v: serde_json::Value = serde_json::from_slice(body).ok()?;
  let m = v.get("error")?.get("message")?.as_str()?;
  let cleaned = clean_provider_message(m);
  if cleaned.is_empty() { None } else { Some(cleaned) }
}

fn try_extract_error_message_from_rig_error_text(err: &str) -> Option<String> {
  let needle = "with message:";
  let idx = err.find(needle)?;
  let json_part = err[idx + needle.len()..].trim();
  let json_start = json_part.find('{')?;
  let json_text = json_part[json_start..].trim();
  let v: serde_json::Value = serde_json::from_str(json_text).ok()?;
  let m = v.get("error")?.get("message")?.as_str()?;
  let cleaned = clean_provider_message(m);
  if cleaned.is_empty() { None } else { Some(cleaned) }
}

fn openai_model_allowed(model_id: &str) -> bool {
  let id = model_id.to_lowercase();

  let family_ok = id.starts_with("gpt-") || id.starts_with("chatgpt-") || id.starts_with('o');
  if !family_ok {
    return false;
  }

  let deny = [
    "gpt-image",
    "dall-e",
    "whisper",
    "tts",
    "embedding",
    "embed",
    "moderation",
    "omni-moderation",
    "realtime",
    "audio",
    "transcribe",
    "transcription",
  ];
  if deny.iter().any(|s| id.contains(s)) {
    return false;
  }

  true
}

fn apply_pinned_models(models: &mut Vec<UiModelOption>) {
  let mut pinned_index: HashMap<&'static str, usize> = HashMap::new();
  for (idx, m) in PINNED_MODELS.iter().enumerate() {
    pinned_index.insert(m.value, idx);
  }

  for m in models.iter_mut() {
    if let Some(idx) = pinned_index.get(m.value.as_str()) {
      let pin = &PINNED_MODELS[*idx];
      m.recommended = true;
      m.provider = pin.provider.to_string();
      m.label = pin.label.to_string();
      if m.description.trim().is_empty() {
        m.description = pin.description.to_string();
      }
    } else {
      m.recommended = false;
    }
  }

  models.sort_by(|a, b| {
    let ia = pinned_index.get(a.value.as_str()).copied();
    let ib = pinned_index.get(b.value.as_str()).copied();
    match (ia, ib) {
      (Some(ia), Some(ib)) => ia.cmp(&ib),
      (Some(_), None) => std::cmp::Ordering::Less,
      (None, Some(_)) => std::cmp::Ordering::Greater,
      (None, None) => {
        let pa = if a.provider == "openai" { 0 } else { 1 };
        let pb = if b.provider == "openai" { 0 } else { 1 };
        pa.cmp(&pb).then_with(|| a.value.cmp(&b.value))
      }
    }
  });
}
