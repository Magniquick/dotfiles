//! Streaming chat backend.
//!
//! Talks to the `OpenAI` Responses API (`/v1/responses`) and Google Gemini
//! (`streamGenerateContent`) directly over `ureq`, parsing server-sent events on
//! the calling worker thread. Conversation history is carried in the `OpenAI`
//! Responses "input item" shape as the neutral representation; the Gemini path
//! converts it to `contents` on the fly. The multi-turn tool loop, model-output
//! persistence, and tool dispatch are provider-agnostic.

use std::io::{BufRead, BufReader, Read};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Instant;

use serde_json::{json, Map, Value};

use super::{
    base_url, call_mcp_tool, callback, default_schema, enrich_tool_call, metrics_snapshot,
    must_json, store_metrics, tool_done_event_json, tool_output_item, tool_start_event_json,
    MetricTracker, StreamArgs, StreamRequest, StreamResult, ToolCall,
};
use crate::mcp::ToolDescriptor;

const MAX_TOOL_TURNS: usize = 8;
const BODY_SNIPPET: usize = 800;

pub(super) fn run(args: &StreamArgs, req: &StreamRequest) -> Result<(), String> {
    let input = if req.conversation_id.trim().is_empty() {
        vec![crate::chatstore::user_input_item(
            &req.message,
            &req.attachments,
        )?]
    } else {
        crate::chatstore::load_history_items(req.conversation_id.trim())?
    };

    let gemini = effective_provider(req) == Provider::Gemini;
    drive(args, req, input, gemini)
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Provider {
    OpenAi,
    Gemini,
}

fn effective_provider(req: &StreamRequest) -> Provider {
    // The hosted Google API and the local proxy (which exposes the native Gemini
    // API under /v1beta) both speak the Gemini protocol for gemini-* models.
    if req.provider == "gemini"
        || (req.provider == "local" && req.raw_model_id.trim().starts_with("gemini-"))
    {
        Provider::Gemini
    } else {
        Provider::OpenAi
    }
}

/// One provider round's distilled result, all in the neutral Responses shape.
#[derive(Default)]
struct RoundOutcome {
    /// Raw model-output items (message, `function_call`, reasoning, ...), in order.
    model_items: Vec<Value>,
    /// Tool calls the model requested this round.
    tool_calls: Vec<ToolCall>,
    prompt_tokens: i32,
    output_tokens: i32,
}

/// Runs the multi-turn loop: request → stream → run tools → repeat until the
/// model stops calling tools or the turn budget is exhausted.
fn drive(
    args: &StreamArgs,
    req: &StreamRequest,
    mut input: Vec<Value>,
    gemini: bool,
) -> Result<(), String> {
    let agent = stream_agent();
    let mut metrics = MetricTracker::new();
    let mut combined = StreamResult::default();
    let mut finished = false;

    for _ in 0..MAX_TOOL_TURNS {
        if args.cancelled.load(Ordering::SeqCst) {
            break;
        }
        metrics.begin_provider_round();
        let outcome = if gemini {
            gemini_round(&agent, args, req, &input, &mut metrics)?
        } else {
            openai_round(&agent, args, req, &input, &mut metrics)?
        };

        combined.prompt_tokens = outcome.prompt_tokens;
        combined.output_tokens = combined.output_tokens.saturating_add(outcome.output_tokens);

        if !outcome.model_items.is_empty() {
            emit_model_items(args, &outcome.model_items);
            input.extend(outcome.model_items.iter().cloned());
        }

        if outcome.tool_calls.is_empty() {
            finished = true;
            break;
        }

        for call in &outcome.tool_calls {
            if args.cancelled.load(Ordering::SeqCst) {
                break;
            }
            let result = run_tool(args, call);
            input.push(tool_output_item(call, &result));
        }
    }

    store_metrics(metrics_snapshot(
        &args.model_id,
        &metrics,
        &combined,
        finished,
        "",
    ));
    if finished {
        callback(args.cb, args.ctx, "", 1);
    }
    Ok(())
}

/// Emits `tool_start`, dispatches to the local MCP catalog, emits `tool_done`.
fn run_tool(args: &StreamArgs, call: &ToolCall) -> crate::mcp::ToolResult {
    callback(args.cb, args.ctx, &tool_start_event_json(call), 2);
    let started = Instant::now();
    let mut result = call_mcp_tool(call);
    if result.duration_ms == 0 {
        result.duration_ms = started.elapsed().as_millis().try_into().unwrap_or(i64::MAX);
    }
    if result.tool_call_id.trim().is_empty() {
        result.tool_call_id.clone_from(&call.id);
    }
    if result.name.trim().is_empty() {
        result.name.clone_from(&call.name);
    }
    callback(args.cb, args.ctx, &tool_done_event_json(call, &result), 2);
    result
}

/// Publishes model-output items so the UI layer can persist them as
/// `model_output` response items (`function_call`, message, reasoning, ...).
fn emit_model_items(args: &StreamArgs, items: &[Value]) {
    if items.is_empty() {
        return;
    }
    let event = json!({ "kind": "raw_response_items", "items": items });
    callback(args.cb, args.ctx, &must_json(&event), 2);
}

// --- OpenAI Responses -------------------------------------------------------

fn openai_round(
    agent: &ureq::Agent,
    args: &StreamArgs,
    req: &StreamRequest,
    input: &[Value],
    metrics: &mut MetricTracker,
) -> Result<RoundOutcome, String> {
    let base = if req.provider == "local" {
        base_url(&req.config.base_url, "http://127.0.0.1:8317/v1")
    } else {
        base_url(&req.config.base_url, "https://api.openai.com/v1")
    };
    let url = format!("{base}/responses");

    let sanitized: Vec<Value> = input.iter().filter_map(sanitize_input_item).collect();
    let mut body = Map::new();
    body.insert("model".into(), json!(req.raw_model_id));
    body.insert("input".into(), json!(sanitized));
    body.insert("stream".into(), json!(true));
    body.insert("store".into(), json!(false));
    if !req.system_prompt.trim().is_empty() {
        body.insert("instructions".into(), json!(req.system_prompt.trim()));
    }
    let tools = openai_tools(req);
    if !tools.is_empty() {
        body.insert("tools".into(), json!(tools));
    }

    let mut request = agent.post(&url).header("Content-Type", "application/json");
    let key = req.config.api_key.trim();
    if !key.is_empty() {
        request = request.header("Authorization", &format!("Bearer {key}"));
    }
    let mut response = request
        .send_json(Value::Object(body))
        .map_err(|error| error.to_string())?;
    if !response.status().is_success() {
        return Err(http_error(
            "openai",
            response.status().as_u16(),
            &mut response,
        ));
    }

    let mut outcome = RoundOutcome::default();
    read_sse(response.body_mut().as_reader(), &args.cancelled, |event| {
        openai_event(&event, args, req, metrics, &mut outcome);
    })?;
    Ok(outcome)
}

fn openai_event(
    event: &Value,
    args: &StreamArgs,
    req: &StreamRequest,
    metrics: &mut MetricTracker,
    outcome: &mut RoundOutcome,
) {
    match event.get("type").and_then(Value::as_str).unwrap_or("") {
        "response.output_text.delta" => {
            if let Some(delta) = event.get("delta").and_then(Value::as_str) {
                if metrics.observe_token(delta) {
                    callback(args.cb, args.ctx, delta, 0);
                }
            }
        }
        "response.output_item.done" => {
            let Some(item) = event.get("item") else {
                return;
            };
            if item.get("type").and_then(Value::as_str) == Some("function_call") {
                outcome.tool_calls.push(openai_tool_call(item, &req.tools));
            }
            outcome.model_items.push(item.clone());
        }
        "response.completed" => {
            if let Some(usage) = event.pointer("/response/usage") {
                outcome.prompt_tokens = usage_i32(usage, "input_tokens");
                outcome.output_tokens = usage_i32(usage, "output_tokens");
            }
        }
        #[expect(
            clippy::match_same_arms,
            reason = "explicit arm documents that response.failed is a known event deliberately \
                      handled by the empty-stream + non-finished-metrics path, not an oversight"
        )]
        "response.failed" => {
            // Surfaced by the empty stream + non-finished metrics; nothing to emit here.
        }
        _ => {}
    }
}

