use libc::c_char;
use rusqlite::{params, Connection, OptionalExtension, Transaction};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::env;
use std::ffi::{CStr, CString};
use std::fs;
use std::path::{Path, PathBuf};
use std::ptr;
use uuid::Uuid;

use crate::config_resolver::DEFAULT_MODEL as DEFAULT_MODEL_ID;
const SCHEMA_SQL: &str = r"
CREATE TABLE IF NOT EXISTS conversations (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL DEFAULT '',
  model_id TEXT NOT NULL,
  provider_id TEXT NOT NULL DEFAULT '',
  mood_id TEXT NOT NULL DEFAULT '',
  mood_name TEXT NOT NULL DEFAULT '',
  system_prompt TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'closed', 'archived', 'deleted')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  closed_at TEXT,
  deleted_at TEXT
);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  ordinal INTEGER NOT NULL,
  sender TEXT NOT NULL CHECK (sender IN ('user', 'assistant', 'tool')),
  kind TEXT NOT NULL CHECK (kind IN ('chat', 'info', 'tool')),
  status TEXT NOT NULL DEFAULT 'complete'
    CHECK (status IN ('streaming', 'complete', 'error', 'deleted')),
  body TEXT NOT NULL DEFAULT '',
  metrics BLOB NOT NULL DEFAULT (jsonb('{}')) CHECK (json_valid(metrics, 8)),
  extra BLOB NOT NULL DEFAULT (jsonb('{}')) CHECK (json_valid(extra, 8)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT,
  completed_at TEXT,
  deleted_at TEXT,
  UNIQUE(conversation_id, ordinal),
  CHECK ((kind = 'tool') = (sender = 'tool'))
);

