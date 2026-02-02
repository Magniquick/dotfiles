use chrono::{DateTime, Datelike, Local, NaiveDate, NaiveDateTime, NaiveTime, TimeZone, Utc};
use chrono_tz::Tz;
use ical::IcalParser;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use std::ffi::CString;
use std::fs;
use std::io::BufReader;
use std::path::Path;
use std::pin::Pin;
use std::process::Command;
use std::time::{Duration, Instant};
use cxx_qt::{CxxQtType, Threading};


#[cxx_qt::bridge]
mod qobjects {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, status)]
        #[qproperty(QString, generated_at)]
        #[qproperty(QString, error)]
        #[qproperty(QString, events_json)]
        #[namespace = "qs_native"]
        type IcalCache = super::IcalCacheRust;
    }

    impl cxx_qt::Threading for IcalCache {}

    extern "RustQt" {
        #[qinvokable]
        #[cxx_name = "refreshFromEnv"]
        fn refresh_from_env(self: Pin<&mut IcalCache>, env_file: &QString, days: i32);
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, data_json)]
        #[qproperty(QString, error)]
        #[qproperty(QString, last_updated)]
        #[namespace = "qs_native"]
        type TodoistClient = super::TodoistClientRust;
    }

    extern "RustQt" {
        #[qinvokable]
        #[cxx_name = "listTasks"]
        fn list_tasks(self: Pin<&mut TodoistClient>, env_file: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "listTasklists"]
        fn list_tasklists(self: Pin<&mut TodoistClient>, env_file: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "completeTask"]
        fn complete_task(self: Pin<&mut TodoistClient>, env_file: &QString, id: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "deleteTask"]
        fn delete_task(self: Pin<&mut TodoistClient>, env_file: &QString, id: &QString) -> bool;
    }

    impl cxx_qt::Threading for TodoistClient {}

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(f64, cpu)]
        #[qproperty(i32, mem)]
        #[qproperty(QString, mem_used)]
        #[qproperty(QString, mem_total)]
        #[qproperty(i32, disk)]
        #[qproperty(QString, disk_health)]
        #[qproperty(QString, disk_wear)]
        #[qproperty(f64, temp)]
        #[qproperty(QString, uptime)]
        #[qproperty(f64, psi_cpu_some)]
        #[qproperty(f64, psi_cpu_full)]
        #[qproperty(f64, psi_mem_some)]
        #[qproperty(f64, psi_mem_full)]
        #[qproperty(f64, psi_io_some)]
        #[qproperty(f64, psi_io_full)]
        #[qproperty(QString, disk_device)]
        #[qproperty(QString, error)]
        #[namespace = "qs_native"]
        type SysInfoProvider = super::SysInfoProviderRust;
    }

    extern "RustQt" {
        #[qinvokable]
        fn refresh(self: Pin<&mut SysInfoProvider>) -> bool;
    }

}

#[derive(Default)]
pub struct IcalCacheRust {
    status: cxx_qt_lib::QString,
    generated_at: cxx_qt_lib::QString,
    error: cxx_qt_lib::QString,
    events_json: cxx_qt_lib::QString,
    meta_by_url: HashMap<String, CacheMeta>,
    ics_by_url: HashMap<String, String>,
}

#[derive(Default)]
pub struct TodoistClientRust {
    data_json: cxx_qt_lib::QString,
    error: cxx_qt_lib::QString,
    last_updated: cxx_qt_lib::QString,
}

pub struct SysInfoProviderRust {
    cpu: f64,
    mem: i32,
    mem_used: cxx_qt_lib::QString,
    mem_total: cxx_qt_lib::QString,
    disk: i32,
    disk_health: cxx_qt_lib::QString,
    disk_wear: cxx_qt_lib::QString,
    temp: f64,
    uptime: cxx_qt_lib::QString,
    psi_cpu_some: f64,
    psi_cpu_full: f64,
    psi_mem_some: f64,
    psi_mem_full: f64,
    psi_io_some: f64,
    psi_io_full: f64,
    disk_device: cxx_qt_lib::QString,
    error: cxx_qt_lib::QString,
    last_cpu_total: u64,
    last_cpu_idle: u64,
    last_disk_health_at: Option<Instant>,
    disk_health_cache: String,
    disk_wear_cache: String,
}

