use core::pin::Pin;
use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;

use crate::secrets;
use cxx_qt_lib::{QMap, QMapPair_QString_QVariant, QString, QVariant};
use serde::Deserialize;

pub(crate) const DEFAULT_MODEL: &str = "local/gpt-5.4-mini";
const DEFAULT_LOCAL_BASE_URL: &str = "http://127.0.0.1:8317/v1";
const SECRET_KEYS: [&str; 3] = ["OPENAI_API_KEY", "GEMINI_API_KEY", "LOCAL_API_KEY"];

type QVariantMap = QMap<QMapPair_QString_QVariant>;

#[derive(Default)]
pub struct ConfigResolverRust {
    values: QVariantMap,
}

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

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qobject]
        #[qproperty(QMap_QString_QVariant, values)]
        type ConfigResolver = super::ConfigResolverRust;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qinvokable]
        fn refresh(self: Pin<&mut ConfigResolver>) -> bool;
    }

    impl cxx_qt::Initialize for ConfigResolver {}
}

impl cxx_qt::Initialize for ffi::ConfigResolver {
    fn initialize(self: Pin<&mut Self>) {}
}

impl ffi::ConfigResolver {
    pub fn refresh(mut self: Pin<&mut Self>) -> bool {
        self.as_mut()
            .set_values(values_to_qvariant_map(resolve_values()));
        true
    }
}

fn resolve_values() -> BTreeMap<String, String> {
    let mut values = load_config(default_path()).public_values();

    for key in SECRET_KEYS {
        if let Some(secret) = secrets::lookup(key).as_deref().and_then(crate::utils::non_empty_trimmed) {
            values.insert(key.to_owned(), secret);
        }
    }

    values
}

fn values_to_qvariant_map(values: BTreeMap<String, String>) -> QVariantMap {
    let mut out = QVariantMap::default();
    for (key, value) in values {
        out.insert(
            QString::from(key.as_str()),
            QVariant::from(&QString::from(value.as_str())),
        );
    }
    out
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
