use std::collections::HashMap;
use std::env;
use std::path::PathBuf;
use std::process::exit;

use chrono::{DateTime, Local, NaiveDate, TimeZone, Utc};
use clap::{Parser, Subcommand};
use dotenvy::{dotenv, from_path};
use reqwest::blocking::Client;
use reqwest::header::{HeaderMap, HeaderValue, AUTHORIZATION, CONTENT_TYPE};
use serde::{Deserialize, Serialize};

#[derive(Parser)]
#[command(name = "todoist-api", about = "Todoist CLI wrapper")] 
struct Cli {
    /// Path to a .env file to load
    #[arg(long = "env-file", value_name = "PATH")]
    env_file: Option<PathBuf>,
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand)]
enum Command {
    /// List pending tasks (default)
    List,
    /// List projects
    #[command(name = "list-tasklists")]
    ListTasklists,
    /// Mark a task as completed
    Complete { id: String },
    /// Delete a task
    Delete { id: String },
}

#[derive(Deserialize, Debug)]
struct Task {
    id: String,
    content: String,
    description: Option<String>,
    project_id: String,
    created_at: DateTime<Utc>,
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

#[derive(Serialize)]
struct StatusOutput {
    id: String,
    status: &'static str,
}

fn main() {
    if let Err(err) = run() {
        eprintln!("{}", err);
        println!("{}", serde_json::json!({"error": err.to_string()}));
        exit(1);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();
    if let Some(env_path) = &cli.env_file {
        from_path(env_path)
            .map_err(|err| format!("Failed to load env file {}: {}", env_path.display(), err))?;
    } else {
        dotenv().ok();
    }
    let token = env::var("TODOIST_API_TOKEN").map_err(|_| "TODOIST_API_TOKEN not found in environment (.env)".to_string())?;
    let client = build_client(&token)?;

    let command = cli.command.unwrap_or(Command::List);
    match command {
        Command::List => {
            let output = list_tasks(&client)?;
            println!("{}", serde_json::to_string(&output)?);
        }
        Command::ListTasklists => {
            let projects = list_projects(&client)?;
            println!("{}", serde_json::to_string(&projects)?);
        }
        Command::Complete { id } => {
            let result = complete_task(&client, &id)?;
            println!("{}", serde_json::to_string(&result)?);
        }
        Command::Delete { id } => {
            let result = delete_task(&client, &id)?;
            println!("{}", serde_json::to_string(&result)?);
        }
    }

    Ok(())
}

fn build_client(token: &str) -> Result<Client, reqwest::Error> {
    let mut headers = HeaderMap::new();
    let auth_value = format!("Bearer {}", token);
    headers.insert(AUTHORIZATION, HeaderValue::from_str(&auth_value).unwrap());
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));

    Client::builder()
        .user_agent("todoist-api-cli")
        .default_headers(headers)
        .build()
}

fn list_tasks(client: &Client) -> Result<ListOutput, Box<dyn std::error::Error>> {
    let tasks: Vec<Task> = client
        .get("https://api.todoist.com/rest/v2/tasks")
        .send()?
        .error_for_status()?
        .json()?;

    let projects: Vec<Project> = client
        .get("https://api.todoist.com/rest/v2/projects")
        .send()?
        .error_for_status()?
        .json()?;

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
                    updated: task.created_at.timestamp(),
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
                updated: task.created_at.timestamp(),
            });
    }

    today_tasks.sort_by_key(|t| (t.due, t.updated));
    for tasks in projects_tasks.values_mut() {
        tasks.sort_by_key(|t| t.updated);
    }

    Ok(ListOutput {
        today: today_tasks,
        projects: projects_tasks,
    })
}

fn list_projects(client: &Client) -> Result<Vec<Project>, Box<dyn std::error::Error>> {
    let projects: Vec<Project> = client
        .get("https://api.todoist.com/rest/v2/projects")
        .send()?
        .error_for_status()?
        .json()?;
    Ok(projects)
}

fn complete_task(client: &Client, id: &str) -> Result<StatusOutput, Box<dyn std::error::Error>> {
    client
        .post(&format!("https://api.todoist.com/rest/v2/tasks/{}/close", id))
        .send()?
        .error_for_status()?;

    Ok(StatusOutput { id: id.to_string(), status: "completed" })
}

fn delete_task(client: &Client, id: &str) -> Result<StatusOutput, Box<dyn std::error::Error>> {
    client
        .delete(&format!("https://api.todoist.com/rest/v2/tasks/{}", id))
        .send()?
        .error_for_status()?;

    Ok(StatusOutput { id: id.to_string(), status: "deleted" })
}

fn parse_todoist_date(due: Option<&Due>) -> Result<Option<(DateTime<Utc>, bool)>, Box<dyn std::error::Error>> {
    let Some(due) = due else { return Ok(None); };
    let value = due.date.trim();

    if let Ok(dt) = DateTime::parse_from_rfc3339(value) {
        return Ok(Some((dt.with_timezone(&Utc), true)));
    }

    if let Ok(date_only) = NaiveDate::parse_from_str(value, "%Y-%m-%d") {
        let local_dt = Local.from_local_datetime(&date_only.and_hms_opt(0, 0, 0).unwrap()).unwrap();
        return Ok(Some((local_dt.with_timezone(&Utc), false)));
    }

    Err(format!("Unrecognised due date format: {}", value).into())
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_rfc3339_due_with_time() {
        let due = Due { date: "2024-08-20T10:30:00Z".to_string() };
        let parsed = parse_todoist_date(Some(&due)).unwrap().unwrap();
        assert!(parsed.1); // has time
        assert_eq!(parsed.0, DateTime::parse_from_rfc3339("2024-08-20T10:30:00Z").unwrap().with_timezone(&Utc));
    }

    #[test]
    fn parses_date_only_due() {
        let due = Due { date: "2024-08-20".to_string() };
        let parsed = parse_todoist_date(Some(&due)).unwrap().unwrap();
        assert!(!parsed.1);
        let expected = Local
            .from_local_datetime(&NaiveDate::from_ymd_opt(2024, 8, 20).unwrap().and_hms_opt(0, 0, 0).unwrap())
            .unwrap()
            .with_timezone(&Utc);
        assert_eq!(parsed.0, expected);
    }

    #[test]
    fn humanises_relative_dates() {
        let now = Local::now();
        let today = now.with_hour(9).unwrap();
        assert_eq!(humanise(today, true), today.format("%-I:%M %p").to_string());
        assert_eq!(humanise(today, false), "Today");

        let tomorrow = today + chrono::Duration::days(1);
        assert!(humanise(tomorrow, true).starts_with("Tomorrow at "));
        assert_eq!(humanise(tomorrow, false), "Tomorrow");

        let yesterday = today - chrono::Duration::days(1);
        assert!(humanise(yesterday, true).starts_with("Yesterday at "));
        assert_eq!(humanise(yesterday, false), "Yesterday");
    }

    #[test]
    fn humanises_future_dates() {
        let date = Local
            .from_local_datetime(&NaiveDate::from_ymd_opt(2024, 12, 25).unwrap().and_hms_opt(15, 45, 0).unwrap())
            .unwrap();
        assert_eq!(humanise(date, false), "Dec 25");
        assert_eq!(humanise(date, true), format!("Dec 25 at {}", date.format("%-I:%M %p")));
    }
}
