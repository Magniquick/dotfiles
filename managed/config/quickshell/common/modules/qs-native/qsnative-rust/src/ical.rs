use core::pin::Pin;
use std::collections::HashMap;
use std::thread;

use chrono::{DateTime, Datelike, Duration, Local, NaiveDate, NaiveTime, TimeZone, Utc};
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use google_calendar3 as calendar3;
use serde::Serialize;

use crate::app_config::{self, CalendarSource};
use crate::google_auth;

#[derive(Default)]
pub struct IcalCacheRust {
    events_json: QString,
    generated_at: QString,
    status: QString,
    error: QString,
}

#[derive(Debug, Serialize, Clone)]
struct EventOut {
    uid: String,
    title: String,
    start: String,
    end: String,
    all_day: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct Output {
    generated_at: String,
    status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
    events_by_day: HashMap<String, Vec<EventOut>>,
}

#[derive(Debug)]
struct ParsedEvent {
    event: EventOut,
    start_date: DateTime<Local>,
    end_date_exclusive: DateTime<Local>,
}

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    impl cxx_qt::Threading for IcalCache {}

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qobject]
        #[qproperty(QString, events_json, cxx_name = "events_json")]
        #[qproperty(QString, generated_at, cxx_name = "generated_at")]
        #[qproperty(QString, status)]
        #[qproperty(QString, error)]
        type IcalCache = super::IcalCacheRust;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qinvokable]
        fn refresh(self: Pin<&mut IcalCache>, days: i32) -> bool;
    }

    impl cxx_qt::Initialize for IcalCache {}
}

impl cxx_qt::Initialize for ffi::IcalCache {
    fn initialize(self: Pin<&mut Self>) {
        crate::install_panic_hook();
    }
}

impl ffi::IcalCache {
    pub fn refresh(self: Pin<&mut Self>, days: i32) -> bool {
        let qt_thread = self.as_ref().qt_thread();
        thread::spawn(move || {
            let result = refresh(days);
            let _ = qt_thread.queue(move |mut cache| {
                cache.as_mut().apply_refresh_json(result);
            });
        });
        true
    }

    fn apply_refresh_json(mut self: Pin<&mut Self>, payload_json: String) {
        let Ok(payload) = serde_json::from_str::<serde_json::Value>(&payload_json) else {
            self.as_mut().set_error(QString::from("Invalid response"));
            return;
        };
        let Some(payload) = payload.as_object() else {
            self.as_mut().set_error(QString::from("Invalid response"));
            return;
        };

        self.as_mut().set_generated_at(QString::from(
            payload
                .get("generatedAt")
                .and_then(serde_json::Value::as_str)
                .unwrap_or_default(),
        ));
        self.as_mut().set_status(QString::from(
            payload
                .get("status")
                .and_then(serde_json::Value::as_str)
                .unwrap_or_default(),
        ));
        self.as_mut().set_error(QString::from(
            payload
                .get("error")
                .and_then(serde_json::Value::as_str)
                .unwrap_or_default(),
        ));
        self.set_events_json(QString::from(payload_json));
    }
}

fn refresh(days: i32) -> String {
    let days = if days <= 0 { 180 } else { days };
    let sources = match app_config::load_calendar_sources(&app_config::default_path()) {
        Ok(sources) => sources,
        Err(error) => return output_error(format!("load config: {error}")),
    };
    if sources.is_empty() {
        return output_error(
            "Missing calendar.accounts entries with calendar_ids in leftpanel/config.toml"
                .to_owned(),
        );
    }

    let (range_start, range_end) = event_range(days);
    match fetch_all_sources_threaded(sources, range_start, range_end) {
        Ok((events, errors, success_count)) => {
            let status = if success_count == 0 && !errors.is_empty() {
                "error"
            } else if success_count > 0 && !errors.is_empty() {
                "partial_success"
            } else {
                "fetched"
            };
            if !errors.is_empty() {
                eprintln!("[IcalCache] {status}: {}", errors.join("; "));
            }
            marshal_output(Output {
                generated_at: Local::now().to_rfc3339(),
                status: status.to_owned(),
                error: (!errors.is_empty()).then(|| errors.join("; ")),
                events_by_day: organize_events(events, range_start, range_end),
            })
        }
        Err(error) => output_error(error),
    }
}

