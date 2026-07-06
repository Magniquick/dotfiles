use std::collections::BTreeMap;
use std::ffi::CString;
use std::os::raw::c_char;
use std::path::{Component, Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};

use crate::app_config;
use crate::email::GmailAccount;
use crate::gmail::{GmailClient, GmailMessage};
use crate::utils::first_non_empty;

const CLIENT_VERSION: &str = "v1.0.0";
const BUILTIN_SERVER_ID: &str = "builtin";
const BUILTIN_SERVER_LABEL: &str = "Leftpanel Built-ins";
const BUILTIN_SERVER_INSTRUCTIONS: &str = "Leftpanel Built-ins provides local tools for this Quickshell configuration. Use shell_command only when the user asks you to inspect or modify local state, run project commands, or operate the local machine.";
const EMAIL_SERVER_ID: &str = "email";
const EMAIL_SERVER_LABEL: &str = "Email Accounts";
const EMAIL_SERVER_INSTRUCTIONS: &str = "Email Accounts provides read-only mailbox tools for configured email accounts. Gmail accounts use the Gmail API with refreshable OAuth credentials. Use these tools only when the user asks about email, inbox messages, unread mail, message subjects, or reading a specific email UID or Gmail message id. Do not use email tools for Todoist tasks, projects, reminders, or general task management.";

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct ServerSnapshot {
    pub id: String,
    pub label: String,
    pub url: String,
    pub enabled: bool,
    pub connected: bool,
    pub status: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub error: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub server_name: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub server_version: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub instructions: String,
    pub tool_count: usize,
    pub prompt_count: usize,
    pub resource_count: usize,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub capabilities: BTreeMap<String, Value>,
}

