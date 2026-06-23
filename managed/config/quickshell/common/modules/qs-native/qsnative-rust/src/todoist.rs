use core::pin::Pin;
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use chrono::{DateTime, Local, Timelike, Utc};
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

const TODOIST_SYNC_URL: &str = "https://api.todoist.com/api/v1/sync";
const TODOIST_CACHE_VERSION: i32 = 1;
const TODOIST_SYNC_TOKEN_FULL: &str = "*";

#[derive(Default)]
pub struct TodoistClientRust {
    data: QString,
    loading: bool,
    error: QString,
    last_updated: QString,
    cache_path: QString,
    prefer_cache: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct CacheState {
    #[serde(default)]
    sync_token: String,
    #[serde(default)]
    synced_at: i64,
    #[serde(default, rename = "tasks")]
    items: BTreeMap<String, TodoistItem>,
    #[serde(default)]
    projects: BTreeMap<String, TodoistProject>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CacheEnvelope {
    version: i32,
    saved_at: i64,
    state: CacheState,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct TodoistProject {
    id: String,
    #[serde(default)]
    name: String,
    #[serde(default)]
    is_deleted: bool,
    #[serde(default)]
    is_archived: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct TodoistItem {
    id: String,
    #[serde(default)]
    project_id: String,
    #[serde(default)]
    content: String,
    #[serde(default)]
    description: String,
    due: Option<TodoistDue>,
    #[serde(default)]
    checked: bool,
    #[serde(default)]
    is_deleted: bool,
    #[serde(default)]
    updated_at: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct TodoistDue {
    date: Option<String>,
    timezone: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SyncResponse {
    sync_token: Option<String>,
    #[serde(default)]
    full_sync: bool,
    #[serde(default)]
    items: Vec<TodoistItem>,
    #[serde(default)]
    projects: Vec<TodoistProject>,
}

#[derive(Debug, Deserialize)]
struct CommandResponse {
    #[serde(default)]
    sync_status: BTreeMap<String, Value>,
}

#[derive(Debug, Serialize)]
struct TaskOutput {
    id: String,
    title: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    notes: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    due: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    due_human: Option<String>,
    updated: i64,
}

#[derive(Debug, Serialize)]
struct ListOutput {
    today: Vec<TaskOutput>,
    projects: BTreeMap<String, Vec<TaskOutput>>,
    last_updated: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    synced_at: String,
    using_cache: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    error: String,
}

#[derive(Debug, Clone)]
struct RefreshResult {
    data: String,
    error: String,
    last_updated: String,
}

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    impl cxx_qt::Threading for TodoistClient {}

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qobject]
        #[qproperty(QString, data)]
        #[qproperty(bool, loading)]
        #[qproperty(QString, error)]
        #[qproperty(QString, last_updated, cxx_name = "last_updated")]
        #[qproperty(QString, cache_path, cxx_name = "cache_path")]
        #[qproperty(bool, prefer_cache, cxx_name = "prefer_cache")]
        type TodoistClient = super::TodoistClientRust;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qinvokable]
        fn refresh(self: Pin<&mut TodoistClient>) -> bool;

        #[qinvokable]
        fn action(self: Pin<&mut TodoistClient>, verb: &QString, args_json: &QString) -> bool;
    }

    impl cxx_qt::Initialize for TodoistClient {}
}

impl cxx_qt::Initialize for ffi::TodoistClient {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut().set_prefer_cache(true);
    }
}

impl ffi::TodoistClient {
    pub fn refresh(mut self: Pin<&mut Self>) -> bool {
        if *self.as_ref().loading() {
            return false;
        }

        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::default());

        let cache_path = self.cache_path().to_string();
        let prefer_cache = *self.prefer_cache();
        let qt_thread = self.as_ref().qt_thread();

        thread::spawn(move || {
            let result = refresh_todoist(&cache_path, prefer_cache);
            let _ = qt_thread.queue(move |mut client| {
                client.as_mut().apply_refresh_result(result);
                client.as_mut().set_loading(false);
            });
        });

        true
    }

    pub fn action(mut self: Pin<&mut Self>, verb: &QString, args_json: &QString) -> bool {
        if *self.as_ref().loading() {
            return false;
        }

        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::default());

        let verb = verb.to_string();
        let args_json = args_json.to_string();
        let cache_path = self.cache_path().to_string();
        let qt_thread = self.as_ref().qt_thread();

