
use crate::qobjects;
use cxx_qt::{CxxQtType, Threading};
use std::pin::Pin;
use std::time::{Duration, Instant};

use super::*;
use crate::util::runtime::tokio_runtime;

impl qobjects::AiModelCatalog {
    fn build_http_client() -> Result<rig::http_client::ReqwestClient, String> {
        rig::http_client::ReqwestClient::builder()
            .user_agent("qs-native/ai-model-catalog")
            .connect_timeout(Duration::from_secs(5))
            .timeout(Duration::from_secs(20))
            .pool_idle_timeout(Duration::from_secs(90))
            .pool_max_idle_per_host(8)
            .tcp_keepalive(Duration::from_secs(60))
            .build()
            .map_err(|e| format!("HTTP client error: {e}"))
    }

    fn set_models_json_from_list(
        mut obj: Pin<&mut qobjects::AiModelCatalog>,
        models: Vec<UiModelOption>,
    ) {
        let json = serde_json::to_string(&models).unwrap_or_else(|_| "[]".to_string());
        obj.as_mut()
            .set_models_json(cxx_qt_lib::QString::from(json));
    }

    pub fn refresh(self: Pin<&mut Self>) -> bool {
        let mut this = self;
        if this.rust().busy {
            return false;
        }

        let (openai_key, gemini_key, openai_base_url) = {
            let rust = this.rust();
            (
                rust.openai_api_key.to_string(),
                rust.gemini_api_key.to_string(),
                rust.openai_base_url.to_string(),
            )
        };

        let key_hash = model_catalog_key_hash(&openai_key, &gemini_key, &openai_base_url);

        // Serve cached results if they're fresh for the current keys/base_url.
        if let Ok(guard) = model_catalog_cache().lock() {
            if let Some(entry) = guard.as_ref() {
                if entry.key_hash == key_hash && entry.stored_at.elapsed() < MODEL_CATALOG_TTL {
                    this.as_mut().set_busy(false);
                    this.as_mut()
                        .set_status(cxx_qt_lib::QString::from("Ready (cached)"));
                    this.as_mut().set_error(cxx_qt_lib::QString::from(""));
                    this.as_mut()
                        .set_models_json(cxx_qt_lib::QString::from(entry.models_json.clone()));
                    return true;
                }
            }
        }

        // If no keys are available, don't spam network calls.
        if openai_key.trim().is_empty() && gemini_key.trim().is_empty() {
            this.as_mut().set_busy(false);
            this.as_mut()
                .set_status(cxx_qt_lib::QString::from("No API keys (static list)"));
            this.as_mut().set_error(cxx_qt_lib::QString::from(""));
            let models = PINNED_MODELS
                .iter()
                .map(|m| UiModelOption {
                    value: m.value.to_string(),
                    label: m.label.to_string(),
                    description: m.description.to_string(),
                    provider: m.provider.to_string(),
                    recommended: true,
                })
                .collect::<Vec<_>>();
            Self::set_models_json_from_list(this.as_mut(), models);
            return true;
        }

        let qt_thread = this.qt_thread();
        this.as_mut().set_busy(true);
        this.as_mut().set_status(cxx_qt_lib::QString::from("Loading..."));
        this.as_mut().set_error(cxx_qt_lib::QString::from(""));
        Self::set_models_json_from_list(this.as_mut(), Vec::new());

        tokio_runtime().spawn(async move {
            let http_client = match Self::build_http_client() {
                Ok(c) => c,
                Err(err) => {
                    qt_thread
                        .queue(move |mut obj| {
                            obj.as_mut().set_busy(false);
                            obj.as_mut().set_status(cxx_qt_lib::QString::from("Error"));
                            obj.as_mut().set_error(cxx_qt_lib::QString::from(err.clone()));
                            Self::set_models_json_from_list(obj.as_mut(), Vec::new());
                        })
                        .ok();
                    return;
                }
            };

            let mut by_value: HashMap<String, UiModelOption> = HashMap::new();
            let mut errors: Vec<String> = Vec::new();

            // OpenAI: GET /models
            if !openai_key.trim().is_empty() {
                let mut builder =
                    rig::providers::openai::Client::<rig::http_client::ReqwestClient>::builder()
                        .api_key(openai_key.trim())
                        .http_client(http_client.clone());
                if !openai_base_url.trim().is_empty() {
                    builder = builder.base_url(openai_base_url.trim());
                }
                match builder.build() {
                    Ok(client) => {
                        let result: Result<Vec<String>, String> = async {
                            let req = client
                                .get("/models")
                                .map_err(|e| format!("OpenAI request build failed: {e}"))?
                                .body(rig::http_client::NoBody)
                                .map_err(|e| format!("OpenAI request build failed: {e}"))?;
                            let response = http_client
                                .send::<_, Vec<u8>>(req)
                                .await
                                .map_err(|e| format!("OpenAI request failed: {e}"))?;
                            let status = response.status();
                            let body: Vec<u8> =
                                response.into_body().await.map_err(|e| e.to_string())?;
                            if !status.is_success() {
                                let msg = try_extract_error_message_from_json(&body)
                                    .unwrap_or_else(|| String::from_utf8_lossy(&body).to_string());
                                return Err(format!("OpenAI HTTP {status}: {msg}"));
                            }

                            let v: serde_json::Value =
                                serde_json::from_slice(&body).map_err(|e| e.to_string())?;
                            let ids = v
                                .get("data")
                                .and_then(|d| d.as_array())
                                .map(|arr| {
                                    arr.iter()
                                        .filter_map(|m| m.get("id").and_then(|id| id.as_str()))
                                        .map(|s| s.to_string())
                                        .collect::<Vec<_>>()
                                })
                                .unwrap_or_default();
                            Ok(ids)
                        }
                        .await;

                        match result {
                            Ok(ids) => {
                                for id in ids {
                                    let id = id.trim().to_string();
                                    if id.is_empty() {
                                        continue;
                                    }
                                    if !openai_model_allowed(&id) {
                                        continue;
                                    }
                                    by_value.entry(id.clone()).or_insert(UiModelOption {
                                        value: id.clone(),
                                        label: id.clone(),
                                        description: "".to_string(),
                                        provider: "openai".to_string(),
                                        recommended: false,
                                    });
                                }
                            }
                            Err(err) => errors.push(err),
                        }
                    }
                    Err(err) => errors.push(format!("OpenAI client error: {err}")),
                }
            }

            // Gemini: GET /v1beta/models
            if !gemini_key.trim().is_empty() {
                let builder =
                    rig::providers::gemini::Client::<rig::http_client::ReqwestClient>::builder()
                        .api_key(gemini_key.trim())
                        .http_client(http_client.clone());
                match builder.build() {
                    Ok(client) => {
                        let result: Result<Vec<UiModelOption>, String> = async {
                            let req = client
                                .get("/v1beta/models")
                                .map_err(|e| format!("Gemini request build failed: {e}"))?
                                .body(rig::http_client::NoBody)
                                .map_err(|e| format!("Gemini request build failed: {e}"))?;
                            let response = http_client
                                .send::<_, Vec<u8>>(req)
                                .await
                                .map_err(|e| format!("Gemini request failed: {e}"))?;
                            let status = response.status();
                            let body: Vec<u8> =
                                response.into_body().await.map_err(|e| e.to_string())?;
                            if !status.is_success() {
                                let msg = try_extract_error_message_from_json(&body)
                                    .unwrap_or_else(|| String::from_utf8_lossy(&body).to_string());
                                return Err(format!("Gemini HTTP {status}: {msg}"));
                            }
                            let v: serde_json::Value =
                                serde_json::from_slice(&body).map_err(|e| e.to_string())?;
                            let models = v.get("models").and_then(|m| m.as_array());
                            let mut out: Vec<UiModelOption> = Vec::new();
                            let Some(models) = models else {
                                return Ok(out);
                            };

                            for m in models {
                                let name = m.get("name").and_then(|n| n.as_str()).unwrap_or("");
                                if name.is_empty() {
                                    continue;
                                }

                                let mut id = name.trim().to_string();
                                if let Some(rest) = id.strip_prefix("models/") {
                                    id = rest.to_string();
                                }
                                if !id.starts_with("gemini-") {
                                    continue;
                                }

                                // Only show models that can actually chat.
                                let methods = m
                                    .get("supportedGenerationMethods")
                                    .and_then(|x| x.as_array())
                                    .cloned()
                                    .unwrap_or_default();
                                let supports_generate = methods
                                    .iter()
                                    .any(|v| v.as_str() == Some("generateContent"));
                                if !supports_generate {
                                    continue;
                                }

                                let label = m
                                    .get("displayName")
                                    .and_then(|x| x.as_str())
                                    .unwrap_or("")
                                    .trim()
                                    .to_string();
                                let description = m
                                    .get("description")
                                    .and_then(|x| x.as_str())
                                    .unwrap_or("")
                                    .trim()
                                    .to_string();

                                out.push(UiModelOption {
                                    value: id.clone(),
                                    label: if label.is_empty() { id.clone() } else { label },
                                    description,
                                    provider: "gemini".to_string(),
                                    recommended: false,
                                });
                            }

                            Ok(out)
                        }
                        .await;

                        match result {
                            Ok(models) => {
                                for model in models {
                                    by_value.entry(model.value.clone()).or_insert(model);
                                }
                            }
                            Err(err) => errors.push(err),
                        }
                    }
                    Err(err) => errors.push(format!("Gemini client error: {err}")),
                }
            }

            // Ensure pinned models are always available in the picker, even if a provider did not
            // return them in the listing (or the listing call partially failed).
            for pin in PINNED_MODELS.iter() {
                by_value.entry(pin.value.to_string()).or_insert(UiModelOption {
                    value: pin.value.to_string(),
                    label: pin.label.to_string(),
                    description: pin.description.to_string(),
                    provider: pin.provider.to_string(),
                    recommended: true,
                });
            }

            let mut models: Vec<UiModelOption> = by_value.into_values().collect();
            apply_pinned_models(&mut models);

            let status = if errors.is_empty() {
                "Ready".to_string()
            } else if models.is_empty() {
                "Error".to_string()
            } else {
                "Ready (partial)".to_string()
            };
            let error = errors.join("; ");

            let models_json = serde_json::to_string(&models).unwrap_or_else(|_| "[]".to_string());
            if errors.is_empty() && !models_json.is_empty() && models_json != "[]" {
                if let Ok(mut guard) = model_catalog_cache().lock() {
                    *guard = Some(ModelCatalogCacheEntry {
                        key_hash,
                        stored_at: Instant::now(),
                        models_json: models_json.clone(),
                    });
                }
            }

            qt_thread
                .queue(move |mut obj| {
                    obj.as_mut().set_busy(false);
                    obj.as_mut().set_status(cxx_qt_lib::QString::from(status));
                    obj.as_mut().set_error(cxx_qt_lib::QString::from(error));
                    obj.as_mut()
                        .set_models_json(cxx_qt_lib::QString::from(models_json));
                })
                .ok();
        });

        true
    }
}