impl Default for SysInfoProviderRust {
    fn default() -> Self {
        let device = default_disk_device();
        Self {
            cpu: 0.0,
            mem: 0,
            mem_used: cxx_qt_lib::QString::from("0.0GB"),
            mem_total: cxx_qt_lib::QString::from("0.0GB"),
            disk: 0,
            disk_health: cxx_qt_lib::QString::from(""),
            disk_wear: cxx_qt_lib::QString::from(""),
            temp: 0.0,
            uptime: cxx_qt_lib::QString::from(""),
            psi_cpu_some: 0.0,
            psi_cpu_full: 0.0,
            psi_mem_some: 0.0,
            psi_mem_full: 0.0,
            psi_io_some: 0.0,
            psi_io_full: 0.0,
            disk_device: cxx_qt_lib::QString::from(device),
            error: cxx_qt_lib::QString::from(""),
            last_cpu_total: 0,
            last_cpu_idle: 0,
            last_disk_health_at: None,
            disk_health_cache: String::new(),
            disk_wear_cache: String::new(),
        }
    }
}

impl qobjects::IcalCache {
    pub fn refresh_from_env(mut self: Pin<&mut Self>, env_file: &cxx_qt_lib::QString, days: i32) {
        let env_file = env_file.to_string();
        let days = days as i64;
        let qt_thread = self.qt_thread();
        let (meta_by_url, ics_by_url) = {
            let rust = self.as_mut().rust_mut();
            let rust = unsafe { rust.get_unchecked_mut() };
            (rust.meta_by_url.clone(), rust.ics_by_url.clone())
        };

        std::thread::spawn(move || {
            let result = run_ical_refresh_with_state(env_file, days, meta_by_url, ics_by_url);
            qt_thread
                .queue(move |mut obj| match result {
                    Ok(output) => {
                        let rust = obj.as_mut().rust_mut();
                        let rust = unsafe { rust.get_unchecked_mut() };
                        rust.meta_by_url = output.meta_by_url;
                        rust.ics_by_url = output.ics_by_url;
                        obj.as_mut()
                            .set_generated_at(cxx_qt_lib::QString::from(output.generated_at));
                        obj.as_mut()
                            .set_status(cxx_qt_lib::QString::from(output.status));
                        obj.as_mut()
                            .set_error(cxx_qt_lib::QString::from(output.error));
                        obj.as_mut()
                            .set_events_json(cxx_qt_lib::QString::from(output.events_json));
                    }
                    Err(err) => {
                        let error = format!("ical-cache error: {err}");
                        obj.as_mut()
                            .set_error(cxx_qt_lib::QString::from(error));
                        obj.as_mut().set_status(cxx_qt_lib::QString::from("error"));
                    }
                })
                .ok();
        });
    }
}

impl qobjects::SysInfoProvider {
    pub fn refresh(self: Pin<&mut Self>) -> bool {
        let mut this = self;
        let mut errors: Vec<String> = Vec::new();

        if let Err(err) = update_cpu_usage(this.as_mut()) {
            errors.push(err);
        }

        if let Err(err) = update_memory(this.as_mut()) {
            errors.push(err);
        }

        if let Err(err) = update_disk_usage(this.as_mut()) {
            errors.push(err);
        }

        if let Err(err) = update_temperature(this.as_mut()) {
            errors.push(err);
        }

        if let Err(err) = update_uptime(this.as_mut()) {
            errors.push(err);
        }

        if let Err(err) = update_psi(this.as_mut()) {
            errors.push(err);
        }

        if let Err(err) = update_disk_health(this.as_mut()) {
            errors.push(err);
        }

        if errors.is_empty() {
            this.as_mut().set_error(cxx_qt_lib::QString::from(""));
            true
        } else {
            this.as_mut()
                .set_error(cxx_qt_lib::QString::from(errors.join("; ")));
            false
        }
    }
}

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
                        obj.as_mut().set_last_updated(cxx_qt_lib::QString::from(
                            Local::now().to_rfc3339(),
                        ));
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
                        obj.as_mut().set_last_updated(cxx_qt_lib::QString::from(
                            Local::now().to_rfc3339(),
                        ));
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

#[derive(Debug, Default, Deserialize, Serialize, Clone)]
struct CacheMeta {
    etag: Option<String>,
    last_modified: Option<String>,
}

#[derive(Debug, Serialize, Clone, PartialEq)]
struct EventOut {
    uid: String,
    title: String,
    start: String,
    end: String,
    all_day: bool,
}

#[derive(Debug, Serialize)]
struct OutputPayload {
    #[serde(rename = "generatedAt")]
    generated_at: String,
    status: String,
    error: Option<String>,
    #[serde(rename = "eventsByDay")]
    events_by_day: BTreeMap<String, Vec<EventOut>>,
}

