use chrono::{DateTime, Local, NaiveDate, TimeZone, Utc};
use cxx_qt::Threading;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::pin::Pin;

use crate::qobjects;
use crate::util::env::load_env;

impl qobjects::TodoistClient {
    pub fn list_tasks(self: Pin<&mut Self>, env_file: &cxx_qt_lib::QString) -> bool {
        let env_file = env_file.to_string();
        let qt_thread = self.qt_thread();
        std::thread::spawn(move || {
            let result = todoist_list_tasks(&env_file);
            qt_thread
                .queue(move |mut obj| match result {
                    Ok(payload) => {
                        obj.as_mut().set_error(cxx_qt_lib::QString::from(""));
                        obj.as_mut()
                            .set_data_json(cxx_qt_lib::QString::from(payload));
                        obj.as_mut()
                            .set_last_updated(cxx_qt_lib::QString::from(Local::now().to_rfc3339()));
                    }
                    Err(err) => {
                        obj.as_mut().set_error(cxx_qt_lib::QString::from(err));
                    }
                })
                .ok();
        });
        true
    }

    pub fn list_tasklists(self: Pin<&mut Self>, env_file: &cxx_qt_lib::QString) -> bool {
        let env_file = env_file.to_string();
        let qt_thread = self.qt_thread();
        std::thread::spawn(move || {
            let result = todoist_list_projects(&env_file);
            qt_thread
                .queue(move |mut obj| match result {
                    Ok(payload) => {
                        obj.as_mut().set_error(cxx_qt_lib::QString::from(""));
                        obj.as_mut()
                            .set_data_json(cxx_qt_lib::QString::from(payload));
                        obj.as_mut()
                            .set_last_updated(cxx_qt_lib::QString::from(Local::now().to_rfc3339()));
                    }
                    Err(err) => {
                        obj.as_mut().set_error(cxx_qt_lib::QString::from(err));
                    }
                })
                .ok();
        });
        true
    }

    pub fn complete_task(
        self: Pin<&mut Self>,
        env_file: &cxx_qt_lib::QString,
        id: &cxx_qt_lib::QString,
    ) -> bool {
        let env_file = env_file.to_string();
        let id = id.to_string();
        let qt_thread = self.qt_thread();
        std::thread::spawn(move || {
            let result = todoist_complete_task(&env_file, &id);
            qt_thread
                .queue(move |mut obj| match result {
                    Ok(()) => {
                        obj.as_mut().set_error(cxx_qt_lib::QString::from(""));
                    }
                    Err(err) => {
                        obj.as_mut().set_error(cxx_qt_lib::QString::from(err));
                    }
                })
                .ok();
        });
        true
    }

    pub fn delete_task(
        self: Pin<&mut Self>,
        env_file: &cxx_qt_lib::QString,
        id: &cxx_qt_lib::QString,
    ) -> bool {
        let env_file = env_file.to_string();
        let id = id.to_string();
        let qt_thread = self.qt_thread();
        std::thread::spawn(move || {
            let result = todoist_delete_task(&env_file, &id);
            qt_thread
                .queue(move |mut obj| match result {
                    Ok(()) => {
                        obj.as_mut().set_error(cxx_qt_lib::QString::from(""));
                    }
                    Err(err) => {
                        obj.as_mut().set_error(cxx_qt_lib::QString::from(err));
                    }
                })
                .ok();
        });
        true
    }
}

#[derive(Deserialize, Debug)]
struct Task {
    id: String,
    content: String,
    description: Option<String>,
    project_id: String,
    updated_at: DateTime<Utc>,
    due: Option<Due>,
}

#[derive(Deserialize, Debug)]
struct Due {
    date: String,
}

#[derive(Deserialize, Serialize, Debug)]
struct Project {
    id: String,
    name: String,
}

#[derive(Serialize)]
struct TaskOutput {
    id: String,
    title: String,
    notes: Option<String>,
    due: Option<i64>,
    due_human: Option<String>,
    updated: i64,
}

#[derive(Serialize)]
struct ListOutput {
    today: Vec<TaskOutput>,
    projects: HashMap<String, Vec<TaskOutput>>,
}

#[derive(Deserialize, Debug)]
struct Paginated<T> {
    results: Vec<T>,
    next_cursor: Option<String>,
}

const TODOIST_API_BASE: &str = "https://api.todoist.com/api/v1";

fn fetch_all_pages<T: for<'de> Deserialize<'de>>(
    client: &reqwest::blocking::Client,
    url: &str,
) -> Result<Vec<T>, String> {
    let mut out: Vec<T> = Vec::new();
    let mut cursor: Option<String> = None;

    loop {
        let mut full_url = reqwest::Url::parse(url).map_err(|err| err.to_string())?;
        {
            let mut pairs = full_url.query_pairs_mut();
            pairs.append_pair("limit", "200");
            if let Some(next) = &cursor {
                if !next.is_empty() {
                    pairs.append_pair("cursor", next);
                }
            }
        }

        let page: Paginated<T> = client
            .get(full_url)
            .send()
            .map_err(|err| err.to_string())?
            .error_for_status()
            .map_err(|err| err.to_string())?
            .json()
            .map_err(|err| err.to_string())?;

        out.extend(page.results);

        match page.next_cursor {
            Some(next) if !next.is_empty() => cursor = Some(next),
            _ => break,
        }
    }

    Ok(out)
}