fn openai_tool_call(item: &Value, tools: &[ToolDescriptor]) -> ToolCall {
    let name = item.get("name").and_then(Value::as_str).unwrap_or("");
    let call_id = item.get("call_id").and_then(Value::as_str).unwrap_or("");
    let raw_args = item.get("arguments").and_then(Value::as_str).unwrap_or("");
    let parsed = serde_json::from_str::<Value>(raw_args).unwrap_or(Value::Null);
    let kind = tool_kind(tools, name);
    let mut call = ToolCall {
        id: first_id([call_id, name]),
        name: name.to_owned(),
        arguments: value_to_arguments(&parsed, kind),
        input: string_input(&parsed),
        ..ToolCall::default()
    };
    enrich_tool_call(&mut call, tools);
    call
}

fn openai_tools(req: &StreamRequest) -> Vec<Value> {
    let mut tools: Vec<Value> = req
        .tools
        .iter()
        .map(|tool| {
            json!({
                "type": "function",
                "name": tool.name,
                "description": tool.description,
                "parameters": tool_parameters(tool),
                "strict": false,
            })
        })
        .collect();
    if req.provider_search_enabled {
        tools.push(json!({ "type": "web_search" }));
    }
    tools
}

/// Strips non-standard/echo-unsafe fields so historical items replay cleanly.
///
/// Server-generated item `id`s (`msg_…`, `fc_…`) are dropped because replaying
/// them with `store: false` can trip "item not found"; call/output pairing rides
/// on `call_id`, which is preserved. `namespace` is an internal annotation the
/// APIs reject.
fn sanitize_input_item(item: &Value) -> Option<Value> {
    let object = item.as_object()?;
    // Reasoning items cannot be replayed without their encrypted payload.
    if object.get("type").and_then(Value::as_str) == Some("reasoning") {
        return None;
    }
    let mut out = object.clone();
    out.remove("id");
    out.remove("namespace");
    Some(Value::Object(out))
}