struct IcalRefreshOutput {
    generated_at: String,
    status: String,
    error: String,
    events_json: String,
    meta_by_url: HashMap<String, CacheMeta>,
    ics_by_url: HashMap<String, String>,
}

#[derive(Debug)]
struct ParsedEvent {
    event: EventOut,
    start_date: NaiveDate,
    end_date_exclusive: NaiveDate,
}

fn run_ical_refresh_with_state(
    env_file: String,
    days: i64,
    mut meta_by_url: HashMap<String, CacheMeta>,
    mut ics_by_url: HashMap<String, String>,
) -> Result<IcalRefreshOutput, String> {
    load_env(&env_file);
    let urls = resolve_urls()?;
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(20))
        .build()
        .map_err(|err| err.to_string())?;

    let mut all_events: Vec<ParsedEvent> = Vec::new();
    let mut aggregate_status = "fetched".to_string();
    let mut errors: Vec<String> = Vec::new();
    let mut success_count = 0;

    for url in &urls {
        let fetch_status = fetch_calendar(&client, url, &mut meta_by_url, &mut ics_by_url);

        match fetch_status {
            Ok(status) => {
                if status.status.starts_with("error") {
                    errors.push(format!(
                        "Error fetching {}: {} ({})",
                        url,
                        status.status,
                        status.error.clone().unwrap_or_default()
                    ));
                    if aggregate_status == "fetched" {
                        aggregate_status = status.status;
                    }
                } else {
                    success_count += 1;
                }

                if let Some(contents) = ics_by_url.get(url) {
                    match parse_calendar(contents) {
                        Ok(mut parsed_events) => {
                            all_events.append(&mut parsed_events);
                        }
                        Err(err) => {
                            errors.push(format!("Error parsing {}: {}", url, err));
                        }
                    }
                }
            }
            Err(err) => {
                errors.push(format!("Fatal error fetching {}: {}", url, err));
                aggregate_status = "error".to_string();
            }
        }
    }

    if success_count > 0 && !errors.is_empty() {
        aggregate_status = "partial_success".to_string();
    } else if success_count == 0 && !errors.is_empty() {
        aggregate_status = "error".to_string();
    }

    let final_error = if errors.is_empty() {
        None
    } else {
        Some(errors.join("; "))
    };

    let events_by_day = organize_events(all_events, days);

    let payload = OutputPayload {
        generated_at: Local::now().to_rfc3339(),
        status: aggregate_status.clone(),
        error: final_error.clone(),
        events_by_day,
    };

    let json = serde_json::to_string(&payload).map_err(|err| err.to_string())?;

    Ok(IcalRefreshOutput {
        generated_at: payload.generated_at,
        status: aggregate_status,
        error: final_error.unwrap_or_default(),
        events_json: json,
        meta_by_url,
        ics_by_url,
    })
}

struct FetchStatus {
    status: String,
    error: Option<String>,
}

fn fetch_calendar(
    client: &reqwest::blocking::Client,
    url: &str,
    meta_by_url: &mut HashMap<String, CacheMeta>,
    ics_by_url: &mut HashMap<String, String>,
) -> Result<FetchStatus, String> {
    let meta = meta_by_url.entry(url.to_string()).or_default();
    let mut request = client.get(url);

    if let Some(etag) = meta.etag.as_ref() {
        request = request.header(reqwest::header::IF_NONE_MATCH, etag);
    }
    if let Some(last_modified) = meta.last_modified.as_ref() {
        request = request.header(reqwest::header::IF_MODIFIED_SINCE, last_modified);
    }

    let response = request.send().map_err(|err| err.to_string())?;
    let status = response.status();
    if status == reqwest::StatusCode::NOT_MODIFIED {
        return Ok(FetchStatus {
            status: "not_modified".to_string(),
            error: None,
        });
    }
    if !status.is_success() {
        let error = format!("HTTP {}", status.as_u16());
        if ics_by_url.contains_key(url) {
            return Ok(FetchStatus {
                status: "error_cached".to_string(),
                error: Some(error),
            });
        }
        return Err(error);
    }

    let etag = response
        .headers()
        .get("ETag")
        .and_then(|value| value.to_str().ok())
        .map(|value| value.to_string());
    let last_modified = response
        .headers()
        .get("Last-Modified")
        .and_then(|value| value.to_str().ok())
        .map(|value| value.to_string());

    let mut body = response.text().map_err(|err| err.to_string())?;
    if !body.contains("BEGIN:VCALENDAR") {
        let message = "Invalid ICS response".to_string();
        if ics_by_url.contains_key(url) {
            return Ok(FetchStatus {
                status: "error_cached".to_string(),
                error: Some(message),
            });
        }
        return Err(message);
    }

    body = body.replace("\r\n", "\n");
    meta.etag = etag;
    meta.last_modified = last_modified;
    ics_by_url.insert(url.to_string(), body);

    Ok(FetchStatus {
        status: "fetched".to_string(),
        error: None,
    })
}