#[expect(
    clippy::struct_excessive_bools,
    reason = "bools mirror the distinct MCP tool annotation flags (readOnly/destructive/openWorld/idempotent) and are serialized individually"
)]
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct ToolSnapshot {
    pub server_id: String,
    pub server_label: String,
    pub name: String,
    pub qualified_name: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub title: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub description: String,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub input_schema: BTreeMap<String, Value>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub output_schema: BTreeMap<String, Value>,
    #[serde(default, skip_serializing_if = "crate::utils::is_false")]
    pub read_only: bool,
    #[serde(default, skip_serializing_if = "crate::utils::is_false")]
    pub destructive: bool,
    #[serde(default, skip_serializing_if = "crate::utils::is_false")]
    pub open_world: bool,
    #[serde(default, skip_serializing_if = "crate::utils::is_false")]
    pub idempotent: bool,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub risk: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct Snapshot {
    pub servers: Vec<ServerSnapshot>,
    pub tools: Vec<ToolSnapshot>,
    pub prompts: Vec<Value>,
    pub resources: Vec<Value>,
    pub status: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub error: String,
}

#[expect(
    clippy::struct_excessive_bools,
    reason = "bools mirror the distinct MCP tool annotation flags (readOnly/destructive/openWorld/idempotent) and are serialized individually"
)]
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct ToolDescriptor {
    pub name: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub title: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub description: String,
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub input_schema: BTreeMap<String, Value>,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub kind: String,
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub format: BTreeMap<String, Value>,
    #[serde(skip_serializing_if = "crate::utils::is_false")]
    pub read_only: bool,
    #[serde(skip_serializing_if = "crate::utils::is_false")]
    pub destructive: bool,
    #[serde(skip_serializing_if = "crate::utils::is_false")]
    pub open_world: bool,
    #[serde(skip_serializing_if = "crate::utils::is_false")]
    pub idempotent: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub risk: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub server_id: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub server_label: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub namespace: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub namespace_description: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub full_instructions: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct ToolResult {
    #[serde(skip_serializing_if = "String::is_empty")]
    pub tool_call_id: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub name: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub text: String,
    #[serde(default, skip_serializing_if = "Map::is_empty")]
    pub data: Map<String, Value>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub content: Vec<Map<String, Value>>,
    #[serde(default, skip_serializing_if = "Map::is_empty")]
    pub structured_content: Map<String, Value>,
    #[serde(default, skip_serializing_if = "Map::is_empty")]
    pub meta: Map<String, Value>,
    #[serde(skip_serializing_if = "crate::utils::is_false")]
    pub is_error: bool,
    #[serde(skip_serializing_if = "is_zero_i64")]
    pub duration_ms: i64,
}

#[must_use]
pub fn refresh() -> String {
    to_json_string(&snapshot())
}

/// Builds the flattened list of tool descriptors from the current snapshot.
///
/// # Errors
///
/// Returns the snapshot error string when no tools are available and the
/// snapshot reported a non-empty error.
pub fn tool_descriptors() -> Result<Vec<ToolDescriptor>, String> {
    let snapshot = snapshot();
    let server_instructions = snapshot
        .servers
        .iter()
        .map(|server| (server.id.clone(), server.instructions.clone()))
        .collect::<BTreeMap<_, _>>();
    let mut out = Vec::with_capacity(snapshot.tools.len());

    for tool in snapshot.tools {
        let mut name = tool.qualified_name.clone();
        if is_local_tool_server(&tool.server_id) {
            name.clone_from(&tool.name);
        }
        let descriptor = ToolDescriptor {
            name,
            title: tool.title,
            description: tool.description,
            input_schema: tool.input_schema,
            read_only: tool.read_only,
            destructive: tool.destructive,
            open_world: tool.open_world,
            idempotent: tool.idempotent,
            risk: first_non_empty([
                tool.risk.as_str(),
                risk_for_tool(tool.read_only, tool.destructive),
            ]),
            server_id: tool.server_id.clone(),
            server_label: tool.server_label,
            full_instructions: server_instructions
                .get(&tool.server_id)
                .cloned()
                .unwrap_or_default(),
            ..ToolDescriptor::default()
        };
        out.push(descriptor);
    }

    if out.is_empty() && !snapshot.error.trim().is_empty() {
        return Err(snapshot.error);
    }
    Ok(out)
}

#[must_use]
pub fn call_tool(server_id: &str, tool_name: &str, arguments: &Map<String, Value>) -> ToolResult {
    let (server_id, tool_name) = split_qualified_tool_name(server_id, tool_name);
    if server_id == BUILTIN_SERVER_ID || (server_id.is_empty() && is_builtin_tool(&tool_name)) {
        return call_builtin_tool(&tool_name, arguments);
    }
    if server_id == EMAIL_SERVER_ID || (server_id.is_empty() && is_email_tool(&tool_name)) {
        return call_email_tool(&tool_name, arguments);
    }
    tool_error(
        &tool_name,
        &format!("Unknown built-in MCP server or tool: {server_id}/{tool_name}"),
    )
}

pub fn tool_result_transcript_payload(result: &ToolResult) -> Map<String, Value> {
    let mut payload = Map::new();
    let mut content = result.content.clone();
    if content.is_empty() {
        let text = result.text.trim();
        if !text.is_empty() {
            let mut item = Map::new();
            item.insert("type".to_owned(), Value::String("text".to_owned()));
            item.insert("text".to_owned(), Value::String(text.to_owned()));
            content.push(item);
        }
    }
    if !content.is_empty() {
        payload.insert(
            "content".to_owned(),
            Value::Array(content.into_iter().map(Value::Object).collect()),
        );
    }

    let structured = if result.structured_content.is_empty() {
        result.data.clone()
    } else {
        result.structured_content.clone()
    };
    if !structured.is_empty() {
        payload.insert("structuredContent".to_owned(), Value::Object(structured));
    }
    if result.is_error {
        payload.insert("isError".to_owned(), Value::Bool(true));
    }
    payload
}

#[must_use]
pub fn tool_result_transcript_output(result: &ToolResult) -> String {
    let payload = tool_result_transcript_payload(result);
    if payload.is_empty() {
        return String::new();
    }
    serde_json::to_string(&payload).unwrap_or_else(|_| {
        let text = result.text.trim();
        if text.is_empty() {
            "{}".to_owned()
        } else {
            text.to_owned()
        }
    })
}

fn snapshot() -> Snapshot {
    let mut servers = vec![builtin_server_snapshot(), email_server_snapshot()];
    let mut tools = builtin_tool_snapshots();
    tools.append(&mut email_tool_snapshots());

    servers
        .sort_by(|a, b| (a.label.as_str(), a.id.as_str()).cmp(&(b.label.as_str(), b.id.as_str())));
    tools.sort_by(|a, b| {
        (a.server_label.as_str(), a.name.as_str()).cmp(&(b.server_label.as_str(), b.name.as_str()))
    });

    Snapshot {
        servers,
        tools,
        prompts: Vec::new(),
        resources: Vec::new(),
        status: "ready".to_owned(),
        error: String::new(),
    }
}

fn email_server_snapshot() -> ServerSnapshot {
    let accounts = load_email_accounts().unwrap_or_default();
    let connected = !accounts.is_empty();
    ServerSnapshot {
        id: EMAIL_SERVER_ID.to_owned(),
        label: EMAIL_SERVER_LABEL.to_owned(),
        url: "builtin://email".to_owned(),
        enabled: true,
        connected,
        status: if connected {
            "connected"
        } else {
            "needs_config"
        }
        .to_owned(),
        server_name: "leftpanel-email".to_owned(),
        server_version: CLIENT_VERSION.to_owned(),
        instructions: EMAIL_SERVER_INSTRUCTIONS.to_owned(),
        tool_count: email_tool_snapshots().len(),
        capabilities: BTreeMap::from([
            ("tools".to_owned(), Value::Bool(true)),
            ("accounts".to_owned(), json!(accounts.len())),
        ]),
        ..ServerSnapshot::default()
    }
}

fn builtin_server_snapshot() -> ServerSnapshot {
    ServerSnapshot {
        id: BUILTIN_SERVER_ID.to_owned(),
        label: BUILTIN_SERVER_LABEL.to_owned(),
        url: "builtin://leftpanel".to_owned(),
        enabled: true,
        connected: true,
        status: "connected".to_owned(),
        server_name: "leftpanel-builtins".to_owned(),
        server_version: CLIENT_VERSION.to_owned(),
        instructions: BUILTIN_SERVER_INSTRUCTIONS.to_owned(),
        tool_count: builtin_tool_snapshots().len(),
        capabilities: BTreeMap::from([("tools".to_owned(), Value::Bool(true))]),
        ..ServerSnapshot::default()
    }
}

fn builtin_tool_snapshots() -> Vec<ToolSnapshot> {
    vec![ToolSnapshot {
        server_id: BUILTIN_SERVER_ID.to_owned(),
        server_label: BUILTIN_SERVER_LABEL.to_owned(),
        name: "shell_command".to_owned(),
        qualified_name: "builtin__shell_command".to_owned(),
        title: "Shell command".to_owned(),
        description: "Run a local shell command and return stdout, stderr, and exit status."
            .to_owned(),
        input_schema: object_schema(
            &BTreeMap::from([
                (
                    "command".to_owned(),
                    string_prop("Command to execute inside the leftpanel bubblewrap sandbox."),
                ),
                (
                    "cwd".to_owned(),
                    string_prop(
                        "Optional sandbox-relative working directory. Defaults to sandbox root.",
                    ),
                ),
                (
                    "timeout_ms".to_owned(),
                    number_prop(
                        "Optional timeout in milliseconds, capped at 120000. Defaults to 30000.",
                    ),
                ),
            ]),
            &["command"],
        ),
        read_only: false,
        destructive: true,
        open_world: true,
        idempotent: false,
        risk: "destructive".to_owned(),
        ..ToolSnapshot::default()
    }]
}

fn call_builtin_tool(tool_name: &str, arguments: &Map<String, Value>) -> ToolResult {
    match tool_name.trim() {
        "shell_command" => call_shell_command(arguments),
        _ => tool_error(tool_name, &format!("Unknown built-in tool: {tool_name}")),
    }
}

fn call_shell_command(arguments: &Map<String, Value>) -> ToolResult {
    let command = string_arg(arguments, "command");
    if command.trim().is_empty() {
        return tool_error("shell_command", "command is required");
    }

    let sandbox_cwd = match sandbox_relative_cwd(&string_arg(arguments, "cwd")) {
        Ok(cwd) => cwd,
        Err(error) => return tool_error("shell_command", &error),
    };
    let bbwrap = PathBuf::from(default_shell_dir())
        .join("tools")
        .join("bbwrap");
    let timeout_ms = u64::try_from(number_arg(arguments, "timeout_ms", 30_000, 1_000, 120_000))
        .unwrap_or(u64::MAX);
    let started = Instant::now();
    let shell_command = sandbox_shell_command(&sandbox_cwd, &command);
    let mut child = match Command::new(&bbwrap)
        .arg("/bin/bash")
        .arg("-lc")
        .arg(&shell_command)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(error) => {
            return tool_error(
                "shell_command",
                &format!(
                    "spawn sandboxed shell command via {}: {error}",
                    bbwrap.display()
                ),
            );
        }
    };

    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    loop {
        match child.try_wait() {
            Ok(Some(_status)) => break,
            Ok(None) if Instant::now() >= deadline => {
                let _ = child.kill();
                let _ = child.wait();
                return ToolResult {
                    name: "shell_command".to_owned(),
                    text: format!("Command timed out after {timeout_ms}ms"),
                    data: map_from_value(json!({
                        "command": command,
                        "sandbox_cwd": sandbox_cwd,
                        "sandbox": sandbox_dir().display().to_string(),
                        "timed_out": true,
                        "timeout_ms": timeout_ms,
                    })),
                    is_error: true,
                    duration_ms: elapsed_millis_i64(started),
                    ..ToolResult::default()
                };
            }
            Ok(None) => thread::sleep(Duration::from_millis(25)),
            Err(error) => {
                let _ = child.kill();
                return tool_error("shell_command", &format!("wait for shell command: {error}"));
            }
        }
    }

    let output = match child.wait_with_output() {
        Ok(output) => output,
        Err(error) => return tool_error("shell_command", &format!("read shell output: {error}")),
    };
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    let code = output.status.code().unwrap_or(-1);
    let text = first_non_empty([
        stdout.trim(),
        stderr.trim(),
        format!("Command exited with status {code}.").as_str(),
    ]);
    ToolResult {
        name: "shell_command".to_owned(),
        text,
        data: map_from_value(json!({
            "command": command,
            "sandbox_cwd": sandbox_cwd,
            "sandbox": sandbox_dir().display().to_string(),
            "exit_code": code,
            "success": output.status.success(),
            "stdout": stdout,
            "stderr": stderr,
            "duration_ms": elapsed_millis_i64(started),
        })),
        is_error: !output.status.success(),
        duration_ms: elapsed_millis_i64(started),
        ..ToolResult::default()
    }
}