CREATE TABLE IF NOT EXISTS tool_calls (
  id TEXT PRIMARY KEY,
  message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  tool_call_id TEXT NOT NULL,
  tool_name TEXT NOT NULL,
  phase TEXT NOT NULL CHECK (phase IN ('tool_start', 'tool_done', 'tool_error')),
  status TEXT NOT NULL CHECK (status IN ('running', 'success', 'error')),
  is_error INTEGER NOT NULL DEFAULT 0 CHECK (is_error IN (0, 1)),
  summary TEXT NOT NULL DEFAULT '',
  subtitle TEXT NOT NULL DEFAULT '',
  payload BLOB NOT NULL DEFAULT (jsonb('{}')) CHECK (json_valid(payload, 8)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT,
  UNIQUE(message_id, tool_call_id)
);

CREATE TABLE IF NOT EXISTS response_items (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  turn_id TEXT NOT NULL,
  turn_ordinal INTEGER NOT NULL,
  item_ordinal INTEGER NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('model_output', 'tool_output')),
  item_type TEXT NOT NULL DEFAULT '',
  call_id TEXT NOT NULL DEFAULT '',
  raw BLOB NOT NULL CHECK (json_valid(raw, 8)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  UNIQUE(conversation_id, turn_id, item_ordinal)
);

CREATE INDEX IF NOT EXISTS idx_conversations_status_updated
ON conversations(status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_conversation_ordinal
ON messages(conversation_id, ordinal);

CREATE INDEX IF NOT EXISTS idx_messages_status
ON messages(status);

CREATE INDEX IF NOT EXISTS idx_tool_calls_message
ON tool_calls(message_id);

CREATE INDEX IF NOT EXISTS idx_tool_calls_name_status
ON tool_calls(tool_name, status);

CREATE INDEX IF NOT EXISTS idx_response_items_turn
ON response_items(conversation_id, turn_ordinal, item_ordinal);

CREATE INDEX IF NOT EXISTS idx_response_items_call
ON response_items(conversation_id, call_id);
";

#[derive(Default)]
struct OpenConversationOptions {
    model_id: String,
    provider_id: String,
    mood_id: String,
    mood_name: String,
    system_prompt: String,
}

#[derive(Default, Serialize)]
struct ApiResult {
    ok: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    error: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    conversation: Option<Conversation>,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    conversations: Vec<ConversationSummary>,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    messages: Vec<Message>,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    response_items: Vec<ResponseItem>,
}

#[derive(Clone, Default, Serialize)]
struct Conversation {
    id: String,
    title: String,
    model_id: String,
    provider_id: String,
    mood_id: String,
    mood_name: String,
    system_prompt: String,
    status: String,
    created_at: String,
    updated_at: String,
}

#[derive(Default, Serialize)]
struct ConversationSummary {
    id: String,
    title: String,
    model_id: String,
    provider_id: String,
    status: String,
    created_at: String,
    updated_at: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    closed_at: String,
    message_count: i64,
    preview: String,
}

#[derive(Default, Deserialize, Serialize)]
struct Message {
    id: String,
    conversation_id: String,
    ordinal: i64,
    sender: String,
    kind: String,
    status: String,
    body: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    metrics_json: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    extra_json: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    created_at: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    updated_at: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    completed_at: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    deleted_at: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    tool_calls: Vec<ToolCall>,
}

#[derive(Default, Deserialize, Serialize)]
struct ToolCall {
    id: String,
    message_id: String,
    #[serde(rename = "tool_call_id")]
    call_id: String,
    tool_name: String,
    phase: String,
    status: String,
    is_error: bool,
    summary: String,
    subtitle: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    payload_json: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    created_at: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    updated_at: String,
}

#[derive(Clone, Default, Deserialize, Serialize)]
struct ResponseItem {
    #[serde(default)]
    id: String,
    #[serde(default)]
    conversation_id: String,
    #[serde(default)]
    turn_id: String,
    #[serde(default)]
    turn_ordinal: i64,
    #[serde(default)]
    item_ordinal: i64,
    #[serde(default)]
    source: String,
    #[serde(default)]
    item_type: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    call_id: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    raw_json: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    created_at: String,
}

struct Store {
    conn: Connection,
}

/// Loads a conversation's history as an `OpenAI` Responses `input` array.
///
/// Opens the default on-disk store and shapes the stored messages plus persisted
/// raw response items into the item sequence expected by the Responses API. The
/// returned items are also the neutral form the Gemini path converts from.
pub(crate) fn load_history_items(conversation_id: &str) -> Result<Vec<Value>, String> {
    let store = Store::open("").map_err(|error| error.to_string())?;
    store
        .history_items(conversation_id)
        .map_err(|error| error.to_string())?
}

#[no_mangle]
/// Restores the latest active conversation for a model.
///
/// # Safety
///
/// Pointer arguments must be null or valid NUL-terminated strings for the
/// duration of this call. The returned pointer must be released with
/// `QsNative_Free`.
pub unsafe extern "C" fn QsNative_AiHistory_Restore(
    model_id: *const c_char,
    provider_id: *const c_char,
    system_prompt: *const c_char,
) -> *mut c_char {
    let opts = unsafe { open_options(model_id, provider_id, system_prompt) };
    alloc_c_string(&with_store("", |store| {
        match store.restore_conversation(&opts)? {
            Some(conv) => {
                let messages = store.list_messages(&conv.id)?;
                Ok(encode(&ApiResult {
                    ok: true,
                    conversation: Some(conv),
                    messages,
                    ..Default::default()
                }))
            }
            None => Ok(encode_ok()),
        }
    }))
}

#[no_mangle]
/// Creates a fresh active conversation.
///
/// # Safety
///
/// Pointer arguments must be null or valid NUL-terminated strings for the
/// duration of this call. The returned pointer must be released with
/// `QsNative_Free`.
pub unsafe extern "C" fn QsNative_AiHistory_Create(
    model_id: *const c_char,
    provider_id: *const c_char,
    system_prompt: *const c_char,
) -> *mut c_char {
    let opts = unsafe { open_options(model_id, provider_id, system_prompt) };
    alloc_c_string(&with_store("", |store| {
        let conv = store.create_conversation(&opts)?;
        Ok(encode(&ApiResult {
            ok: true,
            conversation: Some(conv),
            ..Default::default()
        }))
    }))
}

#[no_mangle]
/// Closes an active conversation.
///
/// # Safety
///
/// `conversation_id` must be null or a valid NUL-terminated string for the
/// duration of this call. The returned pointer must be released with
/// `QsNative_Free`.
pub unsafe extern "C" fn QsNative_AiHistory_Close(conversation_id: *const c_char) -> *mut c_char {
    let conversation_id = unsafe { c_arg(conversation_id) };
    alloc_c_string(&with_store("", |store| {
        store.close_conversation(&conversation_id)?;
        Ok(encode_ok())
    }))
}

#[no_mangle]
/// Resumes a closed conversation and returns its messages.
///
/// # Safety
///
/// Pointer arguments must be null or valid NUL-terminated strings for the
/// duration of this call. The returned pointer must be released with
/// `QsNative_Free`.
pub unsafe extern "C" fn QsNative_AiHistory_Resume(
    model_id: *const c_char,
    provider_id: *const c_char,
    system_prompt: *const c_char,
    current_conversation_id: *const c_char,
    target_conversation_id: *const c_char,
) -> *mut c_char {
    let opts = unsafe { open_options(model_id, provider_id, system_prompt) };
    let current_conversation_id = unsafe { c_arg(current_conversation_id) };
    let target_conversation_id = unsafe { c_arg(target_conversation_id) };
    alloc_c_string(&with_store("", |store| {
        let (conv, messages) =
            store.resume_conversation(&opts, &current_conversation_id, &target_conversation_id)?;
        Ok(encode(&ApiResult {
            ok: true,
            conversation: Some(conv),
            messages,
            ..Default::default()
        }))
    }))
}

#[no_mangle]
/// Lists closed conversations available for resume.
///
/// # Safety
///
/// Pointer arguments must be null or valid NUL-terminated strings for the
/// duration of this call. The returned pointer must be released with
/// `QsNative_Free`.
pub unsafe extern "C" fn QsNative_AiHistory_ListResume(
    model_id: *const c_char,
    provider_id: *const c_char,
    current_conversation_id: *const c_char,
    query: *const c_char,
    limit: i32,
) -> *mut c_char {
    let opts = unsafe { open_options(model_id, provider_id, ptr::null()) };
    let current_conversation_id = unsafe { c_arg(current_conversation_id) };
    let query = unsafe { c_arg(query) };
    alloc_c_string(&with_store("", |store| {
        let conversations = store.list_closed_conversations(
            &opts,
            &current_conversation_id,
            &query,
            i64::from(limit),
        )?;
        Ok(encode(&ApiResult {
            ok: true,
            conversations,
            ..Default::default()
        }))
    }))
}

#[no_mangle]
/// Inserts or updates a message row from a compact JSON object.
///
/// # Safety
///
/// `message_json` must be null or a valid NUL-terminated string for the
/// duration of this call. The returned pointer must be released with
/// `QsNative_Free`.
pub unsafe extern "C" fn QsNative_AiHistory_UpsertMessage(
    message_json: *const c_char,
) -> *mut c_char {
    let raw = unsafe { c_arg(message_json) };
    alloc_c_string(&upsert_json(&raw, decode_message, |store, message| {
        store
            .upsert_message(message)
            .map_err(rusqlite::Error::InvalidParameterName)
    }))
}

#[no_mangle]
/// Deletes one message row and compacts later ordinals.
///
/// # Safety
///
/// `message_id` must be null or a valid NUL-terminated string for the duration
/// of this call. The returned pointer must be released with `QsNative_Free`.
pub unsafe extern "C" fn QsNative_AiHistory_MarkMessageDeleted(
    message_id: *const c_char,
) -> *mut c_char {
    let message_id = unsafe { c_arg(message_id) };
    alloc_c_string(&with_store("", |store| {
        store.mark_message_deleted(&message_id)?;
        Ok(encode_ok())
    }))
}

#[no_mangle]
/// Deletes all rows from an ordinal onward.
///
/// # Safety
///
/// `conversation_id` must be null or a valid NUL-terminated string for the
/// duration of this call. The returned pointer must be released with
/// `QsNative_Free`.
pub unsafe extern "C" fn QsNative_AiHistory_DeleteFromOrdinal(
    conversation_id: *const c_char,
    ordinal: i32,
) -> *mut c_char {
    let conversation_id = unsafe { c_arg(conversation_id) };
    alloc_c_string(&with_store("", |store| {
        store.delete_from_ordinal(&conversation_id, i64::from(ordinal))?;
        Ok(encode_ok())
    }))
}

#[no_mangle]
/// Inserts or updates a tool-call row from a compact JSON object.
///
/// # Safety
///
/// `tool_call_json` must be null or a valid NUL-terminated string for the
/// duration of this call. The returned pointer must be released with
/// `QsNative_Free`.
pub unsafe extern "C" fn QsNative_AiHistory_UpsertToolCall(
    tool_call_json: *const c_char,
) -> *mut c_char {
    let raw = unsafe { c_arg(tool_call_json) };
    alloc_c_string(&upsert_json(&raw, decode_tool_call, |store, call| {
        store
            .upsert_tool_call(call)
            .map_err(rusqlite::Error::InvalidParameterName)
    }))
}

#[no_mangle]
/// Inserts or updates response-item rows from a compact JSON array.
///
/// # Safety
///
/// Pointer arguments must be null or valid NUL-terminated strings for the
/// duration of this call. The returned pointer must be released with
/// `QsNative_Free`.
pub unsafe extern "C" fn QsNative_AiHistory_UpsertResponseItems(
    conversation_id: *const c_char,
    turn_id: *const c_char,
    turn_ordinal: i32,
    response_items_json: *const c_char,
) -> *mut c_char {
    let conversation_id = unsafe { c_arg(conversation_id) };
    let turn_id = unsafe { c_arg(turn_id) };
    let raw = unsafe { c_arg(response_items_json) };
    alloc_c_string(&upsert_json(&raw, decode_response_items, |store, items| {
        store.upsert_response_items(&conversation_id, &turn_id, i64::from(turn_ordinal), items)
    }))
}

fn with_store(path: &str, f: impl FnOnce(&mut Store) -> rusqlite::Result<String>) -> String {
    match Store::open(path).and_then(|mut store| f(&mut store)) {
        Ok(result) => result,
        Err(err) => encode_error(err.to_string()),
    }
}

/// Decode `raw` JSON with `decode`, open the store, then call `store_op`.
/// Returns the encoded result string.
fn upsert_json<T>(
    raw: &str,
    decode: impl FnOnce(Value) -> Result<T, String>,
    store_op: impl FnOnce(&mut Store, T) -> rusqlite::Result<()>,
) -> String {
    match serde_json::from_str::<Value>(raw)
        .map_err(|err| err.to_string())
        .and_then(decode)
    {
        Ok(decoded) => match Store::open("").and_then(|mut store| store_op(&mut store, decoded)) {
            Ok(()) => encode_ok(),
            Err(err) => encode_error(err.to_string()),
        },
        Err(err) => encode_error(err),
    }
}

unsafe fn open_options(
    model_id: *const c_char,
    provider_id: *const c_char,
    system_prompt: *const c_char,
) -> OpenConversationOptions {
    OpenConversationOptions {
        model_id: unsafe { c_arg(model_id) },
        provider_id: unsafe { c_arg(provider_id) },
        mood_id: String::new(),
        mood_name: String::new(),
        system_prompt: unsafe { c_arg(system_prompt) },
    }
}

unsafe fn c_arg(ptr: *const c_char) -> String {
    if ptr.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(ptr) }
            .to_str()
            .unwrap_or("")
            .to_string()
    }
}