fn parse_calendar(contents: &str) -> Result<Vec<ParsedEvent>, String> {
    let reader = BufReader::new(contents.as_bytes());
    let parser = IcalParser::new(reader);

    let mut events: Vec<ParsedEvent> = Vec::new();

    for calendar in parser {
        let calendar = calendar.map_err(|err| err.to_string())?;
        for event in calendar.events {
            if let Some(parsed) = parse_event(event)? {
                events.push(parsed);
            }
        }
    }

    Ok(events)
}

fn organize_events(events: Vec<ParsedEvent>, days: i64) -> BTreeMap<String, Vec<EventOut>> {
    let today = Local::now().date_naive();
    let range_start = NaiveDate::from_ymd_opt(today.year(), today.month(), 1).unwrap_or(today);
    let range_end = range_start + chrono::Duration::days(days);

    let mut events_by_day: BTreeMap<String, Vec<EventOut>> = BTreeMap::new();

    for parsed in events {
        let mut date = parsed.start_date;
        while date < parsed.end_date_exclusive {
            if date >= range_start && date <= range_end {
                let key = format!("{:04}-{:02}-{:02}", date.year(), date.month(), date.day());
                events_by_day
                    .entry(key)
                    .or_insert_with(Vec::new)
                    .push(parsed.event.clone());
            }
            date = date.succ_opt().unwrap_or(date);
        }
    }

    for events in events_by_day.values_mut() {
        events.sort_by_key(|event| event_sort_ts(event));
    }

    events_by_day
}

fn parse_event(event: ical::parser::ical::component::IcalEvent) -> Result<Option<ParsedEvent>, String> {
    let mut summary = None;
    let mut uid = None;
    let mut dtstart_value = None;
    let mut dtstart_tzid = None;
    let mut dtstart_type = None;
    let mut dtend_value = None;
    let mut dtend_tzid = None;
    let mut dtend_type = None;

    for prop in event.properties {
        let name = prop.name.to_uppercase();
        match name.as_str() {
            "SUMMARY" => summary = prop.value.map(unescape_ical),
            "UID" => uid = prop.value,
            "DTSTART" => {
                dtstart_value = prop.value;
                dtstart_tzid = prop
                    .params
                    .as_ref()
                    .and_then(|params| param_value(params, "TZID"));
                dtstart_type = prop
                    .params
                    .as_ref()
                    .and_then(|params| param_value(params, "VALUE"));
            }
            "DTEND" => {
                dtend_value = prop.value;
                dtend_tzid = prop
                    .params
                    .as_ref()
                    .and_then(|params| param_value(params, "TZID"));
                dtend_type = prop
                    .params
                    .as_ref()
                    .and_then(|params| param_value(params, "VALUE"));
            }
            _ => {}
        }
    }

    let summary = summary.unwrap_or_else(|| "Untitled".to_string());
    let uid = uid.unwrap_or_else(|| format!("{}-{}", summary, Local::now().timestamp()));
    let start = match dtstart_value.as_deref() {
        Some(value) => parse_ical_datetime(value, dtstart_tzid.as_deref(), dtstart_type.as_deref())
            .ok_or("Missing DTSTART")?,
        None => return Ok(None),
    };

    let end = match dtend_value.as_deref() {
        Some(value) => parse_ical_datetime(value, dtend_tzid.as_deref(), dtend_type.as_deref()),
        None => None,
    };

    let (all_day, start_date, start_dt) = match start {
        DateValue::Date(date) => (true, date, None),
        DateValue::DateTime(dt) => (false, dt.date_naive(), Some(dt)),
    };

    let (end_date_exclusive, end_dt) = match end {
        Some(DateValue::Date(date)) => (date, None),
        Some(DateValue::DateTime(dt)) => (dt.date_naive(), Some(dt)),
        None => {
            if all_day {
                (start_date.succ_opt().ok_or("Invalid date")?, None)
            } else if let Some(start_dt) = start_dt {
                (
                    start_dt.date_naive().succ_opt().unwrap_or(start_dt.date_naive()),
                    Some(start_dt),
                )
            } else {
                (start_date.succ_opt().ok_or("Invalid date")?, None)
            }
        }
    };

    let mut adjusted_end_exclusive = end_date_exclusive;
    if let Some(end_dt) = end_dt {
        if end_dt.time() == NaiveTime::from_hms_opt(0, 0, 0).unwrap()
            && end_dt.date_naive() > start_date
        {
            adjusted_end_exclusive = end_dt.date_naive();
        } else {
            adjusted_end_exclusive = end_dt.date_naive().succ_opt().unwrap_or(end_dt.date_naive());
        }
    }

    let start_iso = if let Some(start_dt) = start_dt {
        start_dt.to_rfc3339()
    } else {
        let start_dt = Local
            .from_local_datetime(&start_date.and_hms_opt(0, 0, 0).unwrap())
            .single()
            .unwrap_or_else(|| Local.from_utc_datetime(&start_date.and_hms_opt(0, 0, 0).unwrap()));
        start_dt.to_rfc3339()
    };

    let end_iso = if let Some(end_dt) = end_dt {
        end_dt.to_rfc3339()
    } else {
        let end_date = adjusted_end_exclusive;
        let end_dt = Local
            .from_local_datetime(&end_date.and_hms_opt(0, 0, 0).unwrap())
            .single()
            .unwrap_or_else(|| Local.from_utc_datetime(&end_date.and_hms_opt(0, 0, 0).unwrap()));
        end_dt.to_rfc3339()
    };

    let event = EventOut {
        uid,
        title: summary,
        start: start_iso,
        end: end_iso,
        all_day,
    };

    Ok(Some(ParsedEvent {
        event,
        start_date,
        end_date_exclusive: adjusted_end_exclusive,
    }))
}