fn email_tool_snapshots() -> Vec<ToolSnapshot> {
    vec![
        ToolSnapshot {
            server_id: EMAIL_SERVER_ID.to_owned(),
            server_label: EMAIL_SERVER_LABEL.to_owned(),
            name: "email_accounts".to_owned(),
            qualified_name: "email__email_accounts".to_owned(),
            title: "Email accounts".to_owned(),
            description: "List configured email accounts from leftpanel/config.toml without exposing credentials.".to_owned(),
            input_schema: object_schema(&BTreeMap::new(), &[]),
            read_only: true,
            risk: "read".to_owned(),
            ..ToolSnapshot::default()
        },
        ToolSnapshot {
            server_id: EMAIL_SERVER_ID.to_owned(),
            server_label: EMAIL_SERVER_LABEL.to_owned(),
            name: "email_search".to_owned(),
            qualified_name: "email__email_search".to_owned(),
            title: "Search email".to_owned(),
            description: "Search a Gmail account for messages by Gmail-style query operators.".to_owned(),
            input_schema: object_schema(
                &BTreeMap::from([
                    ("account".to_owned(), email_account_prop()),
                    ("query".to_owned(), string_prop("Gmail-style search query.")),
                    ("mailbox".to_owned(), string_prop("Mailbox label. Defaults to gmail.")),
                    ("limit".to_owned(), number_prop("Maximum messages to return, capped at 50. Defaults to 10.")),
                ]),
                &[],
            ),
            read_only: true,
            risk: "read".to_owned(),
            ..ToolSnapshot::default()
        },
        ToolSnapshot {
            server_id: EMAIL_SERVER_ID.to_owned(),
            server_label: EMAIL_SERVER_LABEL.to_owned(),
            name: "email_read".to_owned(),
            qualified_name: "email__email_read".to_owned(),
            title: "Read email".to_owned(),
            description: "Read one Gmail API message id and return headers plus a bounded text/html body excerpt.".to_owned(),
            input_schema: object_schema(
                &BTreeMap::from([
                    ("account".to_owned(), email_account_prop()),
                    ("id".to_owned(), string_prop("Gmail API message id from email_search.")),
                    ("gmail_id".to_owned(), string_prop("Alias for id.")),
                    ("max_body_chars".to_owned(), number_prop("Maximum body characters, capped at 100000. Defaults to 20000.")),
                ]),
                &[],
            ),
            read_only: true,
            risk: "read".to_owned(),
            ..ToolSnapshot::default()
        },
    ]
}