// --- Gemini -----------------------------------------------------------------

fn gemini_round(
    agent: &ureq::Agent,
    args: &StreamArgs,
    req: &StreamRequest,
    input: &[Value],
    metrics: &mut MetricTracker,
) -> Result<RoundOutcome, String> {
    let url = format!(
        "{}/models/{}:streamGenerateContent?alt=sse",
        gemini_base(req),
        req.raw_model_id.trim()
    );

    let mut body = Map::new();
    body.insert("contents".into(), json!(gemini_contents(input)));
    if !req.system_prompt.trim().is_empty() {
        body.insert(
            "systemInstruction".into(),
            json!({ "parts": [{ "text": req.system_prompt.trim() }] }),
        );
    }
    let tools = gemini_tools(req);
    if !tools.is_empty() {
        body.insert("tools".into(), json!(tools));
    }

    let mut request = agent.post(&url).header("Content-Type", "application/json");
    let key = req.config.api_key.trim();
    if !key.is_empty() {
        request = request.header("x-goog-api-key", key);
    }
    let mut response = request
        .send_json(Value::Object(body))
        .map_err(|error| error.to_string())?;
    if !response.status().is_success() {
        return Err(http_error(
            "gemini",
            response.status().as_u16(),
            &mut response,
        ));
    }

    let mut outcome = RoundOutcome::default();
    let mut text = String::new();
    let mut calls: Vec<(String, Value)> = Vec::new();
    read_sse(response.body_mut().as_reader(), &args.cancelled, |event| {
        gemini_event(&event, args, metrics, &mut text, &mut calls, &mut outcome);
    })?;

    // Reassemble the round into neutral Responses items.
    if !text.is_empty() {
        outcome.model_items.push(json!({
            "type": "message",
            "role": "assistant",
            "content": [{ "type": "output_text", "text": text }],
        }));
    }
    for (index, (name, arguments)) in calls.into_iter().enumerate() {
        let call_id = format!("call_{}_{index}", sanitize_id(&name));
        outcome.model_items.push(json!({
            "type": "function_call",
            "call_id": call_id,
            "name": name,
            "arguments": arguments.to_string(),
        }));
        let kind = tool_kind(&req.tools, &name);
        let mut call = ToolCall {
            id: call_id,
            name: name.clone(),
            arguments: value_to_arguments(&arguments, kind),
            input: string_input(&arguments),
            ..ToolCall::default()
        };
        enrich_tool_call(&mut call, &req.tools);
        outcome.tool_calls.push(call);
    }
    Ok(outcome)
}