fn event_sort_ts(event: &EventOut) -> i64 {
    if let Ok(parsed) = DateTime::parse_from_rfc3339(&event.start) {
        parsed.timestamp()
    } else {
        0
    }
}

enum DateValue {
    Date(NaiveDate),
    DateTime(DateTime<Local>),
}

fn parse_ical_datetime(value: &str, tzid: Option<&str>, value_type: Option<&str>) -> Option<DateValue> {
    let value_type = value_type.unwrap_or("");
    if value_type.eq_ignore_ascii_case("DATE") || (value.len() == 8 && !value.contains('T')) {
        let date = NaiveDate::parse_from_str(value, "%Y%m%d").ok()?;
        return Some(DateValue::Date(date));
    }

    if value.ends_with('Z') {
        let value = value.trim_end_matches('Z');
        let dt = parse_naive_datetime(value)?;
        let utc_dt = Utc.from_utc_datetime(&dt);
        return Some(DateValue::DateTime(utc_dt.with_timezone(&Local)));
    }

    if let Some(tzid) = tzid {
        if let Ok(tz) = tzid.parse::<Tz>() {
            let dt = parse_naive_datetime(value)?;
            let local_dt = match tz.from_local_datetime(&dt) {
                chrono::LocalResult::Single(dt) => dt,
                chrono::LocalResult::Ambiguous(a, _) => a,
                chrono::LocalResult::None => tz.from_utc_datetime(&dt),
            };
            return Some(DateValue::DateTime(local_dt.with_timezone(&Local)));
        }
    }

    let dt = parse_naive_datetime(value)?;
    let local_dt = match Local.from_local_datetime(&dt) {
        chrono::LocalResult::Single(dt) => dt,
        chrono::LocalResult::Ambiguous(a, _) => a,
        chrono::LocalResult::None => Local.from_utc_datetime(&dt),
    };
    Some(DateValue::DateTime(local_dt))
}

fn parse_naive_datetime(value: &str) -> Option<NaiveDateTime> {
    NaiveDateTime::parse_from_str(value, "%Y%m%dT%H%M%S")
        .or_else(|_| NaiveDateTime::parse_from_str(value, "%Y%m%dT%H%M"))
        .ok()
}

fn param_value(params: &Vec<(String, Vec<String>)>, key: &str) -> Option<String> {
    for (name, values) in params {
        if name.eq_ignore_ascii_case(key) {
            return values.first().cloned();
        }
    }
    None
}

fn unescape_ical(value: String) -> String {
    value
        .replace("\\\\", "\\")
        .replace("\\n", "\n")
        .replace("\\,", ",")
        .replace("\\;", ";")
}

fn resolve_urls() -> Result<Vec<String>, String> {
    let mut all_urls = Vec::new();

    if let Ok(env_urls) = std::env::var("CALENDAR_ICAL_URL") {
        for url in env_urls.split(',') {
            if !url.trim().is_empty() {
                all_urls.push(url.trim().to_string());
            }
        }
    }

    if all_urls.is_empty() {
        return Err("Missing calendar URL. Provide CALENDAR_ICAL_URL in .env.".to_string());
    }

    Ok(all_urls)
}