fn default_shell_dir() -> String {
    std::env::var("QS_SHELL_DIR")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .or_else(|| {
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .ancestors()
                .nth(3)
                .map(|path| path.to_string_lossy().into_owned())
        })
        .unwrap_or_else(|| ".".to_owned())
}

fn sandbox_dir() -> PathBuf {
    std::env::var("LEFTPANEL_AI_SANDBOX")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .map_or_else(
            || {
                let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_owned());
                PathBuf::from(home).join("tmp").join("ai-sandbox")
            },
            PathBuf::from,
        )
}

fn sandbox_relative_cwd(raw: &str) -> Result<String, String> {
    let raw = raw.trim();
    if raw.is_empty() || raw == "." {
        return Ok(String::new());
    }
    let path = Path::new(raw);
    if path.is_absolute() {
        let sandbox = sandbox_dir();
        let relative = path
            .strip_prefix(&sandbox)
            .map_err(|_| "cwd must be inside the sandbox root".to_owned())?;
        if relative.as_os_str().is_empty() {
            return Ok(String::new());
        }
        return sandbox_relative_path(relative);
    }
    sandbox_relative_path(path)
}

fn sandbox_relative_path(path: &Path) -> Result<String, String> {
    if path
        .components()
        .any(|component| matches!(component, Component::ParentDir | Component::Prefix(_)))
    {
        return Err("cwd must stay inside the sandbox root".to_owned());
    }
    Ok(path.to_string_lossy().into_owned())
}

