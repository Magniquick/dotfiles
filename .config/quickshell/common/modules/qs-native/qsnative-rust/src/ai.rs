mod stream;

use std::collections::{BTreeMap, HashMap};
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;
use std::time::Instant;

use crate::mcp::{tool_result_transcript_output, ToolDescriptor, ToolResult};
use crate::utils::first_non_empty;
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};

type TokenCallback = unsafe extern "C" fn(*mut c_void, *const c_char, c_int);

static NEXT_SESSION_ID: AtomicI32 = AtomicI32::new(1);
static SESSIONS: OnceLock<Mutex<HashMap<i32, Arc<AtomicBool>>>> = OnceLock::new();
static LAST_METRICS: OnceLock<Mutex<SessionMetrics>> = OnceLock::new();

#[derive(Debug, Clone, Default, Serialize)]
struct SessionMetrics {
    model: String,
    chunk_count: i32,
    prompt_tokens: i32,
    output_tokens: i32,
    ttf_ms: f64,
    total_ms: f64,
    finished: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    error: String,
}

struct MetricTracker {
    turn_start: Instant,
    round_start: Instant,
    chunk_count: i32,
    ttf_ms: f64,
}

impl MetricTracker {
    fn new() -> Self {
        let now = Instant::now();
        Self {
            turn_start: now,
            round_start: now,
            chunk_count: 0,
            ttf_ms: -1.0,
        }
    }

    fn begin_provider_round(&mut self) {
        self.round_start = Instant::now();
    }

    fn observe_token(&mut self, token: &str) -> bool {
        if token.is_empty() {
            return false;
        }
        if self.chunk_count == 0 {
            self.ttf_ms = self.round_start.elapsed().as_secs_f64() * 1000.0;
        }
        self.chunk_count += 1;
        true
    }