fn fetch_all_sources_threaded(
    sources: Vec<CalendarSource>,
    range_start: DateTime<Local>,
    range_end: DateTime<Local>,
) -> Result<(Vec<ParsedEvent>, Vec<String>, usize), String> {
    std::thread::spawn(move || {
        crate::utils::build_multi_thread_runtime()?.block_on(fetch_all_sources(
            sources,
            range_start,
            range_end,
        ))
    })
    .join()
    .expect("calendar worker panicked")
}

async fn fetch_all_sources(
    sources: Vec<CalendarSource>,
    range_start: DateTime<Local>,
    range_end: DateTime<Local>,
) -> Result<(Vec<ParsedEvent>, Vec<String>, usize), String> {
    let mut all_events = Vec::new();
    let mut errors = Vec::new();
    let mut success_count = 0;

    for source in &sources {
        let hub = match google_auth::calendar_hub(&source.account_id).await {
            Ok(hub) => hub,
            Err(error) => {
                errors.push(format!("{}: {error}", source.account_id));
                continue;
            }
        };

        let mut account_success = false;
        for calendar_id in &source.calendar_ids {
            match fetch_calendar_events(&hub, calendar_id, range_start, range_end).await {
                Ok(events) => {
                    account_success = true;
                    all_events.extend(events);
                }
                Err(error) => {
                    errors.push(format!("{}/{}: {error}", source.account_id, calendar_id));
                }
            }
        }
        if account_success {
            success_count += 1;
        }
    }

    Ok((all_events, errors, success_count))
}

async fn fetch_calendar_events<C>(
    hub: &calendar3::CalendarHub<C>,
    calendar_id: &str,
    range_start: DateTime<Local>,
    range_end: DateTime<Local>,
) -> Result<Vec<ParsedEvent>, String>
where
    C: calendar3::common::Connector,
{
    let mut events = Vec::new();
    let mut page_token = String::new();

    loop {
        let mut call = hub
            .events()
            .list(calendar_id)
            .single_events(true)
            .order_by("startTime")
            .time_min(range_start.with_timezone(&Utc))
            .time_max(range_end.with_timezone(&Utc))
            .max_results(2500)
            .clear_scopes()
            .add_scope(calendar3::api::Scope::EventReadonly.as_ref());
        if !page_token.is_empty() {
            call = call.page_token(&page_token);
        }

        let response = call
            .doit()
            .await
            .map(|(_, value)| value)
            .map_err(|e| e.to_string())?;
        for item in response.items.unwrap_or_default() {
            if let Some(event) = event_from_api(&item) {
                events.push(event);
            }
        }

        page_token = response.next_page_token.unwrap_or_default();
        if page_token.is_empty() {
            break;
        }
    }

    Ok(events)
}

fn event_from_api(item: &calendar3::api::Event) -> Option<ParsedEvent> {
    if eq_ignore_ascii_case(item.status.as_deref(), "cancelled")
        || eq_ignore_ascii_case(item.event_type.as_deref(), "workingLocation")
    {
        return None;
    }

    let (start, start_all_day) = event_date_time(item.start.as_ref()?)?;
    let (mut end, end_all_day) = event_date_time(item.end.as_ref()?)?;
    if end <= start {
        end = if start_all_day {
            start + Duration::days(1)
        } else {
            start + Duration::hours(1)
        };
    }

    let all_day = start_all_day || end_all_day;
    let end_date_exclusive = if all_day {
        end
    } else {
        local_midnight(end.date_naive() + Duration::days(1))?
    };
    let title = item
        .summary
        .as_deref()
        .and_then(crate::utils::non_empty_trimmed)
        .unwrap_or_else(|| "Untitled".to_owned());
    let uid = item
        .i_cal_uid
        .as_deref()
        .and_then(crate::utils::non_empty_trimmed)
        .or_else(|| item.id.as_deref().and_then(crate::utils::non_empty_trimmed))
        .unwrap_or_else(|| format!("{}-{}", title, start.timestamp()));

    Some(ParsedEvent {
        event: EventOut {
            uid,
            title,
            start: start.to_rfc3339(),
            end: end.to_rfc3339(),
            all_day,
        },
        start_date: start,
        end_date_exclusive,
    })
}