fn sandbox_shell_command(cwd: &str, command: &str) -> String {
    if cwd.trim().is_empty() {
        return command.to_owned();
    }
    format!("cd {} && {}", shell_quote(cwd), command)
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn call_email_tool(tool_name: &str, arguments: &Map<String, Value>) -> ToolResult {
    match tool_name.trim() {
        "email_accounts" => call_email_accounts(),
        "email_search" => call_email_search(arguments),
        "email_read" => call_email_read(arguments),
        "email_send" => tool_error(
            "email_send",
            "email_send is disabled by default; leftpanel email MCP is read-only.",
        ),
        _ => tool_error(tool_name, &format!("Unknown email tool: {tool_name}")),
    }
}

fn call_email_accounts() -> ToolResult {
    let accounts = match load_email_accounts() {
        Ok(accounts) => accounts,
        Err(error) => return tool_error("email_accounts", &error),
    };
    if accounts.is_empty() {
        return tool_error(
            "email_accounts",
            "No email accounts configured. Add email account metadata to leftpanel/config.toml.",
        );
    }
    let public = accounts
        .iter()
        .map(public_email_account)
        .collect::<Vec<_>>();
    let lines = accounts
        .iter()
        .map(|account| {
            format!(
                "- {}: {} ({})",
                account.id.trim(),
                account.address.trim(),
                account.provider.trim()
            )
        })
        .collect::<Vec<_>>()
        .join("\n");
    ToolResult {
        name: "email_accounts".to_owned(),
        text: lines,
        data: map_from_value(json!({ "accounts": public })),
        ..ToolResult::default()
    }
}

fn call_email_search(arguments: &Map<String, Value>) -> ToolResult {
    let account = match select_email_account(arguments) {
        Ok(account) => account,
        Err(error) => return tool_error("email_search", &error),
    };
    if account.provider.trim() != "gmail" {
        return tool_error(
            "email_search",
            "Rust email MCP currently supports Gmail accounts only",
        );
    }
    let limit = u32::try_from(number_arg(arguments, "limit", 10, 1, 50)).unwrap_or(u32::MAX);
    let query = string_arg(arguments, "query");
    let gmail_account = match GmailAccount::load(&account.id, account.address.trim()) {
        Ok(account) => account,
        Err(error) => return tool_error("email_search", &error),
    };
    let client = GmailClient::new(&gmail_account);
    let list = match client.list_messages(&query, limit) {
        Ok(list) => list,
        Err(error) => return tool_error("email_search", &error),
    };
    if list.messages.is_empty() {
        return ToolResult {
            name: "email_search".to_owned(),
            text: "No messages matched.".to_owned(),
            data: map_from_value(json!({
                "account": account.id,
                "mailbox": gmail_mailbox_label(arguments),
                "matched_count": list.estimate,
                "returned_count": 0,
                "limit": limit,
                "messages": [],
            })),
            ..ToolResult::default()
        };
    }

    let mut messages = Vec::new();
    let mut lines = Vec::new();
    for listed in &list.messages {
        let mut message = match client.get_message(&listed.id, false, 0) {
            Ok(message) => message,
            Err(error) => return tool_error("email_search", &error),
        };
        if message.id.trim().is_empty() {
            message.id.clone_from(&listed.id);
        }
        if message.thread_id.trim().is_empty() {
            message.thread_id.clone_from(&listed.thread_id);
        }
        lines.push(format!(
            "- Gmail {}: {}",
            message.id,
            first_non_empty([message.subject.as_str(), "(no subject)"])
        ));
        messages.push(gmail_message_summary(&message, false));
    }
    let matched_count = if list.estimate == 0 {
        i64::try_from(list.messages.len()).unwrap_or(i64::MAX)
    } else {
        list.estimate
    };
    ToolResult {
        name: "email_search".to_owned(),
        text: lines.join("\n"),
        data: map_from_value(json!({
            "account": account.id,
            "mailbox": gmail_mailbox_label(arguments),
            "matched_count": matched_count,
            "returned_count": messages.len(),
            "limit": limit,
            "messages": messages,
        })),
        ..ToolResult::default()
    }
}

fn call_email_read(arguments: &Map<String, Value>) -> ToolResult {
    let account = match select_email_account(arguments) {
        Ok(account) => account,
        Err(error) => return tool_error("email_read", &error),
    };
    if account.provider.trim() != "gmail" {
        return tool_error(
            "email_read",
            "Rust email MCP currently supports Gmail accounts only",
        );
    }
    let id = first_non_empty([
        string_arg(arguments, "id").as_str(),
        string_arg(arguments, "gmail_id").as_str(),
    ]);
    if id.is_empty() {
        return tool_error(
            "email_read",
            "id is required for Gmail accounts; pass the id or gmail_id returned by email_search",
        );
    }
    let max_body_chars =
        usize::try_from(number_arg(arguments, "max_body_chars", 20_000, 1_000, 100_000))
            .unwrap_or(usize::MAX);
    let gmail_account = match GmailAccount::load(&account.id, account.address.trim()) {
        Ok(account) => account,
        Err(error) => return tool_error("email_read", &error),
    };
    let client = GmailClient::new(&gmail_account);
    let mut message = match client.get_message(&id, true, max_body_chars) {
        Ok(message) => message,
        Err(error) => return tool_error("email_read", &error),
    };
    if message.id.trim().is_empty() {
        message.id.clone_from(&id);
    }
    ToolResult {
        name: "email_read".to_owned(),
        text: first_non_empty([
            message.body_text.as_str(),
            message.body_html.as_str(),
            message.snippet.as_str(),
            format!("Read Gmail message {id}.").as_str(),
        ]),
        data: map_from_value(json!({
            "account": account.id,
            "mailbox": gmail_mailbox_label(arguments),
            "message": gmail_message_summary(&message, true),
        })),
        ..ToolResult::default()
    }
}

fn load_email_accounts() -> Result<Vec<app_config::EmailAccount>, String> {
    let path = app_config::default_path();
    app_config::load_all_accounts(&path)
}

fn select_email_account(
    arguments: &Map<String, Value>,
) -> Result<app_config::EmailAccount, String> {
    let accounts = load_email_accounts()?;
    let selector = string_arg(arguments, "account");
    app_config::select_account_by_id_or_address(&accounts, &selector).cloned()
}

fn public_email_account(account: &app_config::EmailAccount) -> Value {
    json!({
        "id": account.id.trim(),
        "label": first_non_empty([account.label.as_str(), account.id.as_str()]),
        "provider": account.provider.trim(),
        "address": account.address.trim(),
        "from": account.address.trim(),
        "imap_host": "imap.gmail.com",
        "imap_port": 993,
        "imap_tls": "ssl",
        "can_read": true,
        "can_send": false,
        "auth_source": "google-oauth-token",
    })
}

fn gmail_message_summary(message: &GmailMessage, include_body: bool) -> Value {
    let mut out = json!({
        "id": message.id,
        "gmail_id": message.id,
        "thread_id": message.thread_id,
        "subject": message.subject,
        "from": message.from,
        "to": message.to,
        "date": message.date,
        "message_id": message.message_id,
        "snippet": message.snippet,
        "internal_date": message.internal_date,
        "size": message.size,
        "label_ids": message.label_ids,
    });
    if include_body {
        out["body_text"] = json!(message.body_text);
        out["body_html"] = json!(message.body_html);
        out["body_truncated"] = json!(message.body_truncated);
    }
    out
}

fn gmail_mailbox_label(arguments: &Map<String, Value>) -> String {
    first_non_empty([string_arg(arguments, "mailbox").as_str(), "gmail"])
}

fn is_email_tool(tool_name: &str) -> bool {
    matches!(
        tool_name.trim(),
        "email_accounts" | "email_search" | "email_read" | "email_send"
    )
}

fn is_builtin_tool(tool_name: &str) -> bool {
    matches!(tool_name.trim(), "shell_command")
}

fn is_local_tool_server(server_id: &str) -> bool {
    matches!(server_id.trim(), BUILTIN_SERVER_ID | EMAIL_SERVER_ID)
}

fn split_qualified_tool_name(server_id: &str, tool_name: &str) -> (String, String) {
    let mut server_id = server_id.trim().to_owned();
    let mut tool_name = tool_name.trim().to_owned();
    if server_id.is_empty() {
        if let Some((prefix, suffix)) = tool_name.split_once("__") {
            prefix.clone_into(&mut server_id);
            tool_name = suffix.to_owned();
        }
    } else {
        tool_name = strip_server_prefix(&server_id, &tool_name);
    }
    (server_id, tool_name)
}

fn strip_server_prefix(server_id: &str, tool_name: &str) -> String {
    tool_name
        .trim()
        .strip_prefix(&format!("{}__", server_id.trim()))
        .unwrap_or(tool_name.trim())
        .to_owned()
}

fn risk_for_tool(read_only: bool, destructive: bool) -> &'static str {
    if read_only {
        "read"
    } else if destructive {
        "destructive"
    } else {
        "write"
    }
}