fn gemini_event(
    event: &Value,
    args: &StreamArgs,
    metrics: &mut MetricTracker,
    text: &mut String,
    calls: &mut Vec<(String, Value)>,
    outcome: &mut RoundOutcome,
) {
    if let Some(parts) = event
        .pointer("/candidates/0/content/parts")
        .and_then(Value::as_array)
    {
        for part in parts {
            if let Some(delta) = part.get("text").and_then(Value::as_str) {
                text.push_str(delta);
                if metrics.observe_token(delta) {
                    callback(args.cb, args.ctx, delta, 0);
                }
            } else if let Some(call) = part.get("functionCall") {
                let name = call
                    .get("name")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_owned();
                let arguments = call.get("args").cloned().unwrap_or_else(|| json!({}));
                calls.push((name, arguments));
            }
        }
    }
    if let Some(usage) = event.get("usageMetadata") {
        outcome.prompt_tokens = usage_i32(usage, "promptTokenCount");
        outcome.output_tokens = usage_i32(usage, "candidatesTokenCount");
    }
}

fn gemini_base(req: &StreamRequest) -> String {
    let configured = req.config.base_url.trim();
    if req.provider == "local" {
        // The local proxy exposes the native Gemini API under /v1beta, alongside
        // its OpenAI-compatible /v1 surface. Swap the OpenAI version segment.
        let root = base_url(configured, "http://127.0.0.1:8317/v1");
        let root = root.trim_end_matches('/');
        let root = root.strip_suffix("/v1").unwrap_or(root);
        return format!("{root}/v1beta");
    }
    if configured.is_empty() {
        "https://generativelanguage.googleapis.com/v1beta".to_owned()
    } else {
        base_url(configured, "")
    }
}

/// Converts neutral Responses input items into Gemini `contents`, merging
/// consecutive same-role turns and pairing tool outputs back to their call name.
fn gemini_contents(input: &[Value]) -> Vec<Value> {
    let names = call_id_names(input);
    let mut contents: Vec<Value> = Vec::new();
    for item in input {
        let Some((role, parts)) = gemini_item(item, &names) else {
            continue;
        };
        if parts.is_empty() {
            continue;
        }
        match contents.last_mut() {
            Some(last) if last.get("role").and_then(Value::as_str) == Some(role) => {
                if let Some(existing) = last.get_mut("parts").and_then(Value::as_array_mut) {
                    existing.extend(parts);
                }
            }
            _ => contents.push(json!({ "role": role, "parts": parts })),
        }
    }
    contents
}

fn gemini_item(item: &Value, names: &Map<String, Value>) -> Option<(&'static str, Vec<Value>)> {
    match item.get("type").and_then(Value::as_str).unwrap_or("") {
        "message" => {
            let role = item.get("role").and_then(Value::as_str).unwrap_or("user");
            let content = item.get("content").and_then(Value::as_array)?;
            if role == "assistant" {
                let text = content
                    .iter()
                    .filter_map(|part| part.get("text").and_then(Value::as_str))
                    .collect::<String>();
                (!text.is_empty()).then(|| ("model", vec![json!({ "text": text })]))
            } else {
                let parts = content
                    .iter()
                    .filter_map(gemini_user_part)
                    .collect::<Vec<_>>();
                Some(("user", parts))
            }
        }
        "function_call" => {
            let name = item.get("name").and_then(Value::as_str).unwrap_or("");
            let arguments = item
                .get("arguments")
                .and_then(Value::as_str)
                .and_then(|raw| serde_json::from_str::<Value>(raw).ok())
                .unwrap_or_else(|| json!({}));
            Some((
                "model",
                vec![json!({ "functionCall": { "name": name, "args": arguments } })],
            ))
        }
        "function_call_output" => {
            let call_id = item.get("call_id").and_then(Value::as_str).unwrap_or("");
            let name = names
                .get(call_id)
                .and_then(Value::as_str)
                .unwrap_or(call_id);
            let output = item.get("output").and_then(Value::as_str).unwrap_or("");
            Some((
                "user",
                vec![json!({
                    "functionResponse": {
                        "name": name,
                        "response": gemini_tool_response(output),
                    }
                })],
            ))
        }
        _ => None,
    }
}

fn gemini_user_part(part: &Value) -> Option<Value> {
    match part.get("type").and_then(Value::as_str).unwrap_or("") {
        "input_text" | "output_text" => part
            .get("text")
            .and_then(Value::as_str)
            .map(|text| json!({ "text": text })),
        "input_image" => {
            let url = part.get("image_url").and_then(Value::as_str)?;
            let (mime, data) = data_uri_parts(url)?;
            Some(json!({ "inlineData": { "mimeType": mime, "data": data } }))
        }
        _ => None,
    }
}

