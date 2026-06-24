use std::collections::VecDeque;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use crate::chatstore::ChatStoreMemory;
use crate::mcp::ToolDescriptor;
use futures_util::StreamExt;
use rig_core::agent::MultiTurnStreamItem;
use rig_core::client::CompletionClient;
use rig_core::completion::{GetTokenUsage, ProviderToolDefinition, ToolDefinition, Usage};
use rig_core::message::{ImageDetail, Message, UserContent};
use rig_core::providers::{gemini, openai};
use rig_core::streaming::{StreamedAssistantContent, StreamedUserContent, StreamingPrompt};
use rig_core::tool::server::{ToolServer, ToolServerHandle};
use rig_core::tool::{ToolDyn, ToolError};
use rig_core::OneOrMany;
use serde_json::{json, Map, Value};

use super::{
    attachment_binary, base_url, call_mcp_tool, callback, default_schema, enrich_tool_call,
    first_non_empty, metrics_snapshot, store_metrics, tool_done_event_json, tool_start_event_json,
    Attachment, MetricTracker, StreamArgs, StreamRequest, StreamResult, TokenCallback, ToolCall,
};

const MAX_TOOL_TURNS: usize = 8;
type PendingToolCalls = Arc<Mutex<VecDeque<ToolCall>>>;

struct RigToolSetup {
    handle: ToolServerHandle,
}

pub(super) fn run(args: &StreamArgs, req: StreamRequest) -> Result<(), String> {
    let runtime = crate::utils::build_multi_thread_runtime()?;
    runtime.block_on(run_async(args, req))
}

async fn run_async(args: &StreamArgs, req: StreamRequest) -> Result<(), String> {
    match req.provider.as_str() {
        "openai" | "local" => {
            let base = if req.provider == "local" {
                base_url(&req.config.base_url, "http://127.0.0.1:8317/v1")
            } else {
                base_url(&req.config.base_url, "https://api.openai.com/v1")
            };
            let client = openai::Client::builder()
                .api_key(req.config.api_key.trim())
                .base_url(base)
                .build()
                .map_err(|error| error.to_string())?;
            let builder = configure_base_agent(client.agent(req.raw_model_id.clone()), &req);
            build_and_stream(builder, args, req).await
        }
        "gemini" => {
            let mut builder = gemini::Client::builder().api_key(req.config.api_key.trim());
            if !req.config.base_url.trim().is_empty() {
                builder = builder.base_url(req.config.base_url.trim());
            }
            let client = builder.build().map_err(|error| error.to_string())?;
            let builder = configure_base_agent(client.agent(req.raw_model_id.clone()), &req);
            build_and_stream(builder, args, req).await
        }
        other => Err(format!("unknown provider: {other}")),
    }
}

async fn build_and_stream<M, R>(
    builder: rig_core::agent::AgentBuilder<M>,
    args: &StreamArgs,
    req: StreamRequest,
) -> Result<(), String>
where
    M: rig_core::completion::CompletionModel<StreamingResponse = R> + 'static,
    R: Clone + Unpin + Send + GetTokenUsage + 'static,
{
    let pending_tool_calls = PendingToolCalls::default();
    let tool_setup = rig_tool_setup(args, &req, pending_tool_calls.clone()).await?;
    let agent = match tool_setup.as_ref() {
        Some(setup) => builder.tool_server_handle(setup.handle.clone()).build(),
        None => builder.build(),
    };
    stream_agent(
        agent.stream_prompt(user_message(&req.message, &req.attachments)?),
        args,
        req,
        pending_tool_calls,
    )
    .await
}

fn configure_base_agent<M>(
    builder: rig_core::agent::AgentBuilder<M>,
    req: &StreamRequest,
) -> rig_core::agent::AgentBuilder<M>
where
    M: rig_core::completion::CompletionModel,
{
    let mut builder = if req.system_prompt.trim().is_empty() {
        builder
    } else {
        builder.preamble(req.system_prompt.trim())
    }
    .default_max_turns(MAX_TOOL_TURNS);

    let params = provider_additional_params(req);
    if params != Value::Null {
        builder = builder.additional_params(params);
    }

    if !req.conversation_id.trim().is_empty() {
        builder = builder.memory(ChatStoreMemory::default_store());
    }

    builder
}

async fn rig_tool_setup(
    args: &StreamArgs,
    req: &StreamRequest,
    pending_tool_calls: PendingToolCalls,
) -> Result<Option<RigToolSetup>, String> {
    if req.tools.is_empty() {
        return Ok(None);
    }

    let handle = ToolServer::new().run();
    for descriptor in req.tools.iter().cloned() {
        handle
            .add_tool(QsNativeRigTool {
                descriptor,
                descriptors: req.tools.clone(),
                cb: args.cb,
                ctx: args.ctx,
                pending_tool_calls: pending_tool_calls.clone(),
            })
            .await
            .map_err(|error| error.to_string())?;
    }

    Ok(Some(RigToolSetup { handle }))
}

