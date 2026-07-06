use std::collections::HashMap;

use chrono::{SecondsFormat, TimeZone, Utc};
use google_gmail1::api::{Message as GmailApiMessage, MessagePart as GmailMessagePart};

use crate::email::GmailAccount;
use crate::google_auth;

const METADATA_HEADERS: [&str; 5] = ["Subject", "From", "To", "Date", "Message-ID"];

#[derive(Debug, Clone)]
pub struct GmailClient {
    account_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GmailListResult {
    pub messages: Vec<GmailListedMessage>,
    pub estimate: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GmailListedMessage {
    pub id: String,
    pub thread_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GmailMessage {
    pub id: String,
    pub thread_id: String,
    pub subject: String,
    pub from: String,
    pub to: String,
    pub date: String,
    pub message_id: String,
    pub snippet: String,
    pub body_text: String,
    pub body_html: String,
    pub body_truncated: bool,
    pub internal_date: String,
    pub size: i64,
    pub label_ids: Vec<String>,
}

impl GmailClient {
    #[must_use]
    pub fn new(account: &GmailAccount) -> Self {
        Self {
            account_id: account.id.clone(),
        }
    }

    /// # Errors
    ///
    /// Returns an error string if the underlying Gmail list request fails.
    pub fn list_messages(&self, query: &str, limit: u32) -> Result<GmailListResult, String> {
        let response = google_auth::gmail_list_messages(&self.account_id, query, limit)?;
        Ok(GmailListResult {
            estimate: i64::from(response.result_size_estimate.unwrap_or_default()),
            messages: response
                .messages
                .unwrap_or_default()
                .into_iter()
                .filter_map(|message| {
                    let id = message.id.as_deref().unwrap_or("").trim();
                    (!id.is_empty()).then(|| GmailListedMessage {
                        id: id.to_owned(),
                        thread_id: message.thread_id.unwrap_or_default(),
                    })
                })
                .collect(),
        })
    }

    /// # Errors
    ///
    /// Returns an error string if the id is empty or the Gmail get request fails.
    pub fn get_message(
        &self,
        id: &str,
        include_body: bool,
        max_body_chars: usize,
    ) -> Result<GmailMessage, String> {
        let id = id.trim();
        if id.is_empty() {
            return Err("Gmail message id is required".to_owned());
        }
        let message =
            google_auth::gmail_get_message(&self.account_id, id, include_body, &METADATA_HEADERS)?;
        Ok(gmail_message_from_api(
            message,
            include_body,
            max_body_chars,
        ))
    }
}

fn gmail_message_from_api(
    message: GmailApiMessage,
    include_body: bool,
    max_body_chars: usize,
) -> GmailMessage {
    let headers = gmail_headers(message.payload.as_ref());
    let (body_text, body_html, body_truncated) = if include_body {
        gmail_bodies(message.payload.as_ref(), max_body_chars)
    } else {
        (String::new(), String::new(), false)
    };

    GmailMessage {
        id: message.id.unwrap_or_default(),
        thread_id: message.thread_id.unwrap_or_default(),
        subject: headers.get("subject").cloned().unwrap_or_default(),
        from: headers.get("from").cloned().unwrap_or_default(),
        to: headers.get("to").cloned().unwrap_or_default(),
        date: headers.get("date").cloned().unwrap_or_default(),
        message_id: headers
            .get("message-id")
            .or_else(|| headers.get("message_id"))
            .cloned()
            .unwrap_or_default(),
        snippet: message.snippet.unwrap_or_default(),
        body_text,
        body_html,
        body_truncated,
        internal_date: gmail_internal_date(message.internal_date),
        size: i64::from(message.size_estimate.unwrap_or_default()),
        label_ids: message.label_ids.unwrap_or_default(),
    }
}

fn gmail_headers(part: Option<&GmailMessagePart>) -> HashMap<String, String> {
    part.map(|part| {
        part.headers
            .as_deref()
            .unwrap_or_default()
            .iter()
            .filter_map(|header| {
                let key = header
                    .name
                    .as_deref()
                    .unwrap_or("")
                    .trim()
                    .to_ascii_lowercase();
                let value = header.value.as_deref().unwrap_or("").trim();
                (!key.is_empty()).then(|| (key, value.to_owned()))
            })
            .collect()
    })
    .unwrap_or_default()
}

fn gmail_internal_date(epoch_millis: Option<i64>) -> String {
    epoch_millis
        .filter(|value| *value > 0)
        .and_then(|value| Utc.timestamp_millis_opt(value).single())
        .map(|value| value.to_rfc3339_opts(SecondsFormat::Secs, true))
        .unwrap_or_default()
}

fn gmail_bodies(part: Option<&GmailMessagePart>, max_chars: usize) -> (String, String, bool) {
    let Some(part) = part else {
        return (String::new(), String::new(), false);
    };
    let mut text = String::new();
    let mut html = String::new();
    let mut truncated = false;
    collect_gmail_bodies(part, max_chars, &mut text, &mut html, &mut truncated);
    (text, html, truncated)
}

fn collect_gmail_bodies(
    part: &GmailMessagePart,
    max_chars: usize,
    text: &mut String,
    html: &mut String,
    truncated: &mut bool,
) {
    if let Some(decoded) = part.body.as_ref().and_then(|body| body.data.as_ref()) {
        let decoded = String::from_utf8_lossy(decoded);
        if !decoded.is_empty() {
            let (value, was_truncated) = truncate_output(&decoded, max_chars);
            *truncated |= was_truncated;
            match part
                .mime_type
                .as_deref()
                .unwrap_or("")
                .to_ascii_lowercase()
                .as_str()
            {
                "text/plain" if text.is_empty() => *text = value,
                "text/html" if html.is_empty() => *html = value,
                _ => {}
            }
        }
    }
    for child in part.parts.as_deref().unwrap_or_default() {
        collect_gmail_bodies(child, max_chars, text, html, truncated);
    }
}

fn truncate_output(value: &str, max_chars: usize) -> (String, bool) {
    if let Some((index, _)) = value.char_indices().nth(max_chars) {
        return (value[..index].to_owned(), true);
    }
    (value.to_owned(), false)
}

#[cfg(test)]
mod tests {
    use super::{gmail_message_from_api, truncate_output, GmailApiMessage};

    #[test]
    fn parses_headers_and_first_text_and_html_bodies() {
        let raw = serde_json::json!({
            "id": "gmail-msg-1",
            "threadId": "thread-1",
            "snippet": "snippet",
            "internalDate": "1770000000000",
            "sizeEstimate": 1234,
            "labelIds": ["INBOX"],
            "payload": {
                "headers": [
                    {"name": "Subject", "value": "Quarterly report"},
                    {"name": "From", "value": "Alice <alice@example.com>"},
                    {"name": "Message-ID", "value": "<rfc-message-id@example.com>"}
                ],
                "parts": [
                    {
                        "mimeType": "text/plain",
                        "body": {"data": "Ym9keSB0ZXh0"}
                    },
                    {
                        "mimeType": "text/html",
                        "body": {"data": "PHA-Ym9keSB0ZXh0PC9wPg=="}
                    }
                ]
            }
        });
        let api = serde_json::from_value::<GmailApiMessage>(raw).expect("parse message");
        let message = gmail_message_from_api(api, true, 4);

        assert_eq!(message.id, "gmail-msg-1");
        assert_eq!(message.subject, "Quarterly report");
        assert_eq!(message.from, "Alice <alice@example.com>");
        assert_eq!(message.message_id, "<rfc-message-id@example.com>");
        assert_eq!(message.body_text, "body");
        assert_eq!(message.body_html, "<p>b");
        assert!(message.body_truncated);
        assert_eq!(message.label_ids, ["INBOX"]);
    }

    #[test]
    fn truncates_on_utf8_character_boundaries() {
        assert_eq!(truncate_output("aé日", 2), ("aé".to_owned(), true));
        assert_eq!(truncate_output("aé日", 3), ("aé日".to_owned(), false));
        assert_eq!(truncate_output("aé日", 0), (String::new(), true));
    }
}