impl Store {
    fn open(path: &str) -> rusqlite::Result<Self> {
        let path = if path.trim().is_empty() {
            default_path()
        } else {
            PathBuf::from(path.trim())
        };
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(io_to_sql)?;
        }
        let conn = Connection::open(&path)?;
        let store = Store { conn };
        store.configure()?;
        store.create_schema()?;
        secure_files(&path).map_err(io_to_sql)?;
        Ok(store)
    }

    fn configure(&self) -> rusqlite::Result<()> {
        self.conn
            .execute_batch("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;")
    }

    fn create_schema(&self) -> rusqlite::Result<()> {
        self.conn.execute_batch(SCHEMA_SQL)
    }

    fn restore_conversation(
        &self,
        opts: &OpenConversationOptions,
    ) -> rusqlite::Result<Option<Conversation>> {
        let model_id = model_id(&opts.model_id);
        self.conn
            .query_row(
                "SELECT id, title, model_id, provider_id, mood_id, mood_name, system_prompt, status, created_at, updated_at
                 FROM conversations
                 WHERE status = 'active' AND model_id = ?
                 ORDER BY updated_at DESC
                 LIMIT 1",
                params![model_id],
                scan_conversation,
            )
            .optional()
    }

    fn create_conversation(
        &mut self,
        opts: &OpenConversationOptions,
    ) -> rusqlite::Result<Conversation> {
        let now = timestamp();
        let conv = Conversation {
            id: new_id(),
            title: String::new(),
            model_id: model_id(&opts.model_id),
            provider_id: opts.provider_id.trim().to_string(),
            mood_id: opts.mood_id.trim().to_string(),
            mood_name: opts.mood_name.trim().to_string(),
            system_prompt: opts.system_prompt.trim().to_string(),
            status: "active".to_string(),
            created_at: now.clone(),
            updated_at: now.clone(),
        };
        self.close_active_conversations(&conv.model_id)?;
        self.conn.execute(
            "INSERT INTO conversations (
                id, model_id, provider_id, mood_id, mood_name, system_prompt, status, created_at, updated_at
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            params![
                conv.id,
                conv.model_id,
                conv.provider_id,
                conv.mood_id,
                conv.mood_name,
                conv.system_prompt,
                conv.status,
                conv.created_at,
                conv.updated_at
            ],
        )?;
        Ok(conv)
    }

    fn close_conversation(&self, id: &str) -> rusqlite::Result<()> {
        let id = id.trim();
        if id.is_empty() {
            return Ok(());
        }
        let now = timestamp();
        self.conn.execute(
            "UPDATE conversations
             SET status = 'closed', closed_at = ?, updated_at = ?
             WHERE id = ? AND status = 'active'",
            params![now, now, id],
        )?;
        Ok(())
    }

    fn resume_conversation(
        &mut self,
        opts: &OpenConversationOptions,
        current_id: &str,
        target_id: &str,
    ) -> rusqlite::Result<(Conversation, Vec<Message>)> {
        let model_id = model_id(&opts.model_id);
        let current_id = current_id.trim();
        let target_id = target_id.trim();
        let mut conv = if target_id.is_empty() {
            self.conn
                .query_row(
                    "SELECT id, title, model_id, provider_id, mood_id, mood_name, system_prompt, status, created_at, updated_at
                     FROM conversations
                     WHERE model_id = ?
                       AND id != ?
                       AND status = 'closed'
                       AND EXISTS (
                         SELECT 1 FROM messages
                         WHERE messages.conversation_id = conversations.id
                           AND messages.status != 'deleted'
                       )
                     ORDER BY coalesce(closed_at, updated_at) DESC, updated_at DESC
                     LIMIT 1",
                    params![model_id, current_id],
                    scan_conversation,
                )
                .optional()?
        } else {
            self.conn
                .query_row(
                    "SELECT id, title, model_id, provider_id, mood_id, mood_name, system_prompt, status, created_at, updated_at
                     FROM conversations
                     WHERE id = ? AND model_id = ? AND status = 'closed'",
                    params![target_id, model_id],
                    scan_conversation,
                )
                .optional()?
        }
        .ok_or_else(|| rusqlite::Error::InvalidQuery)?;

        if !current_id.is_empty() {
            self.close_conversation(current_id)?;
        }
        let now = timestamp();
        self.conn.execute(
            "UPDATE conversations SET status = 'active', closed_at = NULL, updated_at = ? WHERE id = ?",
            params![now, conv.id],
        )?;
        conv.status = "active".to_string();
        conv.updated_at = now;
        let messages = self.list_messages(&conv.id)?;
        Ok((conv, messages))
    }

    fn list_closed_conversations(
        &self,
        opts: &OpenConversationOptions,
        current_id: &str,
        query: &str,
        limit: i64,
    ) -> rusqlite::Result<Vec<ConversationSummary>> {
        let model_id = model_id(&opts.model_id);
        let current_id = current_id.trim();
        let query = query.trim();
        let limit = if limit <= 0 || limit > 100 { 50 } else { limit };
        let like = format!("%{query}%");
        let mut stmt = self.conn.prepare(
            "SELECT
                c.id,
                c.title,
                c.model_id,
                c.provider_id,
                c.status,
                c.created_at,
                c.updated_at,
                coalesce(c.closed_at, ''),
                (
                  SELECT count(*)
                  FROM messages m
                  WHERE m.conversation_id = c.id AND m.status != 'deleted'
                ) AS message_count,
                coalesce((
                  SELECT m.body
                  FROM messages m
                  WHERE m.conversation_id = c.id
                    AND m.status != 'deleted'
                    AND trim(m.body) != ''
                  ORDER BY m.ordinal DESC
                  LIMIT 1
                ), '') AS preview
             FROM conversations c
             WHERE c.model_id = ?
               AND c.id != ?
               AND c.status = 'closed'
               AND EXISTS (
                 SELECT 1 FROM messages m
                 WHERE m.conversation_id = c.id AND m.status != 'deleted'
               )
               AND (
                 ? = ''
                 OR c.title LIKE ?
                 OR c.model_id LIKE ?
                 OR EXISTS (
                   SELECT 1 FROM messages m
                   WHERE m.conversation_id = c.id
                     AND m.status != 'deleted'
                     AND m.body LIKE ?
                 )
               )
             ORDER BY coalesce(c.closed_at, c.updated_at) DESC, c.updated_at DESC
             LIMIT ?",
        )?;
        let rows = stmt.query_map(
            params![model_id, current_id, query, like, like, like, limit],
            |row| {
                Ok(ConversationSummary {
                    id: row.get(0)?,
                    title: row.get(1)?,
                    model_id: row.get(2)?,
                    provider_id: row.get(3)?,
                    status: row.get(4)?,
                    created_at: row.get(5)?,
                    updated_at: row.get(6)?,
                    closed_at: row.get(7)?,
                    message_count: row.get(8)?,
                    preview: row.get(9)?,
                })
            },
        )?;
        rows.collect()
    }

    fn upsert_message(&self, mut msg: Message) -> Result<(), String> {
        if msg.id.trim().is_empty() {
            return Err("message id is required".to_string());
        }
        if msg.conversation_id.trim().is_empty() {
            return Err("conversation id is required".to_string());
        }
        if msg.status.is_empty() {
            msg.status = "complete".to_string();
        }
        if msg.created_at.is_empty() {
            msg.created_at = timestamp();
        }
        let metrics = json_text(&msg.metrics_json);
        let extra = json_text(&msg.extra_json);
        self.conn
            .execute(
                "INSERT INTO messages (
                    id, conversation_id, ordinal, sender, kind, status, body,
                    metrics, extra, created_at, updated_at, completed_at, deleted_at
                 ) VALUES (?, ?, ?, ?, ?, ?, ?, jsonb(?), jsonb(?), ?, nullif(?, ''), nullif(?, ''), nullif(?, ''))
                 ON CONFLICT(id) DO UPDATE SET
                    conversation_id = excluded.conversation_id,
                    ordinal = excluded.ordinal,
                    sender = excluded.sender,
                    kind = excluded.kind,
                    status = excluded.status,
                    body = excluded.body,
                    metrics = excluded.metrics,
                    extra = excluded.extra,
                    updated_at = excluded.updated_at,
                    completed_at = excluded.completed_at,
                    deleted_at = excluded.deleted_at",
                params![
                    msg.id,
                    msg.conversation_id,
                    msg.ordinal,
                    msg.sender,
                    msg.kind,
                    msg.status,
                    msg.body,
                    metrics,
                    extra,
                    msg.created_at,
                    msg.updated_at,
                    msg.completed_at,
                    msg.deleted_at
                ],
            )
            .map_err(|err| err.to_string())?;
        self.touch_conversation(&msg.conversation_id)
            .map_err(|err| err.to_string())
    }

    fn mark_message_deleted(&mut self, id: &str) -> rusqlite::Result<()> {
        let id = id.trim();
        if id.is_empty() {
            return Ok(());
        }
        let target: Option<(String, i64)> = self
            .conn
            .query_row(
                "SELECT conversation_id, ordinal FROM messages WHERE id = ?",
                params![id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()?;
        let Some((conv_id, ordinal)) = target else {
            return Ok(());
        };
        let now = timestamp();
        let tx = self.conn.transaction()?;
        tx.execute("DELETE FROM messages WHERE id = ?", params![id])?;
        tx.execute(
            "DELETE FROM response_items WHERE conversation_id = ? AND turn_ordinal = ?",
            params![conv_id, ordinal],
        )?;
        tx.execute(
            "UPDATE messages
                SET ordinal = -ordinal - 1
              WHERE conversation_id = ? AND ordinal > ?",
            params![conv_id, ordinal],
        )?;
        tx.execute(
            "UPDATE messages
                SET ordinal = -ordinal - 2
              WHERE conversation_id = ? AND ordinal < 0",
            params![conv_id],
        )?;
        tx.execute(
            "UPDATE response_items
                SET turn_ordinal = turn_ordinal - 1
              WHERE conversation_id = ? AND turn_ordinal > ?",
            params![conv_id, ordinal],
        )?;
        tx.execute(
            "UPDATE conversations SET updated_at = ? WHERE id = ?",
            params![now, conv_id],
        )?;
        tx.commit()
    }

    fn delete_from_ordinal(&mut self, conversation_id: &str, ordinal: i64) -> rusqlite::Result<()> {
        let conversation_id = conversation_id.trim();
        if conversation_id.is_empty() {
            return Ok(());
        }
        let now = timestamp();
        let tx = self.conn.transaction()?;
        tx.execute(
            "DELETE FROM messages WHERE conversation_id = ? AND ordinal >= ?",
            params![conversation_id, ordinal],
        )?;
        tx.execute(
            "DELETE FROM response_items WHERE conversation_id = ? AND turn_ordinal >= ?",
            params![conversation_id, ordinal],
        )?;
        tx.execute(
            "UPDATE conversations SET updated_at = ? WHERE id = ?",
            params![now, conversation_id],
        )?;
        tx.commit()
    }

    fn upsert_tool_call(&self, mut call: ToolCall) -> Result<(), String> {
        if call.id.trim().is_empty() {
            return Err("tool call row id is required".to_string());
        }
        if call.message_id.trim().is_empty() {
            return Err("tool call message id is required".to_string());
        }
        if call.call_id.trim().is_empty() {
            return Err("tool call id is required".to_string());
        }
        if call.created_at.is_empty() {
            call.created_at = timestamp();
        }
        let payload = json_text(&call.payload_json);
        self.conn
            .execute(
                "INSERT INTO tool_calls (
                    id, message_id, tool_call_id, tool_name, phase, status, is_error,
                    summary, subtitle, payload, created_at, updated_at
                 ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, jsonb(?), ?, nullif(?, ''))
                 ON CONFLICT(message_id, tool_call_id) DO UPDATE SET
                    tool_name = excluded.tool_name,
                    phase = excluded.phase,
                    status = excluded.status,
                    is_error = excluded.is_error,
                    summary = excluded.summary,
                    subtitle = excluded.subtitle,
                    payload = excluded.payload,
                    updated_at = excluded.updated_at",
                params![
                    call.id,
                    call.message_id,
                    call.call_id,
                    call.tool_name,
                    call.phase,
                    call.status,
                    i32::from(call.is_error),
                    call.summary,
                    call.subtitle,
                    payload,
                    call.created_at,
                    call.updated_at
                ],
            )
            .map(|_| ())
            .map_err(|err| err.to_string())
    }

    fn upsert_response_items(
        &mut self,
        conversation_id: &str,
        turn_id: &str,
        turn_ordinal: i64,
        items: Vec<ResponseItem>,
    ) -> rusqlite::Result<()> {
        let conversation_id = conversation_id.trim();
        let turn_id = turn_id.trim();
        if conversation_id.is_empty() {
            return Err(rusqlite::Error::InvalidParameterName(
                "conversation id is required".to_string(),
            ));
        }
        if turn_id.is_empty() {
            return Err(rusqlite::Error::InvalidParameterName(
                "turn id is required".to_string(),
            ));
        }
        if items.is_empty() {
            return Ok(());
        }
        let explicit_ordinal = items.iter().any(|item| item.item_ordinal != 0);
        let tx = self.conn.transaction()?;
        for (i, mut item) in items.into_iter().enumerate() {
            item.conversation_id = conversation_id.to_string();
            item.turn_id = turn_id.to_string();
            item.turn_ordinal = turn_ordinal;
            if !explicit_ordinal {
                #[expect(
                    clippy::cast_possible_wrap,
                    reason = "i is a response-item index within a single turn; the count never approaches i64::MAX so the cast cannot wrap"
                )]
                {
                    item.item_ordinal = i as i64;
                }
            }
            upsert_response_item(&tx, item)?;
        }
        tx.execute(
            "UPDATE conversations SET updated_at = ? WHERE id = ?",
            params![timestamp(), conversation_id],
        )?;
        tx.commit()
    }

    fn list_response_items(&self, conversation_id: &str) -> rusqlite::Result<Vec<ResponseItem>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, conversation_id, turn_id, turn_ordinal, item_ordinal, source,
                    item_type, call_id, json(raw), created_at
             FROM response_items
             WHERE conversation_id = ?
             ORDER BY turn_ordinal ASC, item_ordinal ASC",
        )?;
        let rows = stmt.query_map(params![conversation_id.trim()], |row| {
            let raw_json: String = row.get(8)?;
            Ok(ResponseItem {
                id: row.get(0)?,
                conversation_id: row.get(1)?,
                turn_id: row.get(2)?,
                turn_ordinal: row.get(3)?,
                item_ordinal: row.get(4)?,
                source: row.get(5)?,
                item_type: row.get(6)?,
                call_id: row.get(7)?,
                raw_json,
                created_at: row.get(9)?,
            })
        })?;
        rows.collect()
    }

    fn list_messages(&self, conversation_id: &str) -> rusqlite::Result<Vec<Message>> {
        let mut stmt = self.conn.prepare(
            "SELECT
                id, conversation_id, ordinal, sender, kind, status, body,
                json(metrics), json(extra), created_at, coalesce(updated_at, ''),
                coalesce(completed_at, ''), coalesce(deleted_at, '')
             FROM messages
             WHERE conversation_id = ? AND status != 'deleted'
             ORDER BY ordinal ASC",
        )?;
        let rows = stmt.query_map(params![conversation_id.trim()], |row| {
            Ok(Message {
                id: row.get(0)?,
                conversation_id: row.get(1)?,
                ordinal: row.get(2)?,
                sender: row.get(3)?,
                kind: row.get(4)?,
                status: row.get(5)?,
                body: row.get(6)?,
                metrics_json: row.get(7)?,
                extra_json: row.get(8)?,
                created_at: row.get(9)?,
                updated_at: row.get(10)?,
                completed_at: row.get(11)?,
                deleted_at: row.get(12)?,
                tool_calls: Vec::new(),
            })
        })?;
        let mut messages: Vec<Message> = rows.collect::<rusqlite::Result<_>>()?;
        for message in &mut messages {
            message.tool_calls = self.list_tool_calls(&message.id)?;
        }
        Ok(messages)
    }

    fn history_items(&self, conversation_id: &str) -> rusqlite::Result<Result<Vec<Value>, String>> {
        let messages = self.list_messages(conversation_id)?;
        let replay_items = self.list_response_items(conversation_id)?;
        Ok(shaped_history(messages, replay_items))
    }

    fn close_active_conversations(&self, raw_model_id: &str) -> rusqlite::Result<()> {
        let now = timestamp();
        self.conn.execute(
            "UPDATE conversations
             SET status = 'closed', closed_at = ?, updated_at = ?
             WHERE status = 'active' AND model_id = ?",
            params![now, now, model_id(raw_model_id)],
        )?;
        Ok(())
    }

    fn list_tool_calls(&self, message_id: &str) -> rusqlite::Result<Vec<ToolCall>> {
        let mut stmt = self.conn.prepare(
            "SELECT
                id, message_id, tool_call_id, tool_name, phase, status, is_error,
                summary, subtitle, json(payload), created_at, coalesce(updated_at, '')
             FROM tool_calls
             WHERE message_id = ?
             ORDER BY created_at ASC",
        )?;
        let rows = stmt.query_map(params![message_id.trim()], |row| {
            let is_error: i64 = row.get(6)?;
            Ok(ToolCall {
                id: row.get(0)?,
                message_id: row.get(1)?,
                call_id: row.get(2)?,
                tool_name: row.get(3)?,
                phase: row.get(4)?,
                status: row.get(5)?,
                is_error: is_error != 0,
                summary: row.get(7)?,
                subtitle: row.get(8)?,
                payload_json: row.get(9)?,
                created_at: row.get(10)?,
                updated_at: row.get(11)?,
            })
        })?;
        rows.collect()
    }

    fn touch_conversation(&self, id: &str) -> rusqlite::Result<()> {
        if id.trim().is_empty() {
            return Ok(());
        }
        self.conn.execute(
            "UPDATE conversations SET updated_at = ? WHERE id = ?",
            params![timestamp(), id.trim()],
        )?;
        Ok(())
    }
}