async fn stream_agent<M, R>(
    request: rig_core::agent::StreamingPromptRequest<M, ()>,
    args: &StreamArgs,
    req: StreamRequest,
    pending_tool_calls: PendingToolCalls,
) -> Result<(), String>
where
    M: rig_core::completion::CompletionModel<StreamingResponse = R> + 'static,
    R: Clone + Unpin + Send + GetTokenUsage + 'static,
{
    let request = if req.conversation_id.trim().is_empty() {
        request
    } else {
        request.conversation(req.conversation_id.trim())
    };
    let mut stream = request.multi_turn(MAX_TOOL_TURNS).await;
    let mut metrics = MetricTracker::new();
    metrics.begin_provider_round();
    let mut combined = StreamResult::default();
    let mut emitted_text = String::new();
    let mut finished = false;

    while let Some(item) = stream.next().await {
        if args.cancelled.load(Ordering::SeqCst) {
            break;
        }
        match item.map_err(|error| error.to_string())? {
            MultiTurnStreamItem::StreamAssistantItem(StreamedAssistantContent::Text(text)) => {
                let delta = assistant_text_delta(&mut emitted_text, &text.text);
                if metrics.observe_token(&delta) {
                    callback(args.cb, args.ctx, &delta, 0);
                }
            }
            MultiTurnStreamItem::StreamAssistantItem(StreamedAssistantContent::Final(_)) => {}
            MultiTurnStreamItem::StreamAssistantItem(StreamedAssistantContent::ToolCall {
                tool_call,
                ..
            }) => {
                let mut call = tool_call_from_rig(&tool_call, &req.tools);
                enrich_tool_call(&mut call, &req.tools);
                callback(args.cb, args.ctx, &tool_start_event_json(&call), 2);
                pending_tool_calls
                    .lock()
                    .expect("pending tool call mutex")
                    .push_back(call);
            }
            MultiTurnStreamItem::StreamAssistantItem(StreamedAssistantContent::ToolCallDelta {
                ..
            }) => {}
            MultiTurnStreamItem::StreamAssistantItem(StreamedAssistantContent::Reasoning(_)) => {}
            MultiTurnStreamItem::StreamAssistantItem(
                StreamedAssistantContent::ReasoningDelta { .. },
            ) => {}
            MultiTurnStreamItem::StreamUserItem(StreamedUserContent::ToolResult { .. }) => {}
            MultiTurnStreamItem::CompletionCall(call) => {
                apply_usage(&mut combined, Some(call.usage));
                metrics.begin_provider_round();
            }
            MultiTurnStreamItem::FinalResponse(response) => {
                let usage = response.usage();
                combined.prompt_tokens = clamp_tokens(usage.input_tokens);
                combined.output_tokens = clamp_tokens(usage.output_tokens);
                finished = true;
            }
            _ => {}
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

fn assistant_text_delta(emitted: &mut String, incoming: &str) -> String {
    if incoming.is_empty() || incoming == emitted {
        return String::new();
    }
    if incoming.starts_with(emitted.as_str()) {
        let delta = incoming[emitted.len()..].to_owned();
        emitted.clear();
        emitted.push_str(incoming);
        return delta;
    }
    emitted.push_str(incoming);
    incoming.to_owned()
}

fn user_message(text: &str, attachments: &[Attachment]) -> Result<Message, String> {
    let mut content = Vec::new();
    if !text.trim().is_empty() {
        content.push(UserContent::text(text));
    }
    for attachment in attachments {
        if !attachment.url.trim().is_empty() {
            content.push(UserContent::image_url(
                attachment.url.trim(),
                None,
                Some(ImageDetail::Auto),
            ));
            continue;
        }
        if let Some((mime, b64)) = attachment_binary(attachment)? {
            if !mime.to_ascii_lowercase().starts_with("image/") {
                return Err("Rig backend currently supports image attachments only".to_owned());
            }
            content.push(UserContent::image_base64(
                b64,
                None,
                Some(ImageDetail::Auto),
            ));
        }
    }
    if content.is_empty() {
        content.push(UserContent::text(""));
    }
    let content = OneOrMany::many(content).map_err(|error| error.to_string())?;
    Ok(Message::User { content })
}

fn tool_call_from_rig(call: &rig_core::message::ToolCall, tools: &[ToolDescriptor]) -> ToolCall {
    let kind = tools
        .iter()
        .find(|tool| tool.name.trim() == call.function.name.trim())
        .map(|tool| tool.kind.as_str())
        .unwrap_or("");
    ToolCall {
        id: first_non_empty([
            call.call_id.as_deref().unwrap_or(""),
            call.id.as_str(),
            call.function.name.as_str(),
        ]),
        name: call.function.name.clone(),
        arguments: value_to_arguments(&call.function.arguments, kind),
        input: string_input(&call.function.arguments),
        ..ToolCall::default()
    }
}

fn take_pending_tool_call(pending: &PendingToolCalls, name: &str) -> Option<ToolCall> {
    let mut pending = pending.lock().expect("pending tool call mutex");
    let index = pending
        .iter()
        .position(|call| call.name.trim() == name.trim())?;
    pending.remove(index)
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
        .map(str::to_owned)
        .unwrap_or_else(|| value.to_string())
}

fn provider_additional_params(req: &StreamRequest) -> Value {
    match req.provider.as_str() {
        "openai" | "local" => json!({
            "tools": [ProviderToolDefinition::new("web_search")],
        }),
        "gemini" if req.raw_model_id.trim().starts_with("gemini-3") => json!({
            "tools": [{"googleSearch": {}}],
        }),
        _ => Value::Null,
    }
}

fn apply_usage(result: &mut StreamResult, usage: Option<Usage>) {
    let Some(usage) = usage else {
        return;
    };
    result.prompt_tokens = clamp_tokens(usage.input_tokens);
    result.output_tokens = result
        .output_tokens
        .saturating_add(clamp_tokens(usage.output_tokens));
}

fn clamp_tokens(value: u64) -> i32 {
    value.try_into().unwrap_or(i32::MAX)
}

struct QsNativeRigTool {
    descriptor: ToolDescriptor,
    descriptors: Vec<ToolDescriptor>,
    cb: TokenCallback,
    ctx: usize,
    pending_tool_calls: PendingToolCalls,
}

impl ToolDyn for QsNativeRigTool {
    fn name(&self) -> String {
        self.descriptor.name.clone()
    }

    fn definition<'a>(
        &'a self,
        _prompt: String,
    ) -> rig_core::wasm_compat::WasmBoxedFuture<'a, ToolDefinition> {
        Box::pin(async move {
            ToolDefinition {
                name: self.descriptor.name.clone(),
                description: self.descriptor.description.clone(),
                parameters: tool_parameters(&self.descriptor),
            }
        })
    }

    fn call<'a>(
        &'a self,
        args: String,
    ) -> rig_core::wasm_compat::WasmBoxedFuture<'a, Result<String, ToolError>> {
        Box::pin(async move {
            let (mut call, start_needed) =
                match take_pending_tool_call(&self.pending_tool_calls, &self.descriptor.name) {
                    Some(call) => (call, false),
                    None => (fallback_tool_call(&self.descriptor, &args), true),
                };
            enrich_tool_call(&mut call, &self.descriptors);
            if start_needed {
                callback(self.cb, self.ctx, &tool_start_event_json(&call), 2);
            }
            let started = Instant::now();
            let mut result = call_mcp_tool(&call);
            if result.duration_ms == 0 {
                result.duration_ms = started.elapsed().as_millis().try_into().unwrap_or(i64::MAX);
            }
            if result.tool_call_id.trim().is_empty() {
                result.tool_call_id = call.id.clone();
            }
            if result.name.trim().is_empty() {
                result.name = call.name.clone();
            }
            callback(self.cb, self.ctx, &tool_done_event_json(&call, &result), 2);
            Ok(crate::mcp::tool_result_transcript_output(&result))
        })
    }
}

