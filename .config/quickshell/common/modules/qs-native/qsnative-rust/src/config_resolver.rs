//! `ConfigResolver` provider.
//!
//! Resolves the non-secret `leftpanel/config.toml` model/provider settings and
//! overlays Secret Service API keys into a flat `string -> string` map that the
//! left panel's `EnvLoader` consumes. Delivered to C++ as a borrowed
//! `#[repr(C)]` `ConfigEntryC` array (homogeneous KV, zero-copy); the C++
//! `QsNativeConfigResolver` `QObject` builds the `values` `QVariantMap`.

use std::collections::BTreeMap;
use std::ffi::CString;
use std::fs;
use std::os::raw::{c_char, c_void};
use std::path::PathBuf;
use std::thread;

use serde::Deserialize;

use crate::secrets;

/// Canonical default model id, also consumed by `chatstore` for new conversations.
pub(crate) const DEFAULT_MODEL: &str = "local/gpt-5.4-mini";
const DEFAULT_LOCAL_BASE_URL: &str = "http://127.0.0.1:8317/v1";
const SECRET_KEYS: [&str; 3] = ["OPENAI_API_KEY", "GEMINI_API_KEY", "LOCAL_API_KEY"];

/// A single resolved config entry, borrowed for the duration of the callback.
#[repr(C)]
pub struct ConfigEntryC {
    pub key: *const c_char,
    pub value: *const c_char,
}

/// Delivers the resolved entries (borrowed for the call only) to the C++ side.
pub type ConfigEntriesFn = unsafe extern "C" fn(*mut c_void, *const ConfigEntryC, usize);

#[derive(Debug, Clone, Default, Deserialize)]
struct Config {
    #[serde(default)]
    model: ModelConfig,
    #[serde(default)]
    providers: BTreeMap<String, ProviderConfig>,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct ModelConfig {
    #[serde(default)]
    default: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct ProviderConfig {
    #[serde(default)]
    base_url: String,
}

/// Resolves config on a background thread (Secret Service lookups block on
/// D-Bus, so they must stay off the Qt thread) and delivers the entries via
/// `cb`. `values` updates reactively through the C++ `valuesChanged` signal.
///
/// # Safety
/// `ctx`/`cb` must remain valid until `cb` fires.
#[no_mangle]
pub unsafe extern "C" fn QsNative_ConfigResolver_Refresh(ctx: *mut c_void, cb: ConfigEntriesFn) {
    let ctx = ctx as usize;
    thread::spawn(move || {
        let values = resolve_values();
        // Keep the CStrings alive across the callback; entries borrow them.
        let owned: Vec<(CString, CString)> = values
            .into_iter()
            .map(|(key, value)| {
                (
                    CString::new(key).unwrap_or_default(),
                    CString::new(value).unwrap_or_default(),
                )
            })
            .collect();
        let entries: Vec<ConfigEntryC> = owned
            .iter()
            .map(|(key, value)| ConfigEntryC {
                key: key.as_ptr(),
                value: value.as_ptr(),
            })
            .collect();
        unsafe { cb(ctx as *mut c_void, entries.as_ptr(), entries.len()) };
    });
}

fn resolve_values() -> BTreeMap<String, String> {
    let mut values = load_config(default_path()).public_values();

    for key in SECRET_KEYS {
        if let Some(secret) = secrets::lookup(key)
            .as_deref()
            .and_then(crate::utils::non_empty_trimmed)
        {
            values.insert(key.to_owned(), secret);
        }
    }

    values
}

fn load_config(path: Option<PathBuf>) -> Config {
    let Some(path) = path else {
        return Config::default().normalize();
    };

    fs::read_to_string(path)
        .ok()
        .and_then(|raw| toml::from_str::<Config>(&raw).ok())
        .unwrap_or_default()
        .normalize()
}

fn default_path() -> Option<PathBuf> {
    let path = crate::app_config::default_path();
    (!path.as_os_str().is_empty()).then_some(path)
}

impl Config {
    fn normalize(mut self) -> Self {
        self.model.default = crate::utils::first_non_empty([&self.model.default, DEFAULT_MODEL]);

        let local = self.providers.entry("local".to_owned()).or_default();
        local.base_url = crate::utils::first_non_empty([&local.base_url, DEFAULT_LOCAL_BASE_URL]);

        for provider in self.providers.values_mut() {
            provider.base_url = provider.base_url.trim().to_owned();
        }

        self
    }

    fn public_values(self) -> BTreeMap<String, String> {
        let mut values = BTreeMap::new();
        values.insert("OPENAI_MODEL".to_owned(), self.model.default.clone());

        if let Some(base_url) = self.provider_base_url("openai") {
            values.insert("OPENAI_BASE_URL".to_owned(), base_url);
        }
        if let Some(base_url) = self.provider_base_url("local") {
            values.insert("LOCAL_BASE_URL".to_owned(), base_url);
        }

        values
    }

    fn provider_base_url(&self, provider: &str) -> Option<String> {
        self.providers
            .get(provider)
            .map(|provider| provider.base_url.trim())
            .filter(|base_url| !base_url.is_empty())
            .map(str::to_owned)
    }
}

#[cfg(test)]
mod tests {
    use super::{Config, DEFAULT_LOCAL_BASE_URL, DEFAULT_MODEL};

    #[test]
    fn normalizes_defaults_and_provider_values() {
        let cfg = toml::from_str::<Config>(
            r#"
            [model]
            default = "  "

            [providers.local]
            base_url = "  "

            [providers.openai]
            base_url = " https://example.test/v1 "
            "#,
        )
        .expect("parse config")
        .normalize();

        let values = cfg.public_values();
        assert_eq!(values["OPENAI_MODEL"], DEFAULT_MODEL);
        assert_eq!(values["LOCAL_BASE_URL"], DEFAULT_LOCAL_BASE_URL);
        assert_eq!(values["OPENAI_BASE_URL"], "https://example.test/v1");
    }
}