fn todoist_list_tasks(env_file: &str) -> Result<String, String> {
    load_env(env_file);
    let token = std::env::var("TODOIST_API_TOKEN")
        .map_err(|_| "TODOIST_API_TOKEN not found in environment (.env)".to_string())?;
    let client = build_client(&token)?;

    let tasks: Vec<Task> = fetch_all_pages(&client, &format!("{}/tasks", TODOIST_API_BASE))?;
    let projects: Vec<Project> =
        fetch_all_pages(&client, &format!("{}/projects", TODOIST_API_BASE))?;

    let project_map: HashMap<String, String> = projects
        .iter()
        .map(|p| (p.id.clone(), p.name.clone()))
        .collect();

    let mut today_tasks = Vec::new();
    let mut projects_tasks: HashMap<String, Vec<TaskOutput>> = HashMap::new();

    let today = Local::now().date_naive();

    for task in tasks {
        if let Some((due_ts, has_time)) = parse_todoist_date(task.due.as_ref())? {
            let due_local = DateTime::<Local>::from(due_ts);
            let due_naive = due_local.date_naive();
            if due_naive == today {
                today_tasks.push(TaskOutput {
                    id: task.id,
                    title: task.content,
                    notes: task.description,
                    due: Some(due_local.timestamp()),
                    due_human: Some(humanise(due_local, has_time)),
                    updated: task.updated_at.timestamp(),
                });
                continue;
            }
        }

        let proj_name = project_map
            .get(&task.project_id)
            .cloned()
            .unwrap_or_else(|| "Unknown".to_string());
        projects_tasks
            .entry(proj_name)
            .or_default()
            .push(TaskOutput {
                id: task.id,
                title: task.content,
                notes: task.description,
                due: None,
                due_human: None,
                updated: task.updated_at.timestamp(),
            });
    }

    today_tasks.sort_by_key(|t| (t.due, t.updated));
    for tasks in projects_tasks.values_mut() {
        tasks.sort_by_key(|t| t.updated);
    }

    let output = ListOutput {
        today: today_tasks,
        projects: projects_tasks,
    };

    serde_json::to_string(&output).map_err(|err| err.to_string())
}

fn todoist_list_projects(env_file: &str) -> Result<String, String> {
    load_env(env_file);
    let token = std::env::var("TODOIST_API_TOKEN")
        .map_err(|_| "TODOIST_API_TOKEN not found in environment (.env)".to_string())?;
    let client = build_client(&token)?;

    let projects: Vec<Project> =
        fetch_all_pages(&client, &format!("{}/projects", TODOIST_API_BASE))?;

    serde_json::to_string(&projects).map_err(|err| err.to_string())
}

fn todoist_complete_task(env_file: &str, id: &str) -> Result<(), String> {
    load_env(env_file);
    let token = std::env::var("TODOIST_API_TOKEN")
        .map_err(|_| "TODOIST_API_TOKEN not found in environment (.env)".to_string())?;
    let client = build_client(&token)?;

    client
        .post(&format!("{}/tasks/{}/close", TODOIST_API_BASE, id))
        .send()
        .map_err(|err| err.to_string())?
        .error_for_status()
        .map_err(|err| err.to_string())?;

    Ok(())
}

fn todoist_delete_task(env_file: &str, id: &str) -> Result<(), String> {
    load_env(env_file);
    let token = std::env::var("TODOIST_API_TOKEN")
        .map_err(|_| "TODOIST_API_TOKEN not found in environment (.env)".to_string())?;
    let client = build_client(&token)?;

    client
        .delete(&format!("{}/tasks/{}", TODOIST_API_BASE, id))
        .send()
        .map_err(|err| err.to_string())?
        .error_for_status()
        .map_err(|err| err.to_string())?;

    Ok(())
}

fn build_client(token: &str) -> Result<reqwest::blocking::Client, String> {
    let mut headers = reqwest::header::HeaderMap::new();
    let auth_value = format!("Bearer {}", token);
    headers.insert(
        reqwest::header::AUTHORIZATION,
        reqwest::header::HeaderValue::from_str(&auth_value).map_err(|err| err.to_string())?,
    );
    headers.insert(
        reqwest::header::CONTENT_TYPE,
        reqwest::header::HeaderValue::from_static("application/json"),
    );

    reqwest::blocking::Client::builder()
        .user_agent("qs-native-todoist")
        .default_headers(headers)
        .build()
        .map_err(|err| err.to_string())
}

fn parse_todoist_date(due: Option<&Due>) -> Result<Option<(DateTime<Utc>, bool)>, String> {
    let Some(due) = due else {
        return Ok(None);
    };
    let value = due.date.trim();

    if let Ok(dt) = DateTime::parse_from_rfc3339(value) {
        return Ok(Some((dt.with_timezone(&Utc), true)));
    }

    if let Ok(date_only) = NaiveDate::parse_from_str(value, "%Y-%m-%d") {
        let local_dt = Local
            .from_local_datetime(&date_only.and_hms_opt(0, 0, 0).unwrap())
            .unwrap();
        return Ok(Some((local_dt.with_timezone(&Utc), false)));
    }

    Err(format!("Unrecognised due date format: {}", value))
}

fn humanise(date_time: DateTime<Local>, has_time: bool) -> String {
    let today = Local::now().date_naive();
    let date = date_time.date_naive();

    if date == today {
        if has_time {
            return date_time.format("%-I:%M %p").to_string();
        }
        return "Today".to_string();
    }

    if date == today.succ_opt().unwrap() {
        if has_time {
            return format!("Tomorrow at {}", date_time.format("%-I:%M %p"));
        }
        return "Tomorrow".to_string();
    }

    if date == today.pred_opt().unwrap() {
        if has_time {
            return format!("Yesterday at {}", date_time.format("%-I:%M %p"));
        }
        return "Yesterday".to_string();
    }

    let date_str = date_time.format("%b %-d").to_string();
    if has_time {
        format!("{} at {}", date_str, date_time.format("%-I:%M %p"))
    } else {
        date_str
    }
}