fn object_schema(
    properties: &BTreeMap<String, Value>,
    required: &[&str],
) -> BTreeMap<String, Value> {
    let mut schema = BTreeMap::from([
        ("type".to_owned(), Value::String("object".to_owned())),
        ("properties".to_owned(), json!(properties)),
    ]);
    if !required.is_empty() {
        schema.insert("required".to_owned(), json!(required));
    }
    schema
}

fn email_account_prop() -> Value {
    string_prop("Email account id or address. Defaults to the first configured account.")
}

fn string_prop(description: &str) -> Value {
    json!({"type": "string", "description": description})
}

fn number_prop(description: &str) -> Value {
    json!({"type": "number", "description": description})
}

fn map_from_value(value: Value) -> Map<String, Value> {
    match value {
        Value::Object(map) => map,
        _ => Map::new(),
    }
}

fn string_arg(arguments: &Map<String, Value>, key: &str) -> String {
    arguments
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_owned()
}

#[expect(
    clippy::cast_possible_truncation,
    reason = "JSON float args are coerced to a whole-number fallback and clamped to [min, max]"
)]
fn number_arg(arguments: &Map<String, Value>, key: &str, default: i64, min: i64, max: i64) -> i64 {
    arguments
        .get(key)
        .and_then(|value| value.as_i64().or_else(|| value.as_f64().map(|n| n as i64)))
        .unwrap_or(default)
        .clamp(min, max)
}

