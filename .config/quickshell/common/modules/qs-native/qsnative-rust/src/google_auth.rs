use std::collections::HashSet;
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::process::Command;
use std::sync::OnceLock;

use async_trait::async_trait;
use chrono::{SecondsFormat, Utc};
use google_calendar3 as calendar3;
use google_gmail1 as gmail1;
use google_gmail1::common::GetToken;
use google_gmail1::yup_oauth2::authenticator_delegate::{
    DefaultInstalledFlowDelegate, InstalledFlowDelegate,
};
use rustls::crypto::ring;
use serde::{Deserialize, Serialize};

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
        let _ = ring::default_provider().install_default();
    });
}

pub const GOOGLE_SCOPES: [&str; 4] = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/calendar.events.readonly",
    "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
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

pub fn provision(account: &EmailAccount, client_json_path: Option<&str>) -> Result<(), String> {
    let client_json_path = client_json_path
        .map(|path| path.trim().to_owned())
        .filter(|path| !path.is_empty());
    crate::utils::build_multi_thread_runtime()?
        .block_on(provision_async(account, client_json_path.as_deref()))
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

async fn provision_async(
    account: &EmailAccount,
    client_json_path: Option<&str>,
) -> Result<(), String> {
    if let Some(client_json_path) = client_json_path {
        let raw = std::fs::read_to_string(Path::new(client_json_path))
            .map_err(|error| format!("read OAuth client JSON: {error}"))?;
        parse_secret(&raw)?;
        let client_key = client_key(&account.id);
        secrets::set_async(&client_key, &raw)
            .await
            .map_err(|error| format!("store Google OAuth client JSON: {error}"))?;
    }
    // Request all scopes upfront so gmail_hub and calendar_hub share one stored token.
    secrets::delete_async(&token_key(&account.id))
        .await
        .map_err(|error| format!("clear existing Google OAuth token: {error}"))?;
    let mut secret = account_secret_async(&account.id).await?;
    add_login_hint(&mut secret, &account.address);
    let auth = authenticator(&account.id, secret, AuthPrompt::Interactive).await?;
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
    let auth = authenticator(
        account_id,
        account_secret_async(account_id).await?,
        AuthPrompt::Interactive,
    )
    .await?;
    let client = google_client()?;
    Ok(gmail1::Gmail::new(client, auth))
}

pub async fn calendar_hub(
    account_id: &str,
) -> Result<calendar3::CalendarHub<HttpsConnector>, String> {
    calendar_hub_with_prompt(account_id, AuthPrompt::Interactive).await
}

pub async fn calendar_hub_silent(
    account_id: &str,
) -> Result<calendar3::CalendarHub<HttpsConnector>, String> {
    calendar_hub_with_prompt(account_id, AuthPrompt::Silent).await
}

pub async fn reauthorize_calendar_hub(
    account_id: &str,
) -> Result<calendar3::CalendarHub<HttpsConnector>, String> {
    secrets::delete_async(&token_key(account_id))
        .await
        .map_err(|error| format!("clear existing Google OAuth token: {error}"))?;
    calendar_hub_with_prompt(account_id, AuthPrompt::Interactive).await
}

async fn calendar_hub_with_prompt(
    account_id: &str,
    prompt: AuthPrompt,
) -> Result<calendar3::CalendarHub<HttpsConnector>, String> {
    ensure_crypto_provider();
    let auth = authenticator(account_id, account_secret_async(account_id).await?, prompt).await?;
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
    prompt: AuthPrompt,
) -> Result<impl gmail1::common::GetToken, String> {
    ensure_crypto_provider();
    let connector = build_https_connector()?;
    let client = gmail1::yup_oauth2::CustomHyperClientBuilder::from(
        gmail1::hyper_util::client::legacy::Client::builder(
            gmail1::hyper_util::rt::TokioExecutor::new(),
        )
        .build(connector),
    );
    let (method, flow_delegate): (
        gmail1::yup_oauth2::InstalledFlowReturnMethod,
        Box<dyn InstalledFlowDelegate>,
    ) = match prompt {
        AuthPrompt::Interactive => (
            gmail1::yup_oauth2::InstalledFlowReturnMethod::HTTPRedirect,
            Box::new(OpenBrowserInstalledFlowDelegate),
        ),
        AuthPrompt::Silent => (
            gmail1::yup_oauth2::InstalledFlowReturnMethod::Interactive,
            Box::new(SilentInstalledFlowDelegate),
        ),
    };
    gmail1::yup_oauth2::InstalledFlowAuthenticator::with_client(secret, method, client)
        .flow_delegate(flow_delegate)
        .force_account_selection(true)
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

fn add_login_hint(secret: &mut gmail1::yup_oauth2::ApplicationSecret, address: &str) {
    let address = address.trim();
    if address.is_empty() || secret.auth_uri.contains("login_hint=") {
        return;
    }
    let separator = if secret.auth_uri.contains('?') {
        '&'
    } else {
        '?'
    };
    secret.auth_uri.push(separator);
    secret.auth_uri.push_str("login_hint=");
    secret.auth_uri.push_str(&query_encode(address));
}

fn query_encode(value: &str) -> String {
    let mut encoded = String::new();
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                encoded.push(byte as char)
            }
            _ => encoded.push_str(&format!("%{byte:02X}")),
        }
    }
    encoded
}