fn gemini_tool_response(output: &str) -> Value {
    match serde_json::from_str::<Value>(output) {
        Ok(value @ Value::Object(_)) => value,
        Ok(value) => json!({ "result": value }),
        Err(_) => json!({ "output": output }),
    }
}

fn gemini_tools(req: &StreamRequest) -> Vec<Value> {
    let mut tools = Vec::new();
    if !req.tools.is_empty() {
        let declarations = req
            .tools
            .iter()
            .map(|tool| {
                json!({
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool_parameters(tool),
                })
            })
            .collect::<Vec<_>>();
        tools.push(json!({ "functionDeclarations": declarations }));
    }
    if req.provider_search_enabled {
        tools.push(json!({ "googleSearch": {} }));
    }
    tools
}

/// Maps each `call_id` to the tool name from the `function_call` that produced it.
fn call_id_names(input: &[Value]) -> Map<String, Value> {
    let mut names = Map::new();
    for item in input {
        if item.get("type").and_then(Value::as_str) == Some("function_call") {
            if let (Some(id), Some(name)) = (
                item.get("call_id").and_then(Value::as_str),
                item.get("name").cloned(),
            ) {
                names.insert(id.to_owned(), name);
            }
        }
    }
    names
}

// --- shared helpers ---------------------------------------------------------

/// Reads an SSE stream line by line, invoking `on_event` for each `data:` JSON
/// payload. `on_event` returns `true` to stop early. Cancellation is polled
/// between lines.
fn read_sse<F>(reader: impl Read, cancelled: &AtomicBool, mut on_event: F) -> Result<(), String>
where
    F: FnMut(Value),
{
    let mut buffered = BufReader::new(reader);
    let mut line = String::new();
    loop {
        if cancelled.load(Ordering::SeqCst) {
            return Ok(());
        }
        line.clear();
        let read = buffered
            .read_line(&mut line)
            .map_err(|error| error.to_string())?;
        if read == 0 {
            return Ok(());
        }
        let Some(data) = line.trim_end().strip_prefix("data:") else {
            continue;
        };
        let data = data.trim();
        if data.is_empty() || data == "[DONE]" {
            continue;
        }
        if let Ok(value) = serde_json::from_str::<Value>(data) {
            on_event(value);
        }
    }
}

fn stream_agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .http_status_as_error(false)
        .build()
        .new_agent()
}

fn http_error(
    provider: &str,
    status: u16,
    response: &mut ureq::http::Response<ureq::Body>,
) -> String {
    let body = response.body_mut().read_to_string().unwrap_or_default();
    format!("{provider} HTTP {status}: {}", snippet(&body))
}

fn snippet(body: &str) -> String {
    body.trim().chars().take(BODY_SNIPPET).collect()
}

fn tool_kind<'a>(tools: &'a [ToolDescriptor], name: &str) -> &'a str {
    tools
        .iter()
        .find(|tool| tool.name.trim() == name.trim())
        .map_or("", |tool| tool.kind.as_str())
}

fn tool_parameters(descriptor: &ToolDescriptor) -> Value {
    if descriptor.kind.trim() == "freeform" {
        json!({
            "type": "object",
            "properties": {
                "input": { "type": "string", "description": "Raw freeform tool input." }
            },
            "required": ["input"]
        })
    } else {
        default_schema(&descriptor.input_schema)
    }
}

fn value_to_arguments(value: &Value, kind: &str) -> Map<String, Value> {
    if let Some(map) = value.as_object() {
        return map.clone();
    }
    if kind.trim() == "freeform" {
        return Map::from_iter([("input".to_owned(), Value::String(string_input(value)))]);
    }
    Map::new()
}

fn string_input(value: &Value) -> String {
    value
        .as_str()
        .map_or_else(|| value.to_string(), str::to_owned)
}

fn first_id<const N: usize>(candidates: [&str; N]) -> String {
    candidates
        .into_iter()
        .map(str::trim)
        .find(|value| !value.is_empty())
        .unwrap_or("")
        .to_owned()
}

fn sanitize_id(name: &str) -> String {
    name.chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '_' })
        .collect()
}

fn usage_i32(usage: &Value, key: &str) -> i32 {
    usage
        .get(key)
        .and_then(Value::as_u64)
        .map_or(0, |value| value.try_into().unwrap_or(i32::MAX))
}