fn load_env(env_file: &str) {
    if !env_file.trim().is_empty() {
        let _ = dotenvy::from_filename(env_file);
    } else {
        let _ = dotenvy::dotenv();
    }
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

fn todoist_list_tasks(env_file: &str) -> Result<String, String> {
    load_env(env_file);
    let token = std::env::var("TODOIST_API_TOKEN")
        .map_err(|_| "TODOIST_API_TOKEN not found in environment (.env)".to_string())?;
    let client = build_client(&token)?;

    let tasks: Vec<Task> = client
        .get("https://api.todoist.com/rest/v2/tasks")
        .send()
        .map_err(|err| err.to_string())?
        .error_for_status()
        .map_err(|err| err.to_string())?
        .json()
        .map_err(|err| err.to_string())?;

    let projects: Vec<Project> = client
        .get("https://api.todoist.com/rest/v2/projects")
        .send()
        .map_err(|err| err.to_string())?
        .error_for_status()
        .map_err(|err| err.to_string())?
        .json()
        .map_err(|err| err.to_string())?;

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

    let projects: Vec<Project> = client
        .get("https://api.todoist.com/rest/v2/projects")
        .send()
        .map_err(|err| err.to_string())?
        .error_for_status()
        .map_err(|err| err.to_string())?
        .json()
        .map_err(|err| err.to_string())?;

    serde_json::to_string(&projects).map_err(|err| err.to_string())
}

fn todoist_complete_task(env_file: &str, id: &str) -> Result<(), String> {
    load_env(env_file);
    let token = std::env::var("TODOIST_API_TOKEN")
        .map_err(|_| "TODOIST_API_TOKEN not found in environment (.env)".to_string())?;
    let client = build_client(&token)?;

    client
        .post(&format!("https://api.todoist.com/rest/v2/tasks/{}/close", id))
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
        .delete(&format!("https://api.todoist.com/rest/v2/tasks/{}", id))
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

fn default_disk_device() -> String {
    let candidates = ["/dev/nvme0", "/dev/nvme0n1", "/dev/sda", "/dev/vda"];
    for candidate in candidates {
        if Path::new(candidate).exists() {
            return candidate.to_string();
        }
    }
    "/dev/nvme0".to_string()
}

fn update_cpu_usage(mut obj: Pin<&mut qobjects::SysInfoProvider>) -> Result<(), String> {
    let (total, idle) = read_cpu_totals()?;
    let (prev_total, prev_idle) = {
        let rust = obj.as_mut().rust_mut();
        let rust = unsafe { rust.get_unchecked_mut() };
        (rust.last_cpu_total, rust.last_cpu_idle)
    };

    if prev_total != 0 && total > prev_total {
        let dt = total - prev_total;
        let didle = idle.saturating_sub(prev_idle);
        let usage = if dt == 0 {
            0.0
        } else {
            100.0 * (1.0 - (didle as f64 / dt as f64))
        };
        obj.as_mut().set_cpu(usage);
    }

    let rust = obj.as_mut().rust_mut();
    let rust = unsafe { rust.get_unchecked_mut() };
    rust.last_cpu_total = total;
    rust.last_cpu_idle = idle;
    Ok(())
}

fn read_cpu_totals() -> Result<(u64, u64), String> {
    let content = fs::read_to_string("/proc/stat").map_err(|err| err.to_string())?;
    let mut lines = content.lines();
    let line = lines.next().ok_or("Missing /proc/stat cpu line")?;
    let mut parts = line.split_whitespace();
    if parts.next() != Some("cpu") {
        return Err("Malformed /proc/stat cpu line".to_string());
    }

    let mut values: Vec<u64> = Vec::new();
    for part in parts {
        if let Ok(value) = part.parse::<u64>() {
            values.push(value);
        }
    }
    if values.len() < 4 {
        return Err("Not enough cpu counters".to_string());
    }

    let idle = values.get(3).copied().unwrap_or(0) + values.get(4).copied().unwrap_or(0);
    let total: u64 = values.iter().sum();
    Ok((total, idle))
}

fn update_memory(mut obj: Pin<&mut qobjects::SysInfoProvider>) -> Result<(), String> {
    let (total_kb, available_kb) = read_meminfo()?;
    if total_kb == 0 {
        return Err("MemTotal is zero".to_string());
    }

    let used_kb = total_kb.saturating_sub(available_kb);
    let mem_pct = ((used_kb as f64 / total_kb as f64) * 100.0).round() as i32;
    let used_gb = used_kb as f64 / 1024.0 / 1024.0;
    let total_gb = total_kb as f64 / 1024.0 / 1024.0;

    obj.as_mut().set_mem(mem_pct);
    obj.as_mut()
        .set_mem_used(cxx_qt_lib::QString::from(format!("{:.1}GB", used_gb)));
    obj.as_mut()
        .set_mem_total(cxx_qt_lib::QString::from(format!("{:.1}GB", total_gb)));
    Ok(())
}

fn read_meminfo() -> Result<(u64, u64), String> {
    let content = fs::read_to_string("/proc/meminfo").map_err(|err| err.to_string())?;
    let mut total_kb = 0;
    let mut available_kb = 0;
    for line in content.lines() {
        if line.starts_with("MemTotal:") {
            total_kb = line
                .split_whitespace()
                .nth(1)
                .and_then(|v| v.parse::<u64>().ok())
                .unwrap_or(0);
        } else if line.starts_with("MemAvailable:") {
            available_kb = line
                .split_whitespace()
                .nth(1)
                .and_then(|v| v.parse::<u64>().ok())
                .unwrap_or(0);
        }
    }
    Ok((total_kb, available_kb))
}

fn update_disk_usage(mut obj: Pin<&mut qobjects::SysInfoProvider>) -> Result<(), String> {
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    let path = CString::new("/").map_err(|err| err.to_string())?;
    let ret = unsafe { libc::statvfs(path.as_ptr(), &mut stat) };
    if ret != 0 {
        return Err(format!("statvfs failed: {}", std::io::Error::last_os_error()));
    }
    let total = stat.f_blocks as f64 * stat.f_frsize as f64;
    let avail = stat.f_bavail as f64 * stat.f_frsize as f64;
    let used = (total - avail).max(0.0);
    let pct = if total > 0.0 { (used / total) * 100.0 } else { 0.0 };
    obj.as_mut().set_disk(pct.round() as i32);
    Ok(())
}

fn update_temperature(mut obj: Pin<&mut qobjects::SysInfoProvider>) -> Result<(), String> {
    let thermal_path = Path::new("/sys/class/thermal");
    let mut temp_c = None;
    if let Ok(entries) = fs::read_dir(thermal_path) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            if !name.to_string_lossy().starts_with("thermal_zone") {
                continue;
            }
            let temp_path = entry.path().join("temp");
            if let Ok(contents) = fs::read_to_string(&temp_path) {
                if let Ok(value) = contents.trim().parse::<f64>() {
                    temp_c = Some(value / 1000.0);
                    break;
                }
            }
        }
    }

    obj.as_mut().set_temp(temp_c.unwrap_or(0.0));
    Ok(())
}