        thread::spawn(move || {
            let result = action_todoist(&verb, &args_json)
                .and_then(|()| refresh_todoist_result(&cache_path, false))
                .unwrap_or_else(|error| refresh_todoist(&cache_path, true).with_error(error));
            let _ = qt_thread.queue(move |mut client| {
                client.as_mut().apply_refresh_result(result);
                client.as_mut().set_loading(false);
            });
        });

        true
    }

    fn apply_refresh_result(mut self: Pin<&mut Self>, result: RefreshResult) {
        self.as_mut().set_error(QString::from(result.error));
        self.as_mut()
            .set_last_updated(QString::from(result.last_updated));
        self.set_data(QString::from(result.data));
    }
}

impl RefreshResult {
    fn with_error(mut self, error: String) -> Self {
        self.error = error;
        self
    }
}

fn refresh_todoist(cache_path: &str, prefer_cache: bool) -> RefreshResult {
    refresh_todoist_result(cache_path, prefer_cache).unwrap_or_else(|error| {
        let cached = read_cache_state(cache_path).ok();
        render_refresh_result(cached.as_ref(), true, &error)
    })
}

fn refresh_todoist_result(cache_path: &str, prefer_cache: bool) -> Result<RefreshResult, String> {
    let cached_state = read_cache_state(cache_path).ok();
    if prefer_cache {
        if let Some(state) = cached_state.as_ref() {
            return Ok(render_refresh_result(Some(state), true, ""));
        }
    }

    let token = read_token()?;
    let sync_token = effective_sync_token(cached_state.as_ref());
    let response = sync_request(&token, &sync_token)?;
    let mut next_state = apply_sync_response(cached_state, response);
    next_state.synced_at = unix_now();
    write_cache_state(cache_path, &next_state)
        .map_err(|error| format!("cache write failed: {error}"))?;

    Ok(render_refresh_result(Some(&next_state), false, ""))
}

fn sync_request(token: &str, sync_token: &str) -> Result<SyncResponse, String> {
    let resource_types = serde_json::to_string(&["items", "projects"]).expect("resource types");
    let agent = todoist_agent();
    let mut response = agent
        .post(TODOIST_SYNC_URL)
        .header("Authorization", &format!("Bearer {token}"))
        .header("Content-Type", "application/x-www-form-urlencoded")
        .send_form([
            ("sync_token", sync_token),
            ("resource_types", &resource_types),
        ])
        .map_err(|error| format!("todoist sync: {error}"))?;

    response
        .body_mut()
        .read_json::<SyncResponse>()
        .map_err(|error| format!("todoist sync response: {error}"))
}

fn action_todoist(verb: &str, args_json: &str) -> Result<(), String> {
    let args: BTreeMap<String, String> = serde_json::from_str(args_json).unwrap_or_default();
    let command = build_command(verb, &args)?;
    let command_uuid = command
        .get("uuid")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned();
    let commands = serde_json::to_string(&[command]).map_err(|error| error.to_string())?;
    let token = read_token()?;

    let agent = todoist_agent();
    let mut response = agent
        .post(TODOIST_SYNC_URL)
        .header("Authorization", &format!("Bearer {token}"))
        .header("Content-Type", "application/x-www-form-urlencoded")
        .send_form([("commands", commands.as_str())])
        .map_err(|error| format!("todoist action: {error}"))?;

    let response = response
        .body_mut()
        .read_json::<CommandResponse>()
        .map_err(|error| format!("todoist action response: {error}"))?;
    match response.sync_status.get(&command_uuid) {
        Some(Value::String(status)) if status == "ok" => Ok(()),
        Some(status) => Err(format!("todoist action failed: {status}")),
        None => Err("todoist action failed: missing sync status".to_owned()),
    }
}

fn build_command(verb: &str, args: &BTreeMap<String, String>) -> Result<Value, String> {
    let uuid = Uuid::new_v4().to_string();
    match verb {
        "close" => {
            let id = required(args, "id")?;
            Ok(json!({"type": "item_close", "uuid": uuid, "args": {"id": id}}))
        }
        "delete" => {
            let id = required(args, "id")?;
            Ok(json!({"type": "item_delete", "uuid": uuid, "args": {"id": id}}))
        }
        "add" => {
            let content = required(args, "content")?;
            let mut command_args = json!({"content": content});
            insert_optional(&mut command_args, args, "description");
            insert_optional(&mut command_args, args, "project_id");
            insert_optional_as_due(&mut command_args, args, "due_string");
            Ok(json!({
                "type": "item_add",
                "uuid": uuid,
                "temp_id": Uuid::new_v4().to_string(),
                "args": command_args,
            }))
        }
        "update" => {
            let id = required(args, "id")?;
            let mut command_args = json!({"id": id});
            insert_optional(&mut command_args, args, "content");
            insert_optional(&mut command_args, args, "description");
            insert_optional_as_due(&mut command_args, args, "due_string");
            Ok(json!({"type": "item_update", "uuid": uuid, "args": command_args}))
        }
        _ => Err(format!("unknown verb: {verb}")),
    }
}

