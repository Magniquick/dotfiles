use std::fs;
use std::path::{Path, PathBuf};

use serde::Deserialize;

#[derive(Debug, Clone)]
pub struct EmailAccount {
    pub id: String,
    pub label: String,
    pub address: String,
    pub provider: String,
}

#[derive(Debug, Clone)]
pub struct CalendarSource {
    pub account_id: String,
    pub calendar_ids: Vec<String>,
}

#[derive(Debug, Default, Deserialize)]
struct Config {
    #[serde(default)]
    email: EmailSection,
    #[serde(default)]
    calendar: CalendarSection,
}

#[derive(Debug, Default, Deserialize)]
struct EmailSection {
    #[serde(default)]
    accounts: Vec<RawEmailAccount>,
}

#[derive(Debug, Default, Deserialize)]
struct RawEmailAccount {
    #[serde(default)]
    id: String,
    #[serde(default)]
    label: String,
    #[serde(default)]
    address: String,
    #[serde(default)]
    provider: String,
}

#[derive(Debug, Default, Deserialize)]
struct CalendarSection {
    #[serde(default)]
    accounts: Vec<RawCalendarAccount>,
}

#[derive(Debug, Default, Deserialize)]
struct RawCalendarAccount {
    #[serde(default)]
    account: String,
    #[serde(default)]
    calendar_ids: Vec<String>,
}

/// Returns the path to `leftpanel/config.toml`, searching from environment
/// variables and the current directory upwards.
#[must_use]
pub fn default_path() -> PathBuf {
    for key in ["QS_SHELL_DIR", "QUICKSHELL_SHELL_DIR"] {
        if let Some(path) = config_path_in_dir(std::env::var(key).unwrap_or_default()) {
            return path;
        }
    }
    let Ok(mut dir) = std::env::current_dir() else {
        return PathBuf::new();
    };
    loop {
        if let Some(path) = config_path_in_dir(&dir) {
            return path;
        }
        if !dir.pop() {
            break;
        }
    }
    PathBuf::new()
}

fn config_path_in_dir(dir: impl AsRef<Path>) -> Option<PathBuf> {
    let dir = dir.as_ref();
    if dir.as_os_str().is_empty() {
        return None;
    }
    let candidate = dir.join("leftpanel").join("config.toml");
    candidate.is_file().then_some(candidate)
}

fn load_config(path: &Path) -> Result<Config, String> {
    let raw = match fs::read_to_string(path) {
        Ok(raw) => raw,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(Config::default());
        }
        Err(error) => return Err(error.to_string()),
    };
    toml::from_str::<Config>(&raw).map_err(|e| e.to_string())
}

/// Loads and validates a single Gmail account by id.
///
/// # Errors
/// Returns `Err` if the config cannot be read/parsed, the account is unknown,
/// or the account is missing its address/provider or is not a Gmail account.
pub fn load_account(path: &Path, account_id: &str) -> Result<EmailAccount, String> {
    let config = load_config(path)?;
    let wanted = account_id.trim();
    config
        .email
        .accounts
        .into_iter()
        .find(|a| a.id.trim().eq_ignore_ascii_case(wanted))
        .ok_or_else(|| format!("unknown email account {account_id:?}"))
        .and_then(|a| {
            let address = crate::utils::non_empty_trimmed(&a.address)
                .ok_or_else(|| format!("email account {account_id} has no address"))?;
            let provider = crate::utils::non_empty_trimmed(&a.provider)
                .ok_or_else(|| format!("email account {account_id} has no provider"))?;
            if provider != "gmail" {
                return Err(format!(
                    "email account {account_id} is not a Google/Gmail account"
                ));
            }
            Ok(EmailAccount {
                id: a.id.trim().to_owned(),
                label: a.label.trim().to_owned(),
                address,
                provider,
            })
        })
}

