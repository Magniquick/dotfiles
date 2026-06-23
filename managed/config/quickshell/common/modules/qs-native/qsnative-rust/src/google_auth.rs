use std::path::Path;
use std::sync::OnceLock;

use async_trait::async_trait;
use rustls::crypto::aws_lc_rs;
use chrono::{SecondsFormat, Utc};
use google_calendar3 as calendar3;
use google_gmail1 as gmail1;
use google_gmail1::common::GetToken;
use serde::Serialize;

use crate::app_config::EmailAccount;
use crate::secrets;

type HttpConnector = gmail1::hyper_util::client::legacy::connect::HttpConnector;
type HttpsConnector = gmail1::hyper_rustls::HttpsConnector<HttpConnector>;
type GoogleClient = gmail1::common::Client<HttpsConnector>;

const TOKEN_KEY: &str = "TOKEN_JSON";
const CLIENT_KEY: &str = "CLIENT_JSON";

static CRYPTO_PROVIDER_INIT: OnceLock<()> = OnceLock::new();

fn ensure_crypto_provider() {
    CRYPTO_PROVIDER_INIT.get_or_init(|| {
        let _ = aws_lc_rs::default_provider().install_default();
    });
}

pub const GOOGLE_SCOPES: [&str; 2] = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/calendar.readonly",
];

#[derive(Debug, Serialize)]
pub struct CalendarSummary {
    pub id: String,
    pub summary: String,
    pub primary: bool,
    pub selected: bool,
    pub hidden: bool,
    #[serde(rename = "accessRole")]
    pub access_role: String,
    pub upcoming: Vec<EventSummary>,
}

#[derive(Debug, Serialize)]
pub struct EventSummary {
    pub summary: String,
    pub start: String,
    pub end: String,
    pub status: String,
}

pub fn env_id(id: &str) -> String {
    id.trim()
        .to_ascii_uppercase()
        .chars()
        .map(|value| {
            if value.is_ascii_alphanumeric() {
                value
            } else {
                '_'
            }
        })
        .collect::<String>()
        .trim_matches('_')
        .to_owned()
}

pub fn key_prefix(id: &str) -> String {
    format!("GOOGLE_{}_", env_id(id))
}

pub fn token_key(id: &str) -> String {
    key_prefix(id) + TOKEN_KEY
}

pub fn client_key(id: &str) -> String {
    key_prefix(id) + CLIENT_KEY
}

pub fn provision(account: &EmailAccount, client_json_path: &str) -> Result<(), String> {
    crate::utils::build_multi_thread_runtime()?.block_on(provision_async(account, client_json_path))
}

pub fn list_calendars(account: &EmailAccount) -> Result<Vec<CalendarSummary>, String> {
    crate::utils::build_multi_thread_runtime()?.block_on(list_calendars_async(&account.id))
}

pub fn gmail_list_messages(
    account_id: &str,
    query: &str,
    limit: u32,
) -> Result<gmail1::api::ListMessagesResponse, String> {
    let account_id = account_id.to_owned();
    let query = query.to_owned();
    std::thread::spawn(move || {
        crate::utils::build_multi_thread_runtime()?.block_on(async {
            let hub = gmail_hub(&account_id).await?;
            let mut call = hub
                .users()
                .messages_list("me")
                .max_results(limit.clamp(1, 50));
            if !query.trim().is_empty() {
                call = call.q(query.trim());
            }
            call.doit()
                .await
                .map(|(_, value)| value)
                .map_err(err_string)
        })
    })
    .join()
    .map_err(|_| "gmail list worker panicked".to_owned())?
}

pub fn gmail_get_message(
    account_id: &str,
    id: &str,
    include_body: bool,
    metadata_headers: &[&str],
) -> Result<gmail1::api::Message, String> {
    let account_id = account_id.to_owned();
    let id = id.to_owned();
    let metadata_headers: Vec<String> = metadata_headers.iter().map(|s| s.to_string()).collect();
    std::thread::spawn(move || {
        crate::utils::build_multi_thread_runtime()?.block_on(async {
            let hub = gmail_hub(&account_id).await?;
            let mut call = hub
                .users()
                .messages_get("me", id.trim())
                .format(if include_body { "full" } else { "metadata" });
            if !include_body {
                for header in &metadata_headers {
                    call = call.add_metadata_headers(header.as_str());
                }
            }
            call.doit()
                .await
                .map(|(_, value)| value)
                .map_err(err_string)
        })
    })
    .join()
    .map_err(|_| "gmail get worker panicked".to_owned())?
}