    fn total_ms(&self) -> f64 {
        self.turn_start.elapsed().as_secs_f64() * 1000.0
    }
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub(crate) struct Attachment {
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub(crate) path: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub(crate) mime: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub(crate) b64: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub(crate) url: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct ProviderConfig {
    #[serde(default)]
    api_key: String,
    #[serde(default)]
    base_url: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct ConfiguredModel {
    #[serde(default)]
    raw_id: String,
    #[serde(default)]
    label: String,
    #[serde(default)]
    description: String,
    #[serde(default)]
    recommended: Option<bool>,
    #[serde(default)]
    capabilities: Map<String, Value>,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct LocalModelEntry {
    #[serde(default)]
    id: String,
}

#[derive(Debug, Clone)]
struct RecommendedModel {
    raw_id: String,
    label: String,
    description: String,
    recommended: bool,
    capabilities: Map<String, Value>,
}

#[derive(Debug, Clone)]
struct Provider {
    id: String,
    label: String,
    icon: &'static str,
    icon_image: &'static str,
    accent_role: &'static str,
    enabled: bool,
    model_ids: Vec<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct ToolCall {
    #[serde(default)]
    id: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    namespace: String,
    name: String,
    #[serde(default, skip_serializing_if = "Map::is_empty")]
    arguments: Map<String, Value>,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    input: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    raw_items: Vec<Map<String, Value>>,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    server_id: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    server_label: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    tool_title: String,
    #[serde(default, skip_serializing_if = "crate::utils::is_false")]
    read_only: bool,
    #[serde(default, skip_serializing_if = "crate::utils::is_false")]
    destructive: bool,
    #[serde(default, skip_serializing_if = "crate::utils::is_false")]
    open_world: bool,
    #[serde(default, skip_serializing_if = "crate::utils::is_false")]
    idempotent: bool,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    risk: String,
}

#[derive(Debug, Clone, Default)]
struct StreamRequest {
    model_id: String,
    raw_model_id: String,
    provider: String,
    config: ProviderConfig,
    system_prompt: String,
    conversation_id: String,
    message: String,
    attachments: Vec<Attachment>,
    tools: Vec<ToolDescriptor>,
    provider_search_enabled: bool,
}

#[derive(Debug, Clone, Default)]
struct StreamResult {
    prompt_tokens: i32,
    output_tokens: i32,
}

#[no_mangle]
/// Starts an AI streaming session on a background thread.
///
/// # Safety
///
/// All pointer arguments must be either null or point to valid NUL-terminated
/// strings for the duration of this call. `cb` must remain valid until the
/// stream sends a terminal callback, and `ctx` must remain valid for each
/// callback invocation.
pub unsafe extern "C" fn QsNative_AiChat_Stream(
    model_id: *const c_char,
    provider_config_json: *const c_char,
    system_prompt: *const c_char,
    conversation_id: *const c_char,
    message: *const c_char,
    attachments_json: *const c_char,
    disabled_tool_servers_json: *const c_char,
    cb: Option<TokenCallback>,
    ctx: *mut c_void,
) -> c_int {
    let Some(cb) = cb else {
        return -1;
    };

    let id = NEXT_SESSION_ID.fetch_add(1, Ordering::SeqCst);
    let cancelled = Arc::new(AtomicBool::new(false));
    sessions()
        .lock()
        .expect("session mutex")
        .insert(id, cancelled.clone());

    let args = StreamArgs {
        model_id: c_string(model_id),
        provider_config_json: c_string(provider_config_json),
        system_prompt: c_string(system_prompt),
        conversation_id: c_string(conversation_id),
        message: c_string(message),
        attachments_json: c_string(attachments_json),
        disabled_tool_servers_json: c_string(disabled_tool_servers_json),
        ctx: ctx as usize,
        cb,
        cancelled,
        id,
    };

    thread::spawn(move || run_stream(args));
    id
}

#[no_mangle]
pub extern "C" fn QsNative_AiChat_Cancel(id: c_int) {
    if let Some(cancelled) = sessions().lock().expect("session mutex").get(&id).cloned() {
        cancelled.store(true, Ordering::SeqCst);
    }
}

#[no_mangle]
pub extern "C" fn QsNative_AiChat_LastMetrics() -> *mut c_char {
    let metrics = last_metrics().lock().expect("metrics mutex").clone();
    into_c_string(serde_json::to_string(&metrics).unwrap_or_else(|_| "{}".to_owned()))
}

#[no_mangle]
pub extern "C" fn QsNative_AiModels_Catalog(
    provider_config_json: *const c_char,
    provider_order_json: *const c_char,
    configured_models_json: *const c_char,
) -> *mut c_char {
    let catalog = model_catalog_json(
        &c_string(provider_config_json),
        &c_string(provider_order_json),
        &c_string(configured_models_json),
    );
    into_c_string(catalog)
}

struct StreamArgs {
    model_id: String,
    provider_config_json: String,
    system_prompt: String,
    conversation_id: String,
    message: String,
    attachments_json: String,
    disabled_tool_servers_json: String,
    ctx: usize,
    cb: TokenCallback,
    cancelled: Arc<AtomicBool>,
    id: i32,
}

fn run_stream(args: StreamArgs) {
    let result = run_stream_inner(&args);
    sessions().lock().expect("session mutex").remove(&args.id);
    if let Err(error) = result {
        callback(args.cb, args.ctx, &error, -1);
    }
}

fn run_stream_inner(args: &StreamArgs) -> Result<(), String> {
    let (provider, raw_model_id) = split_model_id(&args.model_id)?;
    if !matches!(provider.as_str(), "openai" | "local" | "gemini") {
        let message = format!("unknown provider: {provider}");
        store_metrics(SessionMetrics {
            model: args.model_id.clone(),
            ttf_ms: -1.0,
            error: message.clone(),
            ..SessionMetrics::default()
        });
        return Err(message);
    }

    let config = provider_config(&args.provider_config_json, &provider);
    let attachments = parse_json_array::<Attachment>(&args.attachments_json);
    if !attachments.is_empty() {
        ensure_attachment_capability(&args.model_id)?;
    }

    let mut req = StreamRequest {
        model_id: args.model_id.clone(),
        raw_model_id,
        provider: provider.clone(),
        config,
        system_prompt: args.system_prompt.clone(),
        conversation_id: args.conversation_id.clone(),
        message: args.message.clone(),
        attachments,
        tools: Vec::new(),
        provider_search_enabled: false,
    };

    let disabled_tool_servers = disabled_tool_servers(&args.disabled_tool_servers_json);
    req.provider_search_enabled = provider_search_enabled(&req)
        && !disabled_tool_servers
            .iter()
            .any(|server| server == "provider_search");
    if supports_tools(&req) {
        req.tools = mcp_tool_descriptors(&disabled_tool_servers);
    }

    stream::run(args, req)
}

fn tool_start_event_json(call: &ToolCall) -> String {
    let display_name = tool_call_display_name(call);
    must_json(&json!({
        "kind":"tool",
        "phase":"tool_start",
        "tool_call_id":call.id,
        "tool_name":call.name,
        "tool_title":empty_to_null(&call.tool_title),
        "server_id":empty_to_null(&call.server_id),
        "server_label":empty_to_null(&call.server_label),
        "namespace":empty_to_null(&call.namespace),
        "read_only":call.read_only,
        "risk":empty_to_null(&call.risk),
        "status":"running",
        "summary":format!("running {display_name}..."),
        "subtitle":tool_start_subtitle(call),
    }))
}

fn tool_done_event_json(call: &ToolCall, result: &ToolResult) -> String {
    let is_error = result.is_error;
    let phase = if is_error { "tool_error" } else { "tool_done" };
    let status = if is_error { "error" } else { "success" };
    let display_name = tool_call_display_name(call);
    let summary = if is_error {
        format!("failed {display_name}")
    } else {
        format!("called {display_name}")
    };
    let subtitle = first_non_empty([
        &result.text,
        if is_error {
            "tool returned an error"
        } else {
            "completed"
        },
    ]);
    let mut sections = Vec::new();
    if !call.arguments.is_empty() {
        sections
            .push(json!({"title":"Arguments","content":must_json(&call.arguments),"kind":"json"}));
    }
    if !result.text.trim().is_empty() {
        sections.push(json!({"title":"Result","content":result.text,"kind":"text"}));
    }
    must_json(&json!({
        "kind":"tool",
        "phase":phase,
        "tool_call_id":first_non_empty([&result.tool_call_id, &call.id]),
        "tool_name":first_non_empty([&result.name, &call.name]),
        "tool_title":empty_to_null(&call.tool_title),
        "server_id":empty_to_null(&call.server_id),
        "server_label":empty_to_null(&call.server_label),
        "namespace":empty_to_null(&call.namespace),
        "duration_ms":result.duration_ms,
        "read_only":call.read_only,
        "risk":empty_to_null(&call.risk),
        "status":status,
        "summary":summary,
        "subtitle":subtitle,
        "is_error":is_error,
        "detail_sections":sections,
        "replay_items":[tool_output_item(call, result)],
    }))
}

/// Builds the Responses `function_call_output` (or `custom_tool_call_output`)
/// item that carries a tool result back to the model and into history.
fn tool_output_item(call: &ToolCall, result: &ToolResult) -> Value {
    if !result.name.trim().is_empty() && result.name == "apply_patch" {
        json!({"type":"custom_tool_call_output","call_id":first_non_empty([&result.tool_call_id, &call.id]),"name":result.name,"output":tool_result_transcript_output(result)})
    } else {
        json!({"type":"function_call_output","call_id":first_non_empty([&result.tool_call_id, &call.id]),"output":tool_result_transcript_output(result)})
    }
}

fn enrich_tool_call(call: &mut ToolCall, tools: &[ToolDescriptor]) {
    for tool in tools {
        if tool.name.trim() != call.name.trim()
            && responses_child_tool_name(tool) != call.name.trim()
        {
            continue;
        }
        call.server_id = tool.server_id.clone();
        call.server_label = tool.server_label.clone();
        call.tool_title = first_non_empty([&tool.title, &call.name]);
        call.read_only = tool.read_only;
        call.destructive = tool.destructive;
        call.open_world = tool.open_world;
        call.idempotent = tool.idempotent;
        call.risk = first_non_empty([&tool.risk, &call.risk]);
        if call.namespace.trim().is_empty() {
            call.namespace = tool.namespace.clone();
        }
        return;
    }
}

fn mcp_tool_descriptors(disabled_servers: &[String]) -> Vec<ToolDescriptor> {
    crate::mcp::tool_descriptors()
        .unwrap_or_default()
        .into_iter()
        .filter(|tool| {
            !disabled_servers
                .iter()
                .any(|server| server == tool.server_id.trim())
        })
        .collect()
}

fn call_mcp_tool(call: &ToolCall) -> ToolResult {
    let server_id = if call.server_id.trim().is_empty() {
        namespace_server_display_id(&call.namespace).unwrap_or_default()
    } else {
        call.server_id.clone()
    };
    crate::mcp::call_tool(&server_id, &call.name, call.arguments.clone())
}

fn supports_tools(req: &StreamRequest) -> bool {
    match req.provider.trim() {
        "openai" | "local" | "gemini" => model_supports_tools(&req.model_id).unwrap_or(true),
        _ => false,
    }
}

fn provider_search_enabled(req: &StreamRequest) -> bool {
    match req.provider.as_str() {
        "openai" => true,
        "local" => req.raw_model_id.trim().starts_with("gemini-3"),
        "gemini" => req.raw_model_id.trim().starts_with("gemini-3"),
        _ => false,
    }
}

fn disabled_tool_servers(raw: &str) -> Vec<String> {
    parse_json_array::<String>(raw)
        .into_iter()
        .filter_map(|value| nonempty(value.trim()))
        .collect()
}

fn ensure_attachment_capability(model_id: &str) -> Result<(), String> {
    match model_supports_images(model_id) {
        Some(true) => Ok(()),
        Some(false) => Err(format!(
            "attachments are not supported by model {model_id:?}"
        )),
        None => Err(format!("no capability metadata for model {model_id:?}")),
    }
}

fn model_supports_images(model_id: &str) -> Option<bool> {
    capabilities(model_id).map(|(images, _tools)| images)
}

fn model_supports_tools(model_id: &str) -> Option<bool> {
    capabilities(model_id).map(|(_images, tools)| tools)
}

fn capabilities(model_id: &str) -> Option<(bool, bool)> {
    match model_id.trim() {
        "openai/gpt-5.5"
        | "openai/gpt-5.4-mini"
        | "openai/gpt-5.3-codex"
        | "local/gpt-5.5"
        | "local/gpt-5.4-mini"
        | "local/gpt-5.3-codex"
        | "gemini/gemini-3.1-pro-preview"
        | "gemini/gemini-3.5-flash"
        | "gemini/gemini-3.1-flash-lite" => Some((true, true)),
        _ => None,
    }
}

fn split_model_id(model_id: &str) -> Result<(String, String), String> {
    let trimmed = model_id.trim();
    let Some((provider, model)) = trimmed.split_once('/') else {
        return Err(format!("invalid canonical model id: {model_id:?}"));
    };
    if provider.trim().is_empty() || model.trim().is_empty() {
        return Err(format!("invalid canonical model id: {model_id:?}"));
    }
    Ok((provider.trim().to_owned(), model.trim().to_owned()))
}

fn provider_config(raw: &str, provider: &str) -> ProviderConfig {
    serde_json::from_str::<HashMap<String, ProviderConfig>>(raw.trim())
        .ok()
        .and_then(|mut values| values.remove(provider))
        .unwrap_or_default()
}

fn model_catalog_json(
    provider_config_json: &str,
    provider_order_json: &str,
    configured_models_json: &str,
) -> String {
    let provider_config =
        serde_json::from_str::<HashMap<String, ProviderConfig>>(provider_config_json.trim())
            .unwrap_or_default();
    let provider_order = parse_json_array::<String>(provider_order_json)
        .into_iter()
        .filter_map(|provider| nonempty(provider.trim()))
        .fold(Vec::<String>::new(), |mut out, provider| {
            if !out.contains(&provider) {
                out.push(provider);
            }
            out
        });
    let mut provider_order = if provider_order.is_empty() {
        vec!["local".to_owned(), "openai".to_owned(), "gemini".to_owned()]
    } else {
        provider_order
    };
    for provider in ["local", "openai", "gemini"] {
        if !provider_order.iter().any(|value| value == provider) {
            provider_order.push(provider.to_owned());
        }
    }

    let recommended = recommended_models(configured_models_json);
    let mut providers = providers_from_config(&provider_config, &recommended);
    if let Some(local) = providers.iter_mut().find(|provider| provider.id == "local") {
        local.model_ids =
            live_local_model_ids(&provider_config).unwrap_or_else(|| local.model_ids.clone());
    }

    let provider_values = provider_values(&providers, &provider_order);
    let models = model_values(&recommended, &providers, &provider_order);

    json!({
        "models": models,
        "providers": provider_values,
    })
    .to_string()
}

fn recommended_models(configured_models_json: &str) -> Vec<RecommendedModel> {
    let configured = parse_json_array::<ConfiguredModel>(configured_models_json);
    let mut by_raw = BTreeMap::<String, RecommendedModel>::new();
    for model in configured {
        let Some(raw_id) = nonempty(model.raw_id.trim()) else {
            continue;
        };
        let entry = by_raw
            .entry(raw_id.clone())
            .or_insert_with(|| RecommendedModel {
                raw_id: raw_id.clone(),
                label: first_non_empty([model.label.as_str(), &model_label(&raw_id)]),
                description: model.description.trim().to_owned(),
                recommended: model.recommended.unwrap_or(true),
                capabilities: if model.capabilities.is_empty() {
                    default_capabilities()
                } else {
                    model.capabilities.clone()
                },
            });
        if entry.description.is_empty() && !model.description.trim().is_empty() {
            entry.description = model.description.trim().to_owned();
        }
        if entry.label == model_label(&entry.raw_id) && !model.label.trim().is_empty() {
            entry.label = model.label.trim().to_owned();
        }
    }
    by_raw.into_values().collect()
}

fn providers_from_config(
    provider_config: &HashMap<String, ProviderConfig>,
    recommended: &[RecommendedModel],
) -> Vec<Provider> {
    ["local", "openai", "gemini"]
        .into_iter()
        .map(|id| Provider {
            id: id.to_owned(),
            label: provider_label(id),
            icon: provider_icon(id),
            icon_image: provider_icon_image(id),
            accent_role: provider_accent_role(id),
            enabled: provider_enabled(id, provider_config.get(id)),
            model_ids: provider_model_ids(id, recommended),
        })
        .collect()
}

fn live_local_model_ids(provider_config: &HashMap<String, ProviderConfig>) -> Option<Vec<String>> {
    let config = provider_config.get("local")?;
    let base_url = base_url(&config.base_url, "http://127.0.0.1:8317/v1");
    let url = format!("{}/models", base_url);
    let Ok(mut response) = ureq::get(&url).call() else {
        return None;
    };
    if !response.status().is_success() {
        return None;
    }
    let Ok(payload) = response.body_mut().read_json::<Value>() else {
        return None;
    };
    let entries = payload
        .get("data")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let mut seen = BTreeMap::<String, bool>::new();
    let mut out = Vec::<String>::new();
    for value in entries {
        let entry = serde_json::from_value::<LocalModelEntry>(value).unwrap_or_default();
        let Some(raw_id) = nonempty(entry.id.trim()) else {
            continue;
        };
        if seen.contains_key(&raw_id) {
            continue;
        }
        seen.insert(raw_id.clone(), true);
        out.push(raw_id);
    }
    Some(out)
}

fn provider_values(providers: &[Provider], order: &[String]) -> Vec<Value> {
    let mut providers = providers.to_vec();
    providers.sort_by_key(|provider| provider_rank(order, &provider.id));
    providers
        .into_iter()
        .map(|provider| {
            json!({
                "value": provider.id,
                "label": provider.label,
                "description": if provider.enabled { "Enabled" } else { "Not configured" },
                "enabled": provider.enabled,
                "icon": provider.icon,
                "iconImage": provider.icon_image,
                "accentRole": provider.accent_role,
                "recommended": true,
            })
        })
        .collect()
}

fn model_values(
    models: &[RecommendedModel],
    providers: &[Provider],
    order: &[String],
) -> Vec<Value> {
    let mut out = Vec::new();
    for model in models {
        let mut supporting = providers
            .iter()
            .filter(|provider| provider.model_ids.iter().any(|id| id == &model.raw_id))
            .collect::<Vec<_>>();
        supporting.sort_by_key(|provider| provider_rank(order, &provider.id));
        let selected = supporting
            .iter()
            .copied()
            .find(|provider| provider.enabled)
            .or_else(|| supporting.first().copied());
        let Some(selected) = selected else {
            continue;
        };
        let usable = supporting.iter().any(|provider| provider.enabled);
        let provider_entries = supporting
            .iter()
            .map(|provider| {
                json!({
                    "id": provider.id,
                    "label": provider.label,
                    "enabled": provider.enabled,
                })
            })
            .collect::<Vec<_>>();
        let visual_provider = model_visual_provider(&model.raw_id).unwrap_or(selected.id.as_str());
        out.push(json!({
            "value": model.raw_id,
            "rawId": model.raw_id,
            "canonicalId": format!("{}/{}", selected.id, model.raw_id),
            "label": model.label,
            "description": format!(
                "{} - {}",
                first_non_empty([model.description.as_str(), selected.label.as_str()]),
                if usable {
                    format!("Using {}", selected.label)
                } else {
                    "No enabled provider".to_owned()
                }
            ),
            "recommended": model.recommended,
            "provider": selected.id,
            "providerLabel": selected.label,
            "enabled": selected.enabled,
            "capabilities": model.capabilities,
            "providers": provider_entries,
            "icon": provider_icon(visual_provider),
            "iconImage": provider_icon_image(visual_provider),
            "accentRole": provider_accent_role(visual_provider),
        }));
    }
    out.sort_by(|a, b| {
        let ar = provider_rank(order, a["provider"].as_str().unwrap_or(""));
        let br = provider_rank(order, b["provider"].as_str().unwrap_or(""));
        ar.cmp(&br).then_with(|| {
            a["label"]
                .as_str()
                .unwrap_or("")
                .cmp(b["label"].as_str().unwrap_or(""))
        })
    });
    out
}

fn provider_enabled(provider: &str, config: Option<&ProviderConfig>) -> bool {
    let Some(config) = config else {
        return false;
    };
    if provider == "local" {
        !base_url(&config.base_url, "http://127.0.0.1:8317/v1").is_empty()
    } else {
        !config.api_key.trim().is_empty()
    }
}

fn provider_label(provider: &str) -> String {
    match provider {
        "local" => "Local".to_owned(),
        "openai" => "OpenAI".to_owned(),
        "gemini" => "Gemini".to_owned(),
        _ => provider.to_owned(),
    }
}

fn provider_rank(order: &[String], provider: &str) -> usize {
    order
        .iter()
        .position(|value| value == provider)
        .unwrap_or(1000)
}

fn model_label(raw_id: &str) -> String {
    raw_id
        .split('-')
        .filter(|part| !part.is_empty())
        .map(|part| match part {
            "gpt" => "GPT".to_owned(),
            "tts" => "TTS".to_owned(),
            _ if part.len() <= 3 => part.to_ascii_uppercase(),
            _ => {
                let mut chars = part.chars();
                chars
                    .next()
                    .map(|first| first.to_uppercase().chain(chars).collect())
                    .unwrap_or_default()
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn default_capabilities() -> Map<String, Value> {
    Map::from_iter([
        ("supports_images".to_owned(), json!(true)),
        ("supports_tools".to_owned(), json!(true)),
        ("supports_multimodal".to_owned(), json!(true)),
    ])
}

fn provider_icon(provider: &str) -> &'static str {
    if provider == "local" {
        "\u{f048b}"
    } else {
        ""
    }
}

fn provider_icon_image(provider: &str) -> &'static str {
    match provider {
        "gemini" => "./assets/Google_Gemini_icon_2025.svg.png",
        "openai" => "./assets/OpenAI-white-monoblossom.svg",
        _ => "",
    }
}

fn provider_accent_role(provider: &str) -> &'static str {
    match provider {
        "gemini" => "primary",
        "local" => "secondary",
        _ => "tertiary",
    }
}

fn model_visual_provider(raw_id: &str) -> Option<&'static str> {
    if raw_id.starts_with("gemini-") {
        Some("gemini")
    } else if raw_id.starts_with("gpt-") {
        Some("openai")
    } else {
        None
    }
}

fn provider_model_ids(provider: &str, recommended: &[RecommendedModel]) -> Vec<String> {
    recommended
        .iter()
        .filter(|model| provider_supports_raw_model(provider, &model.raw_id))
        .map(|model| model.raw_id.clone())
        .collect()
}

fn provider_supports_raw_model(provider: &str, raw_id: &str) -> bool {
    match provider {
        "local" => true,
        "openai" => raw_id.starts_with("gpt-"),
        "gemini" => raw_id.starts_with("gemini-"),
        _ => false,
    }
}

fn nonempty(value: &str) -> Option<String> {
    let value = value.trim();
    (!value.is_empty()).then(|| value.to_owned())
}

fn parse_json_array<T: for<'de> Deserialize<'de>>(raw: &str) -> Vec<T> {
    let trimmed = raw.trim();
    if trimmed.is_empty() || trimmed == "[]" || trimmed == "null" {
        return Vec::new();
    }
    serde_json::from_str(trimmed).unwrap_or_default()
}

pub(crate) fn attachment_binary(
    attachment: &Attachment,
) -> Result<Option<(String, String)>, String> {
    if !attachment.b64.trim().is_empty() {
        let mime = if attachment.mime.trim().is_empty() {
            "application/octet-stream"
        } else {
            attachment.mime.trim()
        };
        return Ok(Some((mime.to_owned(), attachment.b64.trim().to_owned())));
    }
    if attachment.path.trim().is_empty() {
        return Ok(None);
    }
    let raw = std::fs::read(attachment.path.trim()).map_err(|error| error.to_string())?;
    if raw.is_empty() {
        return Ok(None);
    }
    let mime = if attachment.mime.trim().is_empty() {
        mime_from_path(attachment.path.trim())
    } else {
        attachment.mime.trim().to_owned()
    };
    Ok(Some((mime, BASE64.encode(raw))))
}

fn mime_from_path(path: &str) -> String {
    mime_guess::from_path(path)
        .first_or_octet_stream()
        .essence_str()
        .to_owned()
}

fn base_url(configured: &str, fallback: &str) -> String {
    let raw = configured.trim();
    if raw.is_empty() {
        fallback.trim_end_matches('/').to_owned()
    } else {
        raw.trim_end_matches('/').to_owned()
    }
}

fn default_schema(schema: &BTreeMap<String, Value>) -> Value {
    if schema.is_empty() {
        json!({"type":"object","properties":{}})
    } else {
        Value::Object(schema.clone().into_iter().collect())
    }
}

fn responses_child_tool_name(tool: &ToolDescriptor) -> String {
    let name = tool.name.trim();
    if !tool.server_id.trim().is_empty() {
        if let Some(child) = name.strip_prefix(&format!("{}__", tool.server_id.trim())) {
            return child.trim().to_owned();
        }
    }
    name.to_owned()
}

fn tool_call_display_name(call: &ToolCall) -> String {
    if let Some(server) = namespace_server_display_id(&call.namespace) {
        format!(
            "{} / {}",
            tool_server_display_name(&server),
            call.name.trim()
        )
    } else {
        tool_display_name(&call.name)
    }
}

fn tool_display_name(name: &str) -> String {
    let clean = name.trim();
    if clean == "todoist_overview" {
        return "Todoist overview".to_owned();
    }
    if let Some((server, tool)) = clean.split_once("__") {
        if !server.trim().is_empty() && !tool.trim().is_empty() {
            return format!(
                "{} / {}",
                tool_server_display_name(server.trim()),
                tool.trim()
            );
        }
    }
    clean.to_owned()
}

fn namespace_server_display_id(namespace: &str) -> Option<String> {
    let clean = namespace.trim();
    clean
        .strip_prefix("mcp__")
        .and_then(|value| value.strip_suffix("__"))
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
}

fn tool_server_display_name(server: &str) -> String {
    server.replace(['_', '-'], " ")
}

fn tool_start_subtitle(call: &ToolCall) -> String {
    match call.name.as_str() {
        "shell_command" | "builtin__shell_command" => first_non_empty([
            string_arg(&call.arguments, "command")
                .as_deref()
                .unwrap_or(""),
            string_arg(&call.arguments, "cmd").as_deref().unwrap_or(""),
        ]),
        "apply_patch" | "builtin__apply_patch" => "applying patch".to_owned(),
        _ => String::new(),
    }
}

fn string_arg(args: &Map<String, Value>, key: &str) -> Option<String> {
    args.get(key).and_then(Value::as_str).map(str::to_owned)
}

fn empty_to_null(value: &str) -> Value {
    if value.trim().is_empty() {
        Value::Null
    } else {
        Value::String(value.to_owned())
    }
}

fn metrics_snapshot(
    model: &str,
    tracker: &MetricTracker,
    result: &StreamResult,
    finished: bool,
    error: &str,
) -> SessionMetrics {
    SessionMetrics {
        model: model.to_owned(),
        chunk_count: tracker.chunk_count,
        prompt_tokens: result.prompt_tokens,
        output_tokens: result.output_tokens,
        ttf_ms: tracker.ttf_ms,
        total_ms: tracker.total_ms(),
        finished,
        error: error.to_owned(),
    }
}

fn store_metrics(metrics: SessionMetrics) {
    *last_metrics().lock().expect("metrics mutex") = metrics;
}

fn sessions() -> &'static Mutex<HashMap<i32, Arc<AtomicBool>>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn last_metrics() -> &'static Mutex<SessionMetrics> {
    LAST_METRICS.get_or_init(|| {
        Mutex::new(SessionMetrics {
            ttf_ms: -1.0,
            ..SessionMetrics::default()
        })
    })
}

fn c_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned()
}

fn callback(cb: TokenCallback, ctx: usize, token: &str, done: i32) {
    let c_token = CString::new(token).unwrap_or_else(|_| CString::new("").expect("empty cstring"));
    unsafe {
        cb(ctx as *mut c_void, c_token.as_ptr(), done);
    }
}

fn into_c_string(value: String) -> *mut c_char {
    CString::new(value)
        .unwrap_or_else(|_| CString::new("{}").expect("literal cstring"))
        .into_raw()
}

fn must_json<T: Serialize>(value: &T) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "{}".to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tool_result_transcript_prefers_structured_payload() {
        let result = ToolResult {
            text: "shown".to_owned(),
            data: Map::from_iter([("answer".to_owned(), json!(42))]),
            ..ToolResult::default()
        };
        let output = tool_result_transcript_output(&result);
        assert!(output.contains("structuredContent"));
        assert!(output.contains("shown"));
    }

    #[test]
    fn attachment_binary_uses_standard_padded_base64() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("sample.bin");
        std::fs::write(&path, [0xff, 0xee, 0xdd, 0xcc, 0xbb]).expect("write sample");
        let attachment = Attachment {
            path: path.to_string_lossy().into_owned(),
            mime: String::new(),
            ..Attachment::default()
        };

        let (mime, encoded) = attachment_binary(&attachment)
            .expect("attachment")
            .expect("payload");
        assert_eq!(mime, "application/octet-stream");
        assert_eq!(encoded, "/+7dzLs=");
    }

    #[test]
    fn attachment_binary_guesses_mime_from_path() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("sample.svg");
        std::fs::write(&path, b"<svg/>").expect("write sample");
        let attachment = Attachment {
            path: path.to_string_lossy().into_owned(),
            mime: String::new(),
            ..Attachment::default()
        };

        let (mime, _) = attachment_binary(&attachment)
            .expect("attachment")
            .expect("payload");
        assert_eq!(mime, "image/svg+xml");
    }

    #[test]
    fn catalog_uses_model_family_icon_when_local_routes_gemini() {
        let models = r#"[{
            "raw_id": "gemini-3.5-flash",
            "label": "Gemini 3.5 Flash",
            "description": "Fast",
            "recommended": true
        }]"#;
        let catalog = model_catalog_json(
            r#"{"local":{"base_url":"http://127.0.0.1:1/v1"}}"#,
            r#"["local","gemini"]"#,
            models,
        );
        let payload: Value = serde_json::from_str(&catalog).expect("catalog json");
        let model = payload["models"][0].as_object().expect("model object");

        assert_eq!(model["provider"], "local");
        assert_eq!(model["canonicalId"], "local/gemini-3.5-flash");
        assert_eq!(
            model["iconImage"],
            "./assets/Google_Gemini_icon_2025.svg.png"
        );
    }
}