fn decode_message(value: Value) -> Result<Message, String> {
    let Value::Object(object) = value else {
        return Err("invalid type: expected map".to_string());
    };
    Ok(Message {
        id: value_string(object.get("id")),
        conversation_id: value_string(object.get("conversation_id")),
        ordinal: value_i64(object.get("ordinal")),
        sender: value_string(object.get("sender")),
        kind: value_string(object.get("kind")),
        status: value_string(object.get("status")),
        body: value_string(object.get("body")),
        metrics_json: object
            .get("metrics_json")
            .and_then(flexible_json_value)
            .unwrap_or_else(|| "{}".to_string()),
        extra_json: object
            .get("extra_json")
            .and_then(flexible_json_value)
            .unwrap_or_else(|| "{}".to_string()),
        created_at: value_string(object.get("created_at")),
        updated_at: value_string(object.get("updated_at")),
        completed_at: value_string(object.get("completed_at")),
        deleted_at: value_string(object.get("deleted_at")),
        tool_calls: Vec::new(),
    })
}

fn decode_tool_call(value: Value) -> Result<ToolCall, String> {
    let Value::Object(object) = value else {
        return Err("invalid type: expected map".to_string());
    };
    Ok(ToolCall {
        id: value_string(object.get("id")),
        message_id: value_string(object.get("message_id")),
        call_id: value_string(object.get("tool_call_id")),
        tool_name: value_string(object.get("tool_name")),
        phase: value_string(object.get("phase")),
        status: value_string(object.get("status")),
        is_error: value_bool(object.get("is_error")),
        summary: value_string(object.get("summary")),
        subtitle: value_string(object.get("subtitle")),
        payload_json: object
            .get("payload_json")
            .and_then(flexible_json_value)
            .unwrap_or_else(|| "{}".to_string()),
        created_at: value_string(object.get("created_at")),
        updated_at: value_string(object.get("updated_at")),
    })
}