/// Loads every configured Gmail account.
///
/// # Errors
/// Returns `Err` if the config cannot be read/parsed, or any Gmail account is
/// missing its id or address.
pub fn load_google_accounts(path: &Path) -> Result<Vec<EmailAccount>, String> {
    let config = load_config(path)?;
    config
        .email
        .accounts
        .into_iter()
        .filter(|a| a.provider.trim() == "gmail")
        .map(|a| {
            let id = crate::utils::non_empty_trimmed(&a.id)
                .ok_or_else(|| "email account has no id".to_owned())?;
            let address = crate::utils::non_empty_trimmed(&a.address)
                .ok_or_else(|| format!("email account {id} has no address"))?;
            Ok(EmailAccount {
                id,
                label: a.label.trim().to_owned(),
                address,
                provider: a.provider.trim().to_owned(),
            })
        })
        .collect()
}

/// Returns calendar sources whose `account` field matches a configured email
/// account. Sources with empty `account`/`calendar_ids` are silently dropped.
///
/// # Errors
/// Returns `Err` if the config cannot be read or parsed.
pub fn load_calendar_sources(path: &Path) -> Result<Vec<CalendarSource>, String> {
    let config = load_config(path)?;

    let sources = config
        .calendar
        .accounts
        .into_iter()
        .filter_map(|raw| {
            let account_id = raw.account.trim().to_owned();
            if account_id.is_empty() {
                return None;
            }
            let calendar_ids: Vec<String> = raw
                .calendar_ids
                .into_iter()
                .map(|id| id.trim().to_owned())
                .filter(|id| !id.is_empty())
                .collect();
            if calendar_ids.is_empty() {
                return None;
            }
            if !config
                .email
                .accounts
                .iter()
                .any(|a| a.id.trim().eq_ignore_ascii_case(&account_id))
            {
                return None;
            }
            Some(CalendarSource {
                account_id,
                calendar_ids,
            })
        })
        .collect();
    Ok(sources)
}

/// Loads, validates, and returns all configured email accounts.
/// Accounts without an id are silently skipped. Accounts that fail
/// validation (missing address, missing or non-gmail provider) return an Err.
///
/// # Errors
/// Returns `Err` if the config cannot be read/parsed, or an account is missing
/// its address/provider or has a non-Gmail provider.
pub fn load_all_accounts(path: &Path) -> Result<Vec<EmailAccount>, String> {
    let config = load_config(path)?;
    config
        .email
        .accounts
        .into_iter()
        .filter(|a| !a.id.trim().is_empty())
        .map(|a| {
            let id = a.id.trim().to_owned();
            let label = a.label.trim().to_owned();
            let address = crate::utils::non_empty_trimmed(&a.address)
                .ok_or_else(|| format!("email account {id} has no address"))?;
            let provider = crate::utils::non_empty_trimmed(&a.provider)
                .ok_or_else(|| format!("email account {id} has no provider"))?;
            if provider != "gmail" {
                return Err(format!("email account {id} is not a Google/Gmail account"));
            }
            Ok(EmailAccount {
                id,
                label,
                address,
                provider,
            })
        })
        .collect()
}

/// Returns the account whose `id` or `address` case-insensitively matches
/// `selector`. If `selector` is empty the first account is returned.
/// Returns `Err` if no accounts are configured or the selector does not match.
///
/// # Errors
/// Returns `Err` if `accounts` is empty or no account matches `selector`.
pub fn select_account_by_id_or_address<'a>(
    accounts: &'a [EmailAccount],
    selector: &str,
) -> Result<&'a EmailAccount, String> {
    if accounts.is_empty() {
        return Err(
            "no email accounts configured; add email account metadata to leftpanel/config.toml"
                .to_owned(),
        );
    }
    let selector = selector.trim().to_ascii_lowercase();
    if selector.is_empty() {
        return Ok(&accounts[0]);
    }
    for account in accounts {
        if account.id.trim().eq_ignore_ascii_case(&selector)
            || account.address.trim().eq_ignore_ascii_case(&selector)
        {
            return Ok(account);
        }
    }
    let available = accounts
        .iter()
        .map(|a| a.id.trim().to_owned())
        .collect::<Vec<_>>()
        .join(", ");
    Err(format!(
        "unknown email account {selector:?}; available accounts: {available}"
    ))
}