fn update_uptime(mut obj: Pin<&mut qobjects::SysInfoProvider>) -> Result<(), String> {
    let content = fs::read_to_string("/proc/uptime").map_err(|err| err.to_string())?;
    let secs = content
        .split_whitespace()
        .next()
        .and_then(|v| v.parse::<f64>().ok())
        .unwrap_or(0.0);
    let uptime = format_uptime(secs as u64);
    obj.as_mut()
        .set_uptime(cxx_qt_lib::QString::from(uptime));
    Ok(())
}

fn format_uptime(total_seconds: u64) -> String {
    let mut remaining = total_seconds;
    let days = remaining / 86400;
    remaining %= 86400;
    let hours = remaining / 3600;
    remaining %= 3600;
    let minutes = remaining / 60;

    let mut parts = Vec::new();
    if days > 0 {
        parts.push(format!("{} {}", days, if days == 1 { "day" } else { "days" }));
    }
    if hours > 0 {
        parts.push(format!(
            "{} {}",
            hours,
            if hours == 1 { "hour" } else { "hours" }
        ));
    }
    if minutes > 0 || parts.is_empty() {
        parts.push(format!(
            "{} {}",
            minutes,
            if minutes == 1 { "minute" } else { "minutes" }
        ));
    }
    parts.join(", ")
}

fn update_psi(mut obj: Pin<&mut qobjects::SysInfoProvider>) -> Result<(), String> {
    let (cpu_some, cpu_full) = read_psi("/proc/pressure/cpu");
    let (mem_some, mem_full) = read_psi("/proc/pressure/memory");
    let (io_some, io_full) = read_psi("/proc/pressure/io");

    obj.as_mut().set_psi_cpu_some(cpu_some);
    obj.as_mut().set_psi_cpu_full(cpu_full);
    obj.as_mut().set_psi_mem_some(mem_some);
    obj.as_mut().set_psi_mem_full(mem_full);
    obj.as_mut().set_psi_io_some(io_some);
    obj.as_mut().set_psi_io_full(io_full);
    Ok(())
}