fn decode_response_items(value: Value) -> Result<Vec<ResponseItem>, String> {
    let Value::Array(values) = value else {
        return Err("invalid type: expected array".to_string());
    };
    let mut items = Vec::with_capacity(values.len());
    for value in values {
        let object = value
            .as_object()
            .ok_or_else(|| "invalid type: expected map".to_string())?;
        let raw = object.get("raw").cloned().unwrap_or(Value::Null);
        let raw_json = object
            .get("raw_json")
            .and_then(flexible_json_value)
            .unwrap_or_default();
        items.push(ResponseItem {
            id: value_string(object.get("id")),
            conversation_id: value_string(object.get("conversation_id")),
            turn_id: value_string(object.get("turn_id")),
            turn_ordinal: value_i64(object.get("turn_ordinal")),
            item_ordinal: value_i64(object.get("item_ordinal")),
            source: value_string(object.get("source")),
            item_type: value_string(object.get("item_type")),
            call_id: value_string(object.get("call_id")),
            raw_json: response_item_raw_json(&raw, &raw_json),
            created_at: value_string(object.get("created_at")),
        });
    }
    Ok(items)
}

fn upsert_response_item(tx: &Transaction<'_>, mut item: ResponseItem) -> rusqlite::Result<()> {
    item.conversation_id = item.conversation_id.trim().to_string();
    item.turn_id = item.turn_id.trim().to_string();
    item.source = item.source.trim().to_string();
    if item.conversation_id.is_empty() {
        return Err(rusqlite::Error::InvalidParameterName(
            "conversation id is required".to_string(),
        ));
    }
    if item.turn_id.is_empty() {
        return Err(rusqlite::Error::InvalidParameterName(
            "turn id is required".to_string(),
        ));
    }
    if item.source.is_empty() {
        item.source = "model_output".to_string();
    }
    if item.source != "model_output" && item.source != "tool_output" {
        return Err(rusqlite::Error::InvalidParameterName(format!(
            "invalid response item source: {}",
            item.source
        )));
    }
    let raw = serde_json::from_str::<Value>(&item.raw_json)
        .map_err(|err| rusqlite::Error::InvalidParameterName(err.to_string()))?;
    let raw = normalize_response_item_value(raw).ok_or_else(|| {
        rusqlite::Error::InvalidParameterName("response item raw JSON is required".to_string())
    })?;
    item.raw_json = compact_value(&raw).ok_or_else(|| {
        rusqlite::Error::InvalidParameterName("response item raw JSON is required".to_string())
    })?;
    let item_type = raw
        .get("type")
        .map(string_from_value)
        .unwrap_or_default()
        .trim()
        .to_string();
    let call_id = raw
        .get("call_id")
        .map(string_from_value)
        .unwrap_or_default()
        .trim()
        .to_string();
    if item.item_type.trim().is_empty() {
        item.item_type = item_type;
    }
    if item.call_id.trim().is_empty() {
        item.call_id = call_id;
    }
    if item.id.trim().is_empty() {
        item.id = format!(
            "{}:{}:{}",
            item.conversation_id, item.turn_id, item.item_ordinal
        );
    }
    if item.created_at.is_empty() {
        item.created_at = timestamp();
    }
    tx.execute(
        "INSERT INTO response_items (
            id, conversation_id, turn_id, turn_ordinal, item_ordinal, source,
            item_type, call_id, raw, created_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, jsonb(?), ?)
         ON CONFLICT(conversation_id, turn_id, item_ordinal) DO UPDATE SET
            id = excluded.id,
            source = excluded.source,
            item_type = excluded.item_type,
            call_id = excluded.call_id,
            raw = excluded.raw",
        params![
            item.id,
            item.conversation_id,
            item.turn_id,
            item.turn_ordinal,
            item.item_ordinal,
            item.source,
            item.item_type.trim(),
            item.call_id.trim(),
            item.raw_json,
            item.created_at
        ],
    )?;
    Ok(())
}