fn event_date_time(value: &calendar3::api::EventDateTime) -> Option<(DateTime<Local>, bool)> {
    if let Some(date) = value.date {
        return Some((local_midnight(date)?, true));
    }
    value
        .date_time
        .map(|date_time| (date_time.with_timezone(&Local), false))
}

fn event_range(days: i32) -> (DateTime<Local>, DateTime<Local>) {
    let now = Local::now();
    let start = local_midnight(
        NaiveDate::from_ymd_opt(now.year(), now.month(), 1).expect("current month is valid"),
    )
    .expect("local month start exists");
    (start, start + Duration::days(days as i64))
}

fn organize_events(
    events: Vec<ParsedEvent>,
    range_start: DateTime<Local>,
    range_end: DateTime<Local>,
) -> HashMap<String, Vec<EventOut>> {
    let mut result: HashMap<String, Vec<EventOut>> = HashMap::new();

    for parsed in events {
        let Some(mut day) = local_midnight(parsed.start_date.date_naive()) else {
            continue;
        };
        let Some(end_day) = local_midnight(parsed.end_date_exclusive.date_naive()) else {
            continue;
        };
        loop {
            if day < range_start {
                day += Duration::days(1);
                continue;
            }
            if day > range_end {
                break;
            }
            result
                .entry(day.format("%Y-%m-%d").to_string())
                .or_default()
                .push(parsed.event.clone());
            day += Duration::days(1);
            if day >= end_day {
                break;
            }
        }
    }

    for events in result.values_mut() {
        events.sort_by(|left, right| left.start.cmp(&right.start));
    }
    result
}

fn local_midnight(date: NaiveDate) -> Option<DateTime<Local>> {
    Local
        .from_local_datetime(&date.and_time(NaiveTime::MIN))
        .single()
}

fn eq_ignore_ascii_case(value: Option<&str>, expected: &str) -> bool {
    value
        .map(str::trim)
        .is_some_and(|value| value.eq_ignore_ascii_case(expected))
}

fn output_error(message: String) -> String {
    eprintln!("[IcalCache] error: {message}");
    marshal_output(Output {
        generated_at: Local::now().to_rfc3339(),
        status: "error".to_owned(),
        error: Some(message),
        events_by_day: HashMap::new(),
    })
}

fn marshal_output(output: Output) -> String {
    serde_json::to_string(&output).unwrap_or_else(|_| "{}".to_owned())
}

#[cfg(test)]
mod tests {
    use super::event_from_api;
    use google_calendar3::api::{Event, EventDateTime};

    #[test]
    fn event_from_api_converts_all_day_event() {
        let parsed = event_from_api(&Event {
            id: Some("event-1".to_owned()),
            summary: Some("Exam".to_owned()),
            start: Some(EventDateTime {
                date: Some("2026-06-10".parse().expect("valid date")),
                ..Default::default()
            }),
            end: Some(EventDateTime {
                date: Some("2026-06-11".parse().expect("valid date")),
                ..Default::default()
            }),
            ..Default::default()
        })
        .expect("event should parse");

        assert_eq!(parsed.event.uid, "event-1");
        assert_eq!(parsed.event.title, "Exam");
        assert!(parsed.event.all_day);
        assert!(parsed.event.start.starts_with("2026-06-10T00:00:00"));
        assert!(parsed.event.end.starts_with("2026-06-11T00:00:00"));
    }

    #[test]
    fn calendar_sources_trim_and_filter() {
        use crate::app_config::CalendarSource;
        let sources = [
            CalendarSource {
                account_id: "iit".to_owned(),
                calendar_ids: vec!["primary".to_owned()],
            },
            CalendarSource {
                account_id: "navon".to_owned(),
                calendar_ids: vec!["navonjohnlukose@gmail.com".to_owned()],
            },
        ];
        assert_eq!(sources.len(), 2);
        assert_eq!(sources[0].account_id, "iit");
        assert_eq!(sources[0].calendar_ids, ["primary"]);
    }
}
