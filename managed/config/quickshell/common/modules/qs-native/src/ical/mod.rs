use chrono::{DateTime, Datelike, Local, NaiveDate, NaiveDateTime, NaiveTime, TimeZone, Utc};
use chrono_tz::Tz;
use cxx_qt::{CxxQtType, Threading};
use ical::IcalParser;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use std::io::BufReader;
use std::pin::Pin;
use std::time::Duration;

use crate::qobjects;
use crate::util::env::load_env;

impl qobjects::IcalCache {
    pub fn refresh_from_env(mut self: Pin<&mut Self>, env_file: &cxx_qt_lib::QString, days: i32) {
        let env_file = env_file.to_string();
        let days = days as i64;
        let qt_thread = self.qt_thread();
        let (meta_by_url, ics_by_url) = {
            let rust = self.as_mut().rust_mut();
            let rust = rust.get_mut();
            (rust.meta_by_url.clone(), rust.ics_by_url.clone())
        };

        std::thread::spawn(move || {
            let result = run_ical_refresh_with_state(env_file, days, meta_by_url, ics_by_url);
            qt_thread
                .queue(move |mut obj| match result {
                    Ok(output) => {
                        let rust = obj.as_mut().rust_mut();
                        let rust = rust.get_mut();
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
                        let error = format!("IcalCache error: {err}");
                        obj.as_mut().set_error(cxx_qt_lib::QString::from(error));
                        obj.as_mut().set_status(cxx_qt_lib::QString::from("error"));
                    }
                })
                .ok();
        });
    }
}

#[derive(Debug, Default, Deserialize, Serialize, Clone)]
pub(crate) struct CacheMeta {
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

fn parse_event(
    event: ical::parser::ical::component::IcalEvent,
) -> Result<Option<ParsedEvent>, String> {
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
                    start_dt
                        .date_naive()
                        .succ_opt()
                        .unwrap_or(start_dt.date_naive()),
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
            adjusted_end_exclusive = end_dt
                .date_naive()
                .succ_opt()
                .unwrap_or(end_dt.date_naive());
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

fn parse_ical_datetime(
    value: &str,
    tzid: Option<&str>,
    value_type: Option<&str>,
) -> Option<DateValue> {
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