fn elapsed_millis_i64(started: Instant) -> i64 {
    i64::try_from(started.elapsed().as_millis()).unwrap_or(i64::MAX)
}

#[must_use]
pub fn tool_error(name: &str, text: &str) -> ToolResult {
    ToolResult {
        name: name.trim().to_owned(),
        text: text.to_owned(),
        is_error: true,
        ..ToolResult::default()
    }
}

fn to_json_string<T: Serialize>(value: &T) -> String {
    serde_json::to_string(value).unwrap_or_else(|error| {
        json!({"error": format!("serialize MCP result: {error}")}).to_string()
    })
}

fn alloc_c_string(value: String) -> *mut c_char {
    CString::new(value)
        .unwrap_or_else(|_| CString::new(r#"{"error":"nul byte in MCP result"}"#).expect("literal"))
        .into_raw()
}

#[expect(
    clippy::trivially_copy_pass_by_ref,
    reason = "serde skip_serializing_if requires an fn(&T) -> bool signature"
)]
fn is_zero_i64(value: &i64) -> bool {
    *value == 0
}

#[no_mangle]
pub extern "C" fn QsNative_AiMcp_Refresh() -> *mut c_char {
    alloc_c_string(refresh())
}

#[no_mangle]
/// Frees a string returned by a `QsNative_*` C ABI function.
///
/// # Safety
///
/// `s` must be null or a pointer previously returned by this Rust library via
/// `CString::into_raw`. Passing any other pointer is undefined behavior.
pub unsafe extern "C" fn QsNative_Free(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refresh_and_descriptors_include_email_catalog() {
        let snapshot: Snapshot = serde_json::from_str(&refresh()).expect("snapshot json");
        assert_eq!(snapshot.status, "ready");
        assert!(snapshot
            .servers
            .iter()
            .any(|server| server.id == BUILTIN_SERVER_ID));
        assert!(snapshot
            .servers
            .iter()
            .any(|server| server.id == EMAIL_SERVER_ID));

        let names = snapshot
            .tools
            .iter()
            .map(|tool| tool.qualified_name.as_str())
            .collect::<Vec<_>>();
        assert!(names.contains(&"builtin__shell_command"));
        assert!(names.contains(&"email__email_accounts"));

        let descriptors = tool_descriptors().expect("descriptors");
        assert!(descriptors.iter().any(|tool| {
            tool.name == "shell_command" && tool.server_id == BUILTIN_SERVER_ID && tool.destructive
        }));
        assert!(descriptors.iter().any(|tool| {
            tool.name == "email_accounts" && tool.namespace.is_empty() && tool.read_only
        }));
    }

    #[test]
    fn tool_result_transcript_serialization_matches_provider_shape() {
        let result = ToolResult {
            text: "message body".to_owned(),
            data: map_from_value(json!({"subject": "Status", "uid": 4938})),
            meta: map_from_value(json!({"source": "todoist"})),
            is_error: true,
            ..ToolResult::default()
        };

        let output = tool_result_transcript_output(&result);
        let payload: Value = serde_json::from_str(&output).expect("payload json");
        assert_eq!(payload["content"][0]["type"], "text");
        assert_eq!(payload["content"][0]["text"], "message body");
        assert_eq!(payload["structuredContent"]["subject"], "Status");
        assert_eq!(payload["structuredContent"]["uid"], 4938);
        assert_eq!(payload["isError"], true);
        assert!(payload.get("_meta").is_none());
    }

    #[test]
    fn sandbox_cwd_accepts_absolute_path_inside_sandbox() {
        let sandbox = sandbox_dir();
        assert_eq!(
            sandbox_relative_cwd(&sandbox.display().to_string()).expect("sandbox root"),
            ""
        );
        assert_eq!(
            sandbox_relative_cwd(&sandbox.join("notes/today").display().to_string())
                .expect("sandbox child"),
            "notes/today"
        );
    }

    #[test]
    fn sandbox_cwd_rejects_paths_outside_sandbox() {
        assert!(sandbox_relative_cwd("/tmp").is_err());
        assert!(sandbox_relative_cwd("../outside").is_err());
        assert!(sandbox_relative_cwd("nested/../../outside").is_err());
    }
}