fn read_psi(path: &str) -> (f64, f64) {
    let Ok(contents) = fs::read_to_string(path) else {
        return (0.0, 0.0);
    };
    let mut some = 0.0;
    let mut full = 0.0;
    for line in contents.lines() {
        if line.starts_with("some") {
            some = parse_psi_avg10(line);
        } else if line.starts_with("full") {
            full = parse_psi_avg10(line);
        }
    }
    (some, full)
}

fn parse_psi_avg10(line: &str) -> f64 {
    for part in line.split_whitespace() {
        if let Some(value) = part.strip_prefix("avg10=") {
            return value.parse::<f64>().unwrap_or(0.0);
        }
    }
    0.0
}

fn update_disk_health(mut obj: Pin<&mut qobjects::SysInfoProvider>) -> Result<(), String> {
    let device = obj.as_ref().disk_device().to_string();
    let device = if device.trim().is_empty() {
        default_disk_device()
    } else {
        device
    };

    let now = Instant::now();
    let cache_ttl = Duration::from_secs(6 * 60 * 60);

    let (needs_refresh, cached_health, cached_wear) = {
        let rust = obj.as_mut().rust_mut();
        let rust = unsafe { rust.get_unchecked_mut() };
        let needs_refresh = rust
            .last_disk_health_at
            .map(|ts| now.duration_since(ts) > cache_ttl)
            .unwrap_or(true)
            || rust.disk_health_cache.is_empty();
        (
            needs_refresh,
            rust.disk_health_cache.clone(),
            rust.disk_wear_cache.clone(),
        )
    };

    if needs_refresh {
        let (health, wear) = read_disk_health(&device);
        let rust = obj.as_mut().rust_mut();
        let rust = unsafe { rust.get_unchecked_mut() };
        rust.disk_health_cache = health.clone();
        rust.disk_wear_cache = wear.clone();
        rust.last_disk_health_at = Some(now);
        obj.as_mut()
            .set_disk_health(cxx_qt_lib::QString::from(health));
        obj.as_mut()
            .set_disk_wear(cxx_qt_lib::QString::from(wear));
    } else {
        obj.as_mut()
            .set_disk_health(cxx_qt_lib::QString::from(cached_health));
        obj.as_mut()
            .set_disk_wear(cxx_qt_lib::QString::from(cached_wear));
    }
    Ok(())
}

fn read_disk_health(device: &str) -> (String, String) {
    let attrs = run_smartctl(&["--attributes", device]);
    let health = run_smartctl(&["--health", "--tolerance=conservative", device]);

    if attrs.is_none() && health.is_none() {
        return ("Unknown (smartctl missing)".to_string(), "Unknown".to_string());
    }

    let attrs_output = attrs.unwrap_or_default();
    let critical_warning = parse_smartctl_value(&attrs_output, "Critical Warning:")
        .unwrap_or_else(|| "unknown".to_string());
    let wear = parse_smartctl_value(&attrs_output, "Percentage Used:")
        .unwrap_or_else(|| "Unknown".to_string());

    let mut health_result = "unknown".to_string();
    if let Some(health_output) = health {
        if let Some(value) = parse_smartctl_value(&health_output, "result") {
            health_result = value;
        } else if let Some(value) = parse_smartctl_value(&health_output, "SMART Health Status:") {
            health_result = value;
        }
    }

    let health = if critical_warning == "0x00" && health_result == "PASSED" {
        "Healthy".to_string()
    } else if health_result != "unknown" {
        format!("{} ({})", health_result, critical_warning)
    } else {
        format!("Unknown ({})", critical_warning)
    };

    (health, wear)
}

fn run_smartctl(args: &[&str]) -> Option<String> {
    let output = Command::new("smartctl").args(args).output().ok();
    if let Some(out) = output {
        if out.status.success() {
            return Some(String::from_utf8_lossy(&out.stdout).to_string());
        }
    }

    let output = Command::new("sudo")
        .arg("-n")
        .arg("smartctl")
        .args(args)
        .output()
        .ok();

    if let Some(out) = output {
        if out.status.success() {
            return Some(String::from_utf8_lossy(&out.stdout).to_string());
        }
    }
    None
}

fn parse_smartctl_value(output: &str, needle: &str) -> Option<String> {
    for line in output.lines() {
        if line.contains(needle) {
            if let Some(value) = line.splitn(2, needle).nth(1) {
                return Some(value.trim().trim_matches(':').trim().to_string());
            }
        }
    }
    None
}