async fn provision_async(account: &EmailAccount, client_json_path: &str) -> Result<(), String> {
    let raw = std::fs::read_to_string(Path::new(client_json_path))
        .map_err(|error| format!("read OAuth client JSON: {error}"))?;
    parse_secret(&raw)?;
    let client_key = client_key(&account.id);
    secrets::set_async(&client_key, &raw)
        .await
        .map_err(|error| format!("store Google OAuth client JSON: {error}"))?;
    // Request all scopes upfront so gmail_hub and calendar_hub share one stored token.
    let secret = account_secret_async(&account.id).await?;
    let auth = authenticator(&account.id, secret).await?;
    auth.get_token(GOOGLE_SCOPES.as_slice())
        .await
        .map_err(err_string)?;
    verify_google_account(account).await
}

async fn verify_google_account(account: &EmailAccount) -> Result<(), String> {
    let hub = gmail_hub(&account.id).await?;
    let profile = hub
        .users()
        .get_profile("me")
        .doit()
        .await
        .map(|(_, value)| value)
        .map_err(err_string)?;
    let email = profile.email_address.unwrap_or_default();
    if email.trim().eq_ignore_ascii_case(&account.address) {
        Ok(())
    } else {
        Err(format!(
            "authorized account {email:?} does not match configured account {:?}",
            account.address
        ))
    }
}

async fn list_calendars_async(account_id: &str) -> Result<Vec<CalendarSummary>, String> {
    let hub = calendar_hub(account_id).await?;
    let list = hub
        .calendar_list()
        .list()
        .max_results(250)
        .doit()
        .await
        .map(|(_, value)| value)
        .map_err(err_string)?;
    let now = Utc::now();
    let mut out = Vec::new();

    for item in list.items.unwrap_or_default() {
        let mut summary = calendar_summary(&item);
        if let Some(id) = item.id.as_deref().filter(|id| !id.is_empty()) {
            if let Ok(events) = calendar_events(&hub, id, now).await {
                summary.upcoming = events;
            }
        }
        out.push(summary);
    }

    Ok(out)
}

fn calendar_summary(item: &calendar3::api::CalendarListEntry) -> CalendarSummary {
    CalendarSummary {
        id: item.id.clone().unwrap_or_default(),
        summary: item.summary.clone().unwrap_or_default(),
        primary: item.primary.unwrap_or(false),
        selected: item.selected.unwrap_or(false),
        hidden: item.hidden.unwrap_or(false),
        access_role: item.access_role.clone().unwrap_or_default(),
        upcoming: Vec::new(),
    }
}

async fn calendar_events<C>(
    hub: &calendar3::CalendarHub<C>,
    calendar_id: &str,
    time_min: chrono::DateTime<Utc>,
) -> Result<Vec<EventSummary>, String>
where
    C: calendar3::common::Connector,
{
    let events = hub
        .events()
        .list(calendar_id)
        .single_events(true)
        .order_by("startTime")
        .max_results(8)
        .time_min(time_min)
        .clear_scopes()
        .add_scope(calendar3::api::Scope::EventReadonly.as_ref())
        .doit()
        .await
        .map(|(_, value)| value)
        .map_err(err_string)?;
    Ok(events
        .items
        .unwrap_or_default()
        .into_iter()
        .map(|event| EventSummary {
            summary: event.summary.unwrap_or_else(|| "(no title)".to_owned()),
            start: event.start.as_ref().map(event_time).unwrap_or_default(),
            end: event.end.as_ref().map(event_time).unwrap_or_default(),
            status: event.status.unwrap_or_default(),
        })
        .collect())
}

fn event_time(value: &calendar3::api::EventDateTime) -> String {
    value
        .date_time
        .map(|value| value.to_rfc3339_opts(SecondsFormat::Secs, true))
        .or_else(|| value.date.map(|value| value.to_string()))
        .unwrap_or_default()
}