fn get_trimmed<'a>(args: &'a BTreeMap<String, String>, key: &str) -> Option<&'a str> {
    args.get(key).map(|v| v.trim()).filter(|v| !v.is_empty())
}

fn required(args: &BTreeMap<String, String>, key: &str) -> Result<String, String> {
    get_trimmed(args, key)
        .map(str::to_owned)
        .ok_or_else(|| format!("{key} is required"))
}

fn insert_optional(target: &mut Value, args: &BTreeMap<String, String>, key: &str) {
    if let Some(value) = get_trimmed(args, key) {
        target[key] = Value::String(value.to_owned());
    }
}

fn insert_optional_as_due(target: &mut Value, args: &BTreeMap<String, String>, key: &str) {
    if let Some(value) = get_trimmed(args, key) {
        target["due"] = json!({"string": value});
    }
}

fn read_token() -> Result<String, String> {
    crate::secrets::lookup("TODOIST_API_TOKEN")
        .map(|t| t.trim().to_owned())
        .filter(|t| !t.is_empty())
        .ok_or_else(|| "TODOIST_API_TOKEN not found in Secret Service".to_owned())
}

fn todoist_agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(15)))
        .build()
        .new_agent()
}

fn apply_sync_response(cached_state: Option<CacheState>, response: SyncResponse) -> CacheState {
    let mut state = if response.full_sync {
        CacheState::default()
    } else {
        cached_state.unwrap_or_default()
    };

    for project in response.projects {
        if project.id.trim().is_empty() {
            continue;
        }
        if project.is_deleted || project.is_archived {
            state.projects.remove(&project.id);
        } else {
            state.projects.insert(project.id.clone(), project);
        }
    }

    for item in response.items {
        if item.id.trim().is_empty() {
            continue;
        }
        if item.checked || item.is_deleted {
            state.items.remove(&item.id);
        } else {
            state.items.insert(item.id.clone(), item);
        }
    }

    if let Some(t) = response.sync_token.as_deref().map(str::trim).filter(|t| !t.is_empty()) {
        state.sync_token = t.to_owned();
    }

    state
}

fn effective_sync_token(state: Option<&CacheState>) -> String {
    state
        .and_then(|state| {
            let token = state.sync_token.trim();
            (!token.is_empty()).then(|| token.to_owned())
        })
        .unwrap_or_else(|| TODOIST_SYNC_TOKEN_FULL.to_owned())
}