fn tool_parameters(descriptor: &ToolDescriptor) -> Value {
    if descriptor.kind.trim() == "freeform" {
        json!({
            "type": "object",
            "properties": {
                "input": {
                    "type": "string",
                    "description": "Raw freeform tool input."
                }
            },
            "required": ["input"]
        })
    } else {
        default_schema(&descriptor.input_schema)
    }
}

fn fallback_tool_call(descriptor: &ToolDescriptor, args: &str) -> ToolCall {
    let value = serde_json::from_str::<Value>(args).unwrap_or(Value::Null);
    ToolCall {
        id: descriptor.name.clone(),
        name: descriptor.name.clone(),
        arguments: value_to_arguments(&value, &descriptor.kind),
        input: string_input(&value),
        ..ToolCall::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn assistant_text_delta_accepts_plain_token_chunks() {
        let mut emitted = String::new();

        assert_eq!(assistant_text_delta(&mut emitted, "hello"), "hello");
        assert_eq!(assistant_text_delta(&mut emitted, " world"), " world");
        assert_eq!(emitted, "hello world");
    }

    #[test]
    fn assistant_text_delta_converts_cumulative_chunks_to_suffixes() {
        let mut emitted = String::new();

        assert_eq!(assistant_text_delta(&mut emitted, "hello"), "hello");
        assert_eq!(assistant_text_delta(&mut emitted, "hello world"), " world");
        assert_eq!(assistant_text_delta(&mut emitted, "hello world!"), "!");
        assert_eq!(emitted, "hello world!");
    }

    #[test]
    fn assistant_text_delta_drops_duplicate_final_text() {
        let mut emitted = String::new();

        assert_eq!(
            assistant_text_delta(&mut emitted, "repeat exactly"),
            "repeat exactly"
        );
        assert_eq!(assistant_text_delta(&mut emitted, "repeat exactly"), "");
        assert_eq!(emitted, "repeat exactly");
    }
}