fn shaped_history(
    messages: Vec<Message>,
    response_items: Vec<ResponseItem>,
) -> Result<Vec<Value>, String> {
    let mut replay_by_turn = HashMap::<String, Vec<Value>>::new();
    let mut replay_turn_order = Vec::<String>::new();
    let mut replay_turns_with_message = HashSet::<String>::new();
    for item in response_items {
        if item.turn_id.trim().is_empty() || item.raw_json.trim().is_empty() {
            continue;
        }
        let raw: Value = serde_json::from_str(&item.raw_json).unwrap_or(Value::Null);
        let Some(raw) = normalize_response_item_value(raw) else {
            continue;
        };
        if !replay_by_turn.contains_key(&item.turn_id) {
            replay_turn_order.push(item.turn_id.clone());
        }
        if raw.get("type").map(string_from_value).unwrap_or_default() == "message" {
            replay_turns_with_message.insert(item.turn_id.clone());
        }
        replay_by_turn.entry(item.turn_id).or_default().push(raw);
    }

    let mut out = Vec::new();
    let mut consumed_replay_turns = HashSet::<String>::new();
    let mut active_turn_has_replay = false;
    let mut active_turn_has_raw_message = false;
    for message in messages {
        let replay_items = replay_by_turn.get(&message.id).cloned().unwrap_or_default();
        if message.kind == "chat" && message.sender == "user" {
            out.push(user_input_item(
                &message.body,
                &message_attachments(&message)?,
            )?);
            if replay_items.is_empty() {
                active_turn_has_replay = false;
                active_turn_has_raw_message = false;
            } else {
                out.extend(replay_items);
                consumed_replay_turns.insert(message.id.clone());
                active_turn_has_replay = true;
                active_turn_has_raw_message = replay_turns_with_message.contains(&message.id);
            }
            continue;
        }
        if !replay_items.is_empty() {
            out.extend(replay_items);
            consumed_replay_turns.insert(message.id.clone());
            active_turn_has_replay = true;
            active_turn_has_raw_message = replay_turns_with_message.contains(&message.id);
            continue;
        }
        if active_turn_has_replay {
            if message.kind == "tool" {
                continue;
            }
            if message.kind == "chat"
                && message.sender == "assistant"
                && active_turn_has_raw_message
            {
                continue;
            }
        }
        if message.kind != "chat" {
            continue;
        }
        if message.sender == "assistant" && message.body.trim().is_empty() {
            continue;
        }
        if message.sender == "assistant" {
            out.push(assistant_text_item(
                &responses_message_id(&message.id),
                &message.body,
            ));
        } else {
            out.push(user_input_item(
                &message.body,
                &message_attachments(&message)?,
            )?);
        }
    }
    for turn_id in replay_turn_order {
        if consumed_replay_turns.contains(&turn_id) {
            continue;
        }
        if let Some(replay_items) = replay_by_turn.get(&turn_id) {
            if !replay_items.is_empty() {
                out.extend(replay_items.iter().cloned());
                consumed_replay_turns.insert(turn_id);
            }
        }
    }
    Ok(out)
}

fn message_attachments(message: &Message) -> Result<Vec<crate::ai::Attachment>, String> {
    let Ok(extra) = serde_json::from_str::<Value>(&message.extra_json) else {
        return Ok(Vec::new());
    };
    let Some(attachments) = extra.get("attachments") else {
        return Ok(Vec::new());
    };
    serde_json::from_value::<Vec<crate::ai::Attachment>>(attachments.clone())
        .map_err(|error| error.to_string())
}