fn render_refresh_result(
    state: Option<&CacheState>,
    using_cache: bool,
    error: &str,
) -> RefreshResult {
    let output = render_list_output(state, using_cache, error);
    let last_updated = output.last_updated.clone();
    let error = output.error.clone();
    let data = serde_json::to_string(&output).unwrap_or_else(|ser_error| {
        format!(r#"{{"today":[],"projects":{{}},"using_cache":true,"error":"{ser_error}"}}"#)
    });
    RefreshResult {
        data,
        error,
        last_updated,
    }
}

fn render_list_output(state: Option<&CacheState>, using_cache: bool, error: &str) -> ListOutput {
    let mut output = ListOutput {
        today: Vec::new(),
        projects: BTreeMap::new(),
        last_updated: Utc::now().to_rfc3339(),
        synced_at: String::new(),
        using_cache,
        error: error.trim().to_owned(),
    };

    let Some(state) = state else {
        return output;
    };

    let today = Local::now().date_naive();
    let mut project_names = BTreeMap::new();
    for project in state.projects.values() {
        project_names.insert(project.id.as_str(), project.name.as_str());
    }

    let mut latest_update: Option<DateTime<Utc>> = None;
    for item in state.items.values() {
        if item.checked || item.is_deleted {
            continue;
        }

        let updated = parse_utc_timestamp(&item.updated_at).unwrap_or_else(Utc::now);
        latest_update = Some(latest_update.map_or(updated, |latest| latest.max(updated)));
        let (due, due_human, is_today) = task_due(item, today);
        let task = TaskOutput {
            id: item.id.clone(),
            title: item.content.clone(),
            notes: item.description.clone(),
            due,
            due_human,
            updated: updated.timestamp(),
        };

        if is_today {
            output.today.push(task);
        } else {
            let project_name = project_names
                .get(item.project_id.as_str())
                .copied()
                .unwrap_or("Unknown")
                .to_owned();
            output.projects.entry(project_name).or_default().push(task);
        }
    }

    output.today.sort_by(|a, b| a.title.cmp(&b.title));
    for tasks in output.projects.values_mut() {
        tasks.sort_by(|a, b| a.title.cmp(&b.title));
    }
    if let Some(latest) = latest_update {
        output.last_updated = latest.to_rfc3339();
    }
    if state.synced_at > 0 {
        output.synced_at = DateTime::<Utc>::from_timestamp(state.synced_at, 0)
            .map(|time| time.to_rfc3339())
            .unwrap_or_default();
    }

    output
}

fn task_due(item: &TodoistItem, today: chrono::NaiveDate) -> (Option<i64>, Option<String>, bool) {
    let Some(date) = item.due.as_ref().and_then(|due| due.date.as_deref()) else {
        return (None, None, false);
    };

    let Some(due_at) = parse_due_date(date) else {
        return (None, None, false);
    };
    let due_date = due_at.date_naive();
    if due_date > today {
        return (Some(due_at.timestamp()), None, false);
    }

    let has_time = due_at.hour() != 0 || due_at.minute() != 0 || due_at.second() != 0;
    let label = if due_date < today {
        "Overdue".to_owned()
    } else if has_time {
        format!("Today {}", due_at.format("%-I:%M %p"))
    } else {
        "Today".to_owned()
    };
    (Some(due_at.timestamp()), Some(label), true)
}

fn parse_due_date(value: &str) -> Option<DateTime<Local>> {
    DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|time| time.with_timezone(&Local))
        .or_else(|| {
            chrono::NaiveDateTime::parse_from_str(value, "%Y-%m-%dT%H:%M:%S")
                .ok()
                .and_then(|time| time.and_local_timezone(Local).single())
        })
        .or_else(|| {
            chrono::NaiveDate::parse_from_str(value, "%Y-%m-%d")
                .ok()
                .and_then(|date| {
                    date.and_hms_opt(0, 0, 0)
                        .and_then(|time| time.and_local_timezone(Local).single())
                })
        })
}

fn parse_utc_timestamp(value: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(value)
        .map(|time| time.with_timezone(&Utc))
        .ok()
}

fn read_cache_state(cache_path: &str) -> Result<CacheState, String> {
    let cache_path = cache_path.trim();
    if cache_path.is_empty() {
        return Err("empty cache path".to_owned());
    }
    let raw = fs::read(cache_path).map_err(|error| error.to_string())?;
    let mut envelope: CacheEnvelope =
        serde_json::from_slice(&raw).map_err(|error| error.to_string())?;
    if envelope.version != TODOIST_CACHE_VERSION {
        return Err("cache version mismatch".to_owned());
    }
    Ok(std::mem::take(&mut envelope.state))
}

fn write_cache_state(cache_path: &str, state: &CacheState) -> Result<(), String> {
    let cache_path = cache_path.trim();
    if cache_path.is_empty() {
        return Ok(());
    }
    let envelope = CacheEnvelope {
        version: TODOIST_CACHE_VERSION,
        saved_at: unix_now(),
        state: state.clone(),
    };
    let data = serde_json::to_vec(&envelope).map_err(|error| error.to_string())?;
    write_file_atomic(Path::new(cache_path), &data)
}

fn write_file_atomic(path: &Path, data: &[u8]) -> Result<(), String> {
    crate::utils::write_file_atomic(path, data, false, Some(0o600))
}

fn unix_now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::{task_due, TodoistDue, TodoistItem};
    use chrono::NaiveDate;

    #[test]
    fn renders_today_due_labels_without_shifting_date_only_tasks() {
        let today = NaiveDate::from_ymd_opt(2026, 4, 26).unwrap();
        let date_only = TodoistItem {
            due: Some(TodoistDue {
                date: Some("2026-04-26".to_owned()),
                timezone: None,
            }),
            ..TodoistItem::default()
        };
        let timed = TodoistItem {
            due: Some(TodoistDue {
                date: Some("2026-04-26T09:30:00".to_owned()),
                timezone: None,
            }),
            ..TodoistItem::default()
        };

        assert_eq!(task_due(&date_only, today).1.as_deref(), Some("Today"));
        assert_eq!(task_due(&timed, today).1.as_deref(), Some("Today 9:30 AM"));
    }
}