pub async fn gmail_hub(account_id: &str) -> Result<gmail1::Gmail<HttpsConnector>, String> {
    ensure_crypto_provider();
    let auth = authenticator(account_id, account_secret_async(account_id).await?).await?;
    let client = google_client()?;
    Ok(gmail1::Gmail::new(client, auth))
}

pub async fn calendar_hub(
    account_id: &str,
) -> Result<calendar3::CalendarHub<HttpsConnector>, String> {
    ensure_crypto_provider();
    let auth = authenticator(account_id, account_secret_async(account_id).await?).await?;
    let client = google_client()?;
    Ok(calendar3::CalendarHub::new(client, auth))
}

fn build_https_connector() -> Result<HttpsConnector, String> {
    Ok(gmail1::hyper_rustls::HttpsConnectorBuilder::new()
        .with_native_roots()
        .map_err(err_string)?
        .https_only()
        .enable_http2()
        .build())
}

fn google_client() -> Result<GoogleClient, String> {
    let connector = build_https_connector()?;
    Ok(gmail1::hyper_util::client::legacy::Client::builder(
        gmail1::hyper_util::rt::TokioExecutor::new(),
    )
    .build(connector))
}

async fn authenticator(
    account_id: &str,
    secret: gmail1::yup_oauth2::ApplicationSecret,
) -> Result<impl gmail1::common::GetToken, String> {
    let connector = build_https_connector()?;
    let client = gmail1::yup_oauth2::CustomHyperClientBuilder::from(
        gmail1::hyper_util::client::legacy::Client::builder(
            gmail1::hyper_util::rt::TokioExecutor::new(),
        )
        .build(connector),
    );
    gmail1::yup_oauth2::InstalledFlowAuthenticator::with_client(
        secret,
        gmail1::yup_oauth2::InstalledFlowReturnMethod::HTTPRedirect,
        client,
    )
    .with_storage(Box::new(SecretTokenStorage {
        account_id: account_id.trim().to_owned(),
    }))
    .build()
    .await
    .map_err(err_string)
}

async fn account_secret_async(
    account_id: &str,
) -> Result<gmail1::yup_oauth2::ApplicationSecret, String> {
    let raw = secrets::lookup_async(&client_key(account_id))
        .await
        .ok_or_else(|| {
            format!(
                "account {account_id} Google OAuth requires {}",
                client_key(account_id)
            )
        })?;
    parse_secret(&raw)
}

fn parse_secret(raw: &str) -> Result<gmail1::yup_oauth2::ApplicationSecret, String> {
    gmail1::yup_oauth2::parse_application_secret(raw).map_err(err_string)
}

#[derive(Clone)]
struct SecretTokenStorage {
    account_id: String,
}

#[async_trait]
impl gmail1::yup_oauth2::storage::TokenStorage for SecretTokenStorage {
    async fn set(
        &self,
        _scopes: &[&str],
        token: gmail1::yup_oauth2::storage::TokenInfo,
    ) -> Result<(), gmail1::yup_oauth2::storage::TokenStorageError> {
        let raw = serde_json::to_string(&token).map_err(|error| {
            gmail1::yup_oauth2::storage::TokenStorageError::Other(error.to_string().into())
        })?;
        secrets::set_async(&token_key(&self.account_id), &raw)
            .await
            .map_err(|error| {
                gmail1::yup_oauth2::storage::TokenStorageError::Other(error.to_string().into())
            })
    }

    async fn get(&self, _scopes: &[&str]) -> Option<gmail1::yup_oauth2::storage::TokenInfo> {
        secrets::lookup_async(&token_key(&self.account_id))
            .await
            .and_then(|raw| {
                serde_json::from_str::<gmail1::yup_oauth2::storage::TokenInfo>(raw.trim()).ok()
            })
    }
}

fn err_string(error: impl std::fmt::Display) -> String {
    error.to_string()
}

#[cfg(test)]
mod tests {
    use super::{client_key, env_id, token_key};

    #[test]
    fn secret_keys_match_account_id_shape() {
        assert_eq!(env_id(" personal.gmail "), "PERSONAL_GMAIL");
        assert_eq!(
            token_key(" personal.gmail "),
            "GOOGLE_PERSONAL_GMAIL_TOKEN_JSON"
        );
        assert_eq!(
            client_key(" personal.gmail "),
            "GOOGLE_PERSONAL_GMAIL_CLIENT_JSON"
        );
    }
}