/// Builds a Responses API `message` input item for a user turn.
///
/// Text becomes an `input_text` part; attachments become `input_image` parts
/// (referencing a URL directly, or an inline `data:` URI for binary payloads).
/// Only image attachments are supported.
pub(crate) fn user_input_item(
    text: &str,
    attachments: &[crate::ai::Attachment],
) -> Result<Value, String> {
    let mut content = Vec::new();
    if !text.trim().is_empty() {
        content.push(json!({"type": "input_text", "text": text}));
    }
    for attachment in attachments {
        if !attachment.url.trim().is_empty() {
            content.push(json!({
                "type": "input_image",
                "image_url": attachment.url.trim(),
                "detail": "auto",
            }));
            continue;
        }
        if let Some((mime, b64)) = crate::ai::attachment_binary(attachment)? {
            if !mime.to_ascii_lowercase().starts_with("image/") {
                return Err("only image attachments are supported".to_owned());
            }
            content.push(json!({
                "type": "input_image",
                "image_url": format!("data:{mime};base64,{b64}"),
                "detail": "auto",
            }));
        }
    }
    if content.is_empty() {
        content.push(json!({"type": "input_text", "text": ""}));
    }
    Ok(json!({"type": "message", "role": "user", "content": content}))
}

/// Builds a Responses API assistant `message` item carrying plain output text.
fn assistant_text_item(id: &str, body: &str) -> Value {
    json!({
        "type": "message",
        "role": "assistant",
        "id": id,
        "content": [{"type": "output_text", "text": body}],
    })
}

fn scan_conversation(row: &rusqlite::Row<'_>) -> rusqlite::Result<Conversation> {
    Ok(Conversation {
        id: row.get(0)?,
        title: row.get(1)?,
        model_id: row.get(2)?,
        provider_id: row.get(3)?,
        mood_id: row.get(4)?,
        mood_name: row.get(5)?,
        system_prompt: row.get(6)?,
        status: row.get(7)?,
        created_at: row.get(8)?,
        updated_at: row.get(9)?,
    })
}

fn response_item_raw_json(raw: &Value, raw_json: &str) -> String {
    if let Some(text) = flexible_json_value(raw) {
        return text;
    }
    if !raw_json.is_empty() {
        return json_text(raw_json);
    }
    "{}".to_string()
}

fn flexible_json_value(value: &Value) -> Option<String> {
    match value {
        Value::Null => None,
        Value::String(text) => Some(json_text(text)),
        other => Some(json_text(&compact_value(other)?)),
    }
}

fn json_text(raw: &str) -> String {
    let raw = raw.trim();
    if raw.is_empty() || serde_json::from_str::<Value>(raw).is_err() {
        "{}".to_string()
    } else {
        raw.to_string()
    }
}

fn compact_value(value: &Value) -> Option<String> {
    if value.is_null() {
        return None;
    }
    serde_json::to_string(value).ok()
}

fn normalize_response_item_value(mut value: Value) -> Option<Value> {
    if value.is_null() {
        return None;
    }
    if value.get("type").map(string_from_value).unwrap_or_default() != "message" {
        return Some(value);
    }
    let Some(content) = value.get_mut("content").and_then(Value::as_array_mut) else {
        return Some(value);
    };
    let mut normalized = Vec::with_capacity(content.len());
    for mut part in content.drain(..) {
        let Some(object) = part.as_object_mut() else {
            continue;
        };
        match object
            .get("type")
            .map(string_from_value)
            .unwrap_or_default()
            .as_str()
        {
            "input_text" => {
                object.insert("type".to_string(), Value::String("output_text".to_string()));
                normalized.push(part);
            }
            "output_text" | "refusal" => normalized.push(part),
            _ => {}
        }
    }
    *content = normalized;
    Some(value)
}

fn string_from_value(value: &Value) -> String {
    match value {
        Value::Null => String::new(),
        Value::String(text) => text.clone(),
        other => other.to_string(),
    }
}

fn value_string(value: Option<&Value>) -> String {
    value.map(string_from_value).unwrap_or_default()
}

fn value_i64(value: Option<&Value>) -> i64 {
    match value {
        Some(Value::Number(number)) => number.as_i64().unwrap_or_default(),
        Some(Value::String(text)) => text.trim().parse().unwrap_or_default(),
        _ => 0,
    }
}

fn value_bool(value: Option<&Value>) -> bool {
    match value {
        Some(Value::Bool(value)) => *value,
        Some(Value::Number(number)) => number.as_i64().unwrap_or_default() != 0,
        Some(Value::String(text)) => matches!(text.trim(), "true" | "1"),
        _ => false,
    }
}

fn model_id(raw: &str) -> String {
    let raw = raw.trim();
    if raw.is_empty() {
        DEFAULT_MODEL_ID.to_string()
    } else {
        raw.to_string()
    }
}

fn responses_message_id(id: &str) -> String {
    let suffix = id
        .trim()
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric() || *ch == '_')
        .collect::<String>();
    if suffix.is_empty() {
        "msg_local".to_string()
    } else if suffix.starts_with("msg") {
        suffix
    } else {
        format!("msg_{suffix}")
    }
}

fn default_path() -> PathBuf {
    let data_home = env::var("XDG_DATA_HOME")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .or_else(|| {
            env::var("HOME")
                .ok()
                .map(|home| format!("{home}/.local/share"))
        })
        .unwrap_or_else(|| ".".to_string());
    Path::new(&data_home)
        .join("quickshell")
        .join("leftpanel")
        .join("conversations.sqlite")
}

fn timestamp() -> String {
    let now = chrono::Utc::now();
    now.format("%Y-%m-%dT%H:%M:%S.%.3fZ").to_string()
}

fn new_id() -> String {
    Uuid::new_v4().to_string()
}

fn secure_files(path: &Path) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        for candidate in [
            path.to_path_buf(),
            sqlite_sidecar_path(path, "-wal"),
            sqlite_sidecar_path(path, "-shm"),
        ] {
            match fs::metadata(&candidate) {
                Ok(_) => fs::set_permissions(candidate, fs::Permissions::from_mode(0o600))?,
                Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
                Err(err) => return Err(err),
            }
        }
    }
    Ok(())
}

#[cfg(unix)]
fn sqlite_sidecar_path(path: &Path, suffix: &str) -> PathBuf {
    let mut raw = path.as_os_str().to_owned();
    raw.push(suffix);
    PathBuf::from(raw)
}

fn io_to_sql(err: std::io::Error) -> rusqlite::Error {
    rusqlite::Error::ToSqlConversionFailure(Box::new(err))
}

fn encode_ok() -> String {
    encode(&ApiResult {
        ok: true,
        ..Default::default()
    })
}

fn encode_error(error: String) -> String {
    encode(&ApiResult {
        ok: false,
        error,
        ..Default::default()
    })
}

fn encode(result: &ApiResult) -> String {
    serde_json::to_string(result).unwrap_or_else(|_| {
        r#"{"ok":false,"error":"failed to encode chatstore result"}"#.to_string()
    })
}