fn data_uri_parts(url: &str) -> Option<(String, String)> {
    let rest = url.strip_prefix("data:")?;
    let (mime, data) = rest.split_once(',')?;
    let mime = mime.strip_suffix(";base64").unwrap_or(mime);
    Some((mime.to_owned(), data.to_owned()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_drops_reasoning_and_namespace() {
        assert!(sanitize_input_item(&json!({ "type": "reasoning", "id": "rs_1" })).is_none());
        let call = sanitize_input_item(&json!({
            "type": "function_call",
            "id": "fc_1",
            "call_id": "call_1",
            "name": "x",
            "arguments": "{}",
            "namespace": "mcp__email__"
        }))
        .expect("kept");
        assert!(call.get("id").is_none());
        assert!(call.get("namespace").is_none());
        assert_eq!(call["call_id"], "call_1");
    }

    #[test]
    fn gemini_contents_pairs_tool_output_to_call_name() {
        let input = vec![
            json!({ "type": "message", "role": "user", "content": [{ "type": "input_text", "text": "hi" }] }),
            json!({ "type": "function_call", "call_id": "call_1", "name": "weather", "arguments": "{\"city\":\"NYC\"}" }),
            json!({ "type": "function_call_output", "call_id": "call_1", "output": "{\"temp\":21}" }),
        ];
        let contents = gemini_contents(&input);
        assert_eq!(contents[0]["role"], "user");
        assert_eq!(contents[0]["parts"][0]["text"], "hi");
        assert_eq!(contents[1]["role"], "model");
        assert_eq!(contents[1]["parts"][0]["functionCall"]["name"], "weather");
        assert_eq!(contents[2]["role"], "user");
        let response = &contents[2]["parts"][0]["functionResponse"];
        assert_eq!(response["name"], "weather");
        assert_eq!(response["response"]["temp"], 21);
    }

    #[test]
    fn data_uri_parts_splits_mime_and_payload() {
        let (mime, data) = data_uri_parts("data:image/png;base64,AAAB").expect("parsed");
        assert_eq!(mime, "image/png");
        assert_eq!(data, "AAAB");
    }

    // End-to-end streaming against the local proxy's native Gemini endpoint.
    // Ignored by default; run with `--ignored` when the local server is up:
    //   cargo test ... -p qsnative_rust --release ai::stream::tests::live -- --ignored --nocapture
    #[test]
    #[ignore = "hits the live local Gemini proxy at 127.0.0.1:8317"]
    fn live_local_gemini_streams() {
        use std::ffi::{c_void, CStr};
        use std::os::raw::{c_char, c_int};
        use std::sync::atomic::AtomicBool;
        use std::sync::Arc;

        unsafe extern "C" fn collect(ctx: *mut c_void, token: *const c_char, done: c_int) {
            let events = unsafe { &mut *ctx.cast::<Vec<(String, i32)>>() };
            let text = if token.is_null() {
                String::new()
            } else {
                unsafe { CStr::from_ptr(token) }
                    .to_string_lossy()
                    .into_owned()
            };
            events.push((text, done));
        }

        let prompt = "Say hello in exactly three words.";
        let mut events: Vec<(String, i32)> = Vec::new();
        let args = crate::ai::StreamArgs {
            model_id: "local/gemini-pro-latest".to_owned(),
            provider_config: std::collections::HashMap::new(),
            system_prompt: String::new(),
            conversation_id: String::new(),
            message: prompt.to_owned(),
            attachments_json: String::new(),
            disabled_tool_servers_json: String::new(),
            ctx: &raw mut events as usize,
            cb: collect,
            cancelled: Arc::new(AtomicBool::new(false)),
            id: 0,
        };
        let req = crate::ai::StreamRequest {
            model_id: "local/gemini-pro-latest".to_owned(),
            raw_model_id: "gemini-pro-latest".to_owned(),
            provider: "local".to_owned(),
            config: crate::ai::ProviderConfig {
                base_url: "http://127.0.0.1:8317/v1".to_owned(),
                ..Default::default()
            },
            message: prompt.to_owned(),
            ..Default::default()
        };

        run(&args, &req).expect("stream run");

        let text: String = events
            .iter()
            .filter(|(_, done)| *done == 0)
            .map(|(token, _)| token.as_str())
            .collect();
        let finished = events.iter().any(|(_, done)| *done == 1);
        eprintln!("streamed {} chunks -> {text:?}", events.len());
        assert!(finished, "expected terminal done=1; events={events:?}");
        assert!(!text.trim().is_empty(), "expected non-empty streamed text");
    }
}