#[derive(Clone)]
struct SecretTokenStorage {
    account_id: String,
}

#[derive(Clone, Copy)]
enum AuthPrompt {
    Interactive,
    Silent,
}

#[derive(Clone)]
struct OpenBrowserInstalledFlowDelegate;

#[derive(Clone)]
struct SilentInstalledFlowDelegate;

impl InstalledFlowDelegate for OpenBrowserInstalledFlowDelegate {
    fn present_user_url<'a>(
        &'a self,
        url: &'a str,
        need_code: bool,
    ) -> Pin<Box<dyn Future<Output = Result<String, String>> + Send + 'a>> {
        Box::pin(async move {
            match Command::new("xdg-open").arg(url).spawn() {
                Ok(_) => eprintln!("Opened Google OAuth consent page in your browser."),
                Err(error) => eprintln!("Failed to open Google OAuth URL with xdg-open: {error}"),
            }
            DefaultInstalledFlowDelegate
                .present_user_url(url, need_code)
                .await
        })
    }
}

impl InstalledFlowDelegate for SilentInstalledFlowDelegate {
    fn present_user_url<'a>(
        &'a self,
        _url: &'a str,
        _need_code: bool,
    ) -> Pin<Box<dyn Future<Output = Result<String, String>> + Send + 'a>> {
        Box::pin(async {
            Err("Google OAuth token is missing or expired; run qs-google-auth provision".to_owned())
        })
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
struct StoredToken {
    scopes: Vec<String>,
    token: gmail1::yup_oauth2::storage::TokenInfo,
}

fn normalize_scopes(scopes: &[&str]) -> Vec<String> {
    let mut scopes = scopes
        .iter()
        .map(|scope| scope.trim().to_owned())
        .filter(|scope| !scope.is_empty())
        .collect::<Vec<_>>();
    scopes.sort_unstable();
    scopes.dedup();
    scopes
}

fn scope_key(scopes: &[String]) -> String {
    scopes.join("\n")
}

fn find_token_for_scopes(
    tokens: &[StoredToken],
    requested_scopes: &[String],
) -> Option<gmail1::yup_oauth2::storage::TokenInfo> {
    let requested = requested_scopes.iter().collect::<HashSet<_>>();
    tokens
        .iter()
        .find(|entry| {
            let available = entry.scopes.iter().collect::<HashSet<_>>();
            requested.is_subset(&available)
        })
        .map(|entry| entry.token.clone())
}

#[async_trait]
impl gmail1::yup_oauth2::storage::TokenStorage for SecretTokenStorage {
    async fn set(
        &self,
        scopes: &[&str],
        token: gmail1::yup_oauth2::storage::TokenInfo,
    ) -> Result<(), gmail1::yup_oauth2::storage::TokenStorageError> {
        let requested_scopes = normalize_scopes(scopes);
        let key = scope_key(&requested_scopes);
        let mut tokens = secrets::lookup_async(&token_key(&self.account_id))
            .await
            .and_then(|raw| serde_json::from_str::<Vec<StoredToken>>(raw.trim()).ok())
            .unwrap_or_default();
        if let Some(entry) = tokens
            .iter_mut()
            .find(|entry| scope_key(&entry.scopes) == key)
        {
            entry.token = token;
        } else {
            tokens.push(StoredToken {
                scopes: requested_scopes,
                token,
            });
        }
        let raw = serde_json::to_string(&tokens).map_err(|error| {
            gmail1::yup_oauth2::storage::TokenStorageError::Other(error.to_string().into())
        })?;
        secrets::set_async(&token_key(&self.account_id), &raw)
            .await
            .map_err(|error| {
                gmail1::yup_oauth2::storage::TokenStorageError::Other(error.to_string().into())
            })
    }

    async fn get(&self, scopes: &[&str]) -> Option<gmail1::yup_oauth2::storage::TokenInfo> {
        let requested_scopes = normalize_scopes(scopes);
        secrets::lookup_async(&token_key(&self.account_id))
            .await
            .and_then(|raw| {
                serde_json::from_str::<Vec<StoredToken>>(raw.trim())
                    .ok()
                    .and_then(|tokens| find_token_for_scopes(&tokens, &requested_scopes))
            })
    }
}

fn err_string(error: impl std::fmt::Display) -> String {
    error.to_string()
}

#[cfg(test)]
mod tests {
    use super::{client_key, env_id, normalize_scopes, query_encode, token_key};

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

    #[test]
    fn encodes_login_hint_query_value() {
        assert_eq!(
            query_encode("24f2003934@ds.study.iitm.ac.in"),
            "24f2003934%40ds.study.iitm.ac.in"
        );
    }

    #[test]
    fn normalizes_scope_sets() {
        assert_eq!(normalize_scopes(&[" b ", "a", "a", ""]), ["a", "b"]);
    }
}