fn alloc_c_string(s: &str) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| {
            CString::new(r#"{"ok":false,"error":"nul byte in chatstore result"}"#)
                .expect("literal has no nul")
        })
        .into_raw()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

    #[test]
    fn create_upsert_list_flow() {
        let (store, conversation_id) = test_store();
        store
            .upsert_message(Message {
                id: "msg-1".to_string(),
                conversation_id: conversation_id.clone(),
                ordinal: 0,
                sender: "assistant".to_string(),
                kind: "chat".to_string(),
                status: "complete".to_string(),
                body: "stored response".to_string(),
                metrics_json: r#"{"total_ms":42}"#.to_string(),
                ..Message::default()
            })
            .expect("upsert message");

        let messages = store
            .list_messages(&conversation_id)
            .expect("list messages");
        assert_eq!(messages.len(), 1);
        assert_eq!(messages[0].body, "stored response");
        assert!(messages[0].metrics_json.contains("total_ms"));
    }

    #[test]
    fn c_string_allocation_uses_shared_free_contract() {
        let ptr = alloc_c_string(r#"{"ok":true}"#);
        assert!(!ptr.is_null());
        let value = unsafe { CStr::from_ptr(ptr) }.to_string_lossy();
        assert_eq!(value, r#"{"ok":true}"#);
        unsafe {
            crate::mcp::QsNative_Free(ptr);
        }
    }

    #[cfg(unix)]
    #[test]
    fn sqlite_sidecar_path_appends_suffix_without_replacing_extension() {
        let path = Path::new("/tmp/conversations.sqlite");
        assert_eq!(
            sqlite_sidecar_path(path, "-wal"),
            PathBuf::from("/tmp/conversations.sqlite-wal")
        );
        assert_eq!(
            sqlite_sidecar_path(path, "-shm"),
            PathBuf::from("/tmp/conversations.sqlite-shm")
        );
    }

    #[test]
    fn deleted_message_ordinals_can_be_reused() {
        let (mut store, conversation_id) = test_store();
        upsert_chat(
            &store,
            &conversation_id,
            "msg-old",
            0,
            "assistant",
            "old response",
        );
        store
            .mark_message_deleted("msg-old")
            .expect("delete message");
        upsert_chat(
            &store,
            &conversation_id,
            "msg-new",
            0,
            "assistant",
            "new response",
        );

        let messages = store
            .list_messages(&conversation_id)
            .expect("list messages");
        assert_eq!(messages.len(), 1);
        assert_eq!(messages[0].id, "msg-new");
        assert_eq!(messages[0].ordinal, 0);
    }

    #[test]
    fn deleting_middle_message_compacts_persisted_ordinals() {
        let (mut store, conversation_id) = test_store();

        for ordinal in 0..3 {
            upsert_chat(
                &store,
                &conversation_id,
                &format!("msg-{ordinal}"),
                ordinal,
                "assistant",
                &format!("response {ordinal}"),
            );
        }

        store.mark_message_deleted("msg-1").expect("delete message");

        let messages = store
            .list_messages(&conversation_id)
            .expect("list messages");
        assert_eq!(messages.len(), 2);
        assert_eq!(messages[0].id, "msg-0");
        assert_eq!(messages[0].ordinal, 0);
        assert_eq!(messages[1].id, "msg-2");
        assert_eq!(messages[1].ordinal, 1);

        upsert_chat(
            &store,
            &conversation_id,
            "msg-3",
            2,
            "assistant",
            "response 3",
        );
    }

    #[test]
    fn conversation_memory_loads_full_history() {
        let dir = tempfile_dir();
        let path = dir.join("conversations.sqlite");
        let path_text = path.to_string_lossy();
        let mut store = Store::open(&path_text).expect("open store");
        let conversation = store
            .create_conversation(&OpenConversationOptions {
                model_id: "local/gpt-5.4-mini".to_string(),
                provider_id: "local".to_string(),
                ..OpenConversationOptions::default()
            })
            .expect("create conversation");
        let conversation_id = conversation.id;

        for (ordinal, sender, body) in [
            (0, "user", "first"),
            (1, "assistant", "second"),
            (2, "user", "third"),
        ] {
            upsert_chat(
                &store,
                &conversation_id,
                &format!("msg-{ordinal}"),
                ordinal,
                sender,
                body,
            );
        }

        let history = store
            .history_items(&conversation_id)
            .expect("history query")
            .expect("shaped history");
        assert_eq!(history.len(), 3);
        assert_eq!(history[0]["role"], "user");
        assert_eq!(history[1]["role"], "assistant");
        assert_eq!(history[2]["role"], "user");
    }

    #[test]
    fn response_item_upsert_normalizes_message_content_to_output_text() {
        let (mut store, conversation_id) = test_store();
        store
            .upsert_response_items(
                &conversation_id,
                "turn-1",
                0,
                vec![ResponseItem {
                    turn_id: "turn-1".to_string(),
                    item_ordinal: 0,
                    source: "model_output".to_string(),
                    raw_json: r#"{"type":"message","role":"assistant","content":[{"type":"input_text","text":"hello"}]}"#.to_string(),
                    ..ResponseItem::default()
                }],
            )
            .expect("upsert response item");

        let items = store
            .list_response_items(&conversation_id)
            .expect("list response items");
        let raw: Value = serde_json::from_str(&items[0].raw_json).expect("raw json");
        assert_eq!(raw["content"][0]["type"], "output_text");
    }

    #[test]
    fn fallback_assistant_history_keeps_message_id_for_responses_replay() {
        let (store, conversation_id) = test_store();
        upsert_chat(&store, &conversation_id, "user-1", 0, "user", "first");
        upsert_chat(
            &store,
            &conversation_id,
            "assistant-1",
            1,
            "assistant",
            "second",
        );
        upsert_chat(&store, &conversation_id, "user-2", 2, "user", "again");

        let history = store
            .history_items(&conversation_id)
            .expect("history query")
            .expect("shaped history");
        assert_eq!(history[1]["type"], "message");
        assert_eq!(history[1]["role"], "assistant");
        assert_eq!(history[1]["id"], "msg_assistant1");
    }

    #[test]
    fn responses_message_id_maps_local_uuid_to_msg_id() {
        assert_eq!(
            responses_message_id("7fbda73a-d22f-4125-8489-610f9daf7685"),
            "msg_7fbda73ad22f41258489610f9daf7685"
        );
        assert_eq!(responses_message_id("msg_existing"), "msg_existing");
    }

    fn test_store() -> (Store, String) {
        let dir = tempfile_dir();
        let path = dir.join("conversations.sqlite");
        let path_text = path.to_string_lossy();
        let mut store = Store::open(&path_text).expect("open store");
        let conversation = store
            .create_conversation(&OpenConversationOptions {
                model_id: "local/gpt-5.4-mini".to_string(),
                provider_id: "local".to_string(),
                ..OpenConversationOptions::default()
            })
            .expect("create conversation");
        (store, conversation.id)
    }

    fn upsert_chat(
        store: &Store,
        conversation_id: &str,
        id: &str,
        ordinal: i64,
        sender: &str,
        body: &str,
    ) {
        store
            .upsert_message(Message {
                id: id.to_string(),
                conversation_id: conversation_id.to_string(),
                ordinal,
                sender: sender.to_string(),
                kind: "chat".to_string(),
                status: "complete".to_string(),
                body: body.to_string(),
                ..Message::default()
            })
            .expect("upsert message");
    }

    fn tempfile_dir() -> PathBuf {
        let dir = env::temp_dir().join(format!("qsnative-chatstore-test-{}", new_id()));
        fs::create_dir_all(&dir).expect("create temp dir");
        dir
    }
}
