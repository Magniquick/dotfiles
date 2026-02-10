
use crate::qobjects;
use cxx_qt::{CxxQtType, Threading};
use futures_util::StreamExt;
use std::fs;
use std::io::Write;
use std::path::Path;
use std::pin::Pin;

use super::*;
use crate::util::runtime::tokio_runtime;
use crate::AiChatSessionRust;

fn percent_decode(s: &str) -> String {
    // Minimal percent-decoder for file:// URIs.
    let mut out = String::with_capacity(s.len());
    let bytes = s.as_bytes();
    let mut i = 0usize;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            let h1 = bytes[i + 1];
            let h2 = bytes[i + 2];
            let v1 = (h1 as char).to_digit(16);
            let v2 = (h2 as char).to_digit(16);
            if let (Some(a), Some(b)) = (v1, v2) {
                out.push((u8::try_from(a * 16 + b).unwrap_or(b'?')) as char);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i] as char);
        i += 1;
    }
    out
}

fn parse_uri_list_to_paths(uri_list: &str) -> Vec<String> {
    // text/uri-list: newline-separated URIs, may include comments starting with '#'
    // We only accept local file:// URIs.
    let mut out: Vec<String> = Vec::new();
    for line in uri_list.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(rest) = line.strip_prefix("file://") {
            // file:///path or file://localhost/path. Reject other hosts.
            let rest = rest.trim();
            if rest.starts_with('/') {
                out.push(percent_decode(rest));
                continue;
            }
            if let Some(after_host) = rest.strip_prefix("localhost") {
                if after_host.starts_with('/') {
                    out.push(percent_decode(after_host));
                    continue;
                }
            }
            // file://<host>/... not supported; ignore.
        }
    }
    out
}

fn looks_like_pdf_attachment(a: &ChatAttachment) -> bool {
    let mime = a.mime.trim().to_lowercase();
    if mime == "application/pdf" {
        return true;
    }
    let path = a.path.trim().to_lowercase();
    path.ends_with(".pdf")
}

fn pdf_label_from_path(path: &str) -> String {
    // Best-effort, purely for user-visible labels in the prompt.
    Path::new(path)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("document.pdf")
        .to_string()
}

fn pdf_extract_to_string(path: &str) -> Result<String, String> {
    pdf_extract::extract_text(Path::new(path)).map_err(|e| format!("{e}"))
}

impl qobjects::AiChatSession {
    const ROLE_MESSAGE_ID: i32 = 256 + 1;
    const ROLE_SENDER: i32 = 256 + 2;
    const ROLE_BODY: i32 = 256 + 3;
    const ROLE_KIND: i32 = 256 + 4;

    pub fn row_count(&self, parent: &cxx_qt_lib::QModelIndex) -> i32 {
        // Flat list model, no children.
        if parent.is_valid() {
            return 0;
        }
        let len: usize = self.rust().messages.len();
        i32::try_from(len).unwrap_or(i32::MAX)
    }

    pub fn data(&self, index: &cxx_qt_lib::QModelIndex, role: i32) -> cxx_qt_lib::QVariant {
        if !index.is_valid() {
            return cxx_qt_lib::QVariant::default();
        }
        let row = index.row();
        if row < 0 {
            return cxx_qt_lib::QVariant::default();
        }
        let row: usize = match usize::try_from(row) {
            Ok(v) => v,
            Err(_) => return cxx_qt_lib::QVariant::default(),
        };

        let Some(msg) = self.rust().messages.get(row) else {
            return cxx_qt_lib::QVariant::default();
        };

        match role {
            Self::ROLE_MESSAGE_ID => cxx_qt_lib::QVariant::from(&cxx_qt_lib::QString::from(&msg.message_id)),
            Self::ROLE_SENDER => cxx_qt_lib::QVariant::from(&cxx_qt_lib::QString::from(&msg.sender)),
            Self::ROLE_BODY => cxx_qt_lib::QVariant::from(&cxx_qt_lib::QString::from(&msg.body)),
            Self::ROLE_KIND => cxx_qt_lib::QVariant::from(&cxx_qt_lib::QString::from(&msg.kind)),
            _ => cxx_qt_lib::QVariant::default(),
        }
    }

    pub fn role_names(&self) -> cxx_qt_lib::QHash<cxx_qt_lib::QHashPair_i32_QByteArray> {
        let mut out: cxx_qt_lib::QHash<cxx_qt_lib::QHashPair_i32_QByteArray> =
            cxx_qt_lib::QHash::default();
        out.insert_clone(&Self::ROLE_MESSAGE_ID, &cxx_qt_lib::QByteArray::from("messageId"));
        out.insert_clone(&Self::ROLE_SENDER, &cxx_qt_lib::QByteArray::from("sender"));
        out.insert_clone(&Self::ROLE_BODY, &cxx_qt_lib::QByteArray::from("body"));
        out.insert_clone(&Self::ROLE_KIND, &cxx_qt_lib::QByteArray::from("kind"));
        out
    }

    fn ensure_initialized(mut self: Pin<&mut Self>) {
        let needs_init = {
            let this = self.as_mut();
            this.rust().messages.is_empty()
        };
        if !needs_init {
            return;
        }

        self.as_mut().set_busy(false);
        self.as_mut().set_status(cxx_qt_lib::QString::from("Ready"));
        self.as_mut().set_error(cxx_qt_lib::QString::from(""));

        // Bootstrap messages.
        let mut this = self;
        Self::append_message(
            this.as_mut(),
            "assistant",
            "Hi! This panel is wired to OpenAI/Gemini chat via qs-native.".to_string(),
            "info",
        );
        Self::append_message(
            this.as_mut(),
            "assistant",
            "Set OPENAI_API_KEY or GEMINI_API_KEY to enable replies.".to_string(),
            "info",
        );
    }

    fn next_id(rust: &mut AiChatSessionRust) -> String {
        rust.id_counter = rust.id_counter.saturating_add(1);
        format!(
            "{}-{}",
            chrono::Utc::now().timestamp_millis(),
            rust.id_counter
        )
    }

    fn fmt_opt_time(t: Option<DateTime<Utc>>) -> String {
        match t {
            Some(dt) => dt.to_rfc3339(),
            None => "never".to_string(),
        }
    }

    fn append_message(
        mut obj: Pin<&mut qobjects::AiChatSession>,
        sender: &str,
        body: String,
        kind: &str,
    ) -> String {
        let (row, message_id) = {
            let rust = obj.as_mut().rust_mut();
            let rust = rust.get_mut();
            let message_id = Self::next_id(rust);
            let row = i32::try_from(rust.messages.len()).unwrap_or(i32::MAX);
            (row, message_id)
        };

        let parent = cxx_qt_lib::QModelIndex::default();
        obj.as_mut().begin_insert_rows(&parent, row, row);
        {
            let rust = obj.as_mut().rust_mut();
            let rust = rust.get_mut();
            rust.messages.push(ChatMessage {
                message_id: message_id.clone(),
                sender: sender.to_string(),
                body,
                kind: kind.to_string(),
            });
        }
        obj.as_mut().end_insert_rows();

        message_id
    }

    fn remove_message(mut obj: Pin<&mut qobjects::AiChatSession>, message_id: &str) -> bool {
        let idx_opt = {
            let rust = obj.as_mut().rust_mut();
            let rust = rust.get_mut();
            rust.messages.iter().position(|m| m.message_id == message_id)
        };
        let Some(idx) = idx_opt else { return false; };

        let idx_i32 = i32::try_from(idx).unwrap_or(i32::MAX);
        let parent = cxx_qt_lib::QModelIndex::default();
        obj.as_mut().begin_remove_rows(&parent, idx_i32, idx_i32);
        {
            let rust = obj.as_mut().rust_mut();
            let rust = rust.get_mut();
            if idx < rust.messages.len() {
                rust.messages.remove(idx);
            }
        }
        obj.as_mut().end_remove_rows();
        true
    }

    fn has_required_api_key(model_id: &str, openai_key: &str, gemini_key: &str) -> bool {
        if model_id.starts_with("gemini") {
            !gemini_key.is_empty()
        } else {
            !openai_key.is_empty()
        }
    }

    fn build_http_client() -> Result<rig::http_client::ReqwestClient, String> {
        // Reuse this client across requests to benefit from connection pooling/keepalive.
        rig::http_client::ReqwestClient::builder()
            .user_agent("qs-native/ai-chat")
            .connect_timeout(Duration::from_secs(5))
            .timeout(Duration::from_secs(45))
            .pool_idle_timeout(Duration::from_secs(90))
            .pool_max_idle_per_host(8)
            .tcp_keepalive(Duration::from_secs(60))
            .build()
            .map_err(|e| format!("HTTP client error: {e}"))
    }

    fn get_or_build_http_client(
        rust: &mut AiChatSessionRust,
    ) -> Result<rig::http_client::ReqwestClient, String> {
        if let Some(cached) = rust.http_client.clone() {
            return Ok(cached);
        }
        let client = Self::build_http_client()?;
        rust.http_client = Some(client.clone());
        Ok(client)
    }

    fn get_or_build_openai_completions(
        rust: &mut AiChatSessionRust,
        http_client: rig::http_client::ReqwestClient,
        api_key: &str,
        base_url: &str,
    ) -> Result<rig::providers::openai::CompletionsClient<rig::http_client::ReqwestClient>, String>
    {
        let base_url = base_url.trim();
        if let Some(cache) = rust.openai_cache.as_ref() {
            if cache.api_key == api_key && cache.base_url == base_url {
                return Ok(cache.completions.clone());
            }
        }

        let mut builder =
            rig::providers::openai::Client::<rig::http_client::ReqwestClient>::builder()
                .api_key(api_key)
                .http_client(http_client);
        if !base_url.is_empty() {
            builder = builder.base_url(base_url);
        }
        let client = builder
            .build()
            .map_err(|e| format!("OpenAI client error: {e}"))?;
        let completions = client.completions_api();

        rust.openai_cache = Some(OpenAiCache {
            api_key: api_key.to_string(),
            base_url: base_url.to_string(),
            completions: completions.clone(),
        });

        Ok(completions)
    }

    fn get_or_build_gemini_client(
        rust: &mut AiChatSessionRust,
        http_client: rig::http_client::ReqwestClient,
        api_key: &str,
    ) -> Result<rig::providers::gemini::Client<rig::http_client::ReqwestClient>, String> {
        if let Some(cache) = rust.gemini_cache.as_ref() {
            if cache.api_key == api_key {
                return Ok(cache.client.clone());
            }
        }

        let client =
            rig::providers::gemini::Client::<rig::http_client::ReqwestClient>::builder()
                .api_key(api_key)
                .http_client(http_client)
                .build()
                .map_err(|e| format!("Gemini client error: {e}"))?;

        rust.gemini_cache = Some(GeminiCache {
            api_key: api_key.to_string(),
            client: client.clone(),
        });

        Ok(client)
    }

    pub fn append_info(mut self: Pin<&mut Self>, text: &cxx_qt_lib::QString) {
        self.as_mut().ensure_initialized();
        let text = text.to_string();
        let mut this = self;
        Self::append_message(this.as_mut(), "assistant", text, "info");
        this.as_mut().scroll_to_end_requested();
    }

    pub fn reset_for_model_switch(mut self: Pin<&mut Self>, model_id: &cxx_qt_lib::QString) {
        self.as_mut().ensure_initialized();
        let model_id = model_id.to_string();
        let mut this = self;
        this.as_mut().begin_reset_model();
        {
            let rust = this.as_mut().rust_mut();
            let rust = rust.get_mut();
            rust.messages.clear();
        }
        this.as_mut().end_reset_model();
        Self::append_message(
            this.as_mut(),
            "assistant",
            format!("Switched to {model_id}. Chat history cleared."),
            "info",
        );
        this.as_mut().scroll_to_end_requested();
    }

    pub fn copy_all_text(mut self: Pin<&mut Self>) -> cxx_qt_lib::QString {
        self.as_mut().ensure_initialized();
        let rust = self.as_mut().rust_mut();
        let rust = rust.get_mut();
        let mut lines: Vec<String> = Vec::new();
        for m in &rust.messages {
            if m.kind == "info" {
                continue;
            }
            let name = if m.sender == "user" {
                "user"
            } else {
                "assistant"
            };
            lines.push(format!("*{name}*: {}", m.body));
        }
        cxx_qt_lib::QString::from(lines.join("\n"))
    }

    pub fn delete_message(mut self: Pin<&mut Self>, message_id: &cxx_qt_lib::QString) {
        self.as_mut().ensure_initialized();
        let message_id = message_id.to_string();
        let mut this = self;
        let _ = Self::remove_message(this.as_mut(), &message_id);
    }

    pub fn edit_message(
        mut self: Pin<&mut Self>,
        message_id: &cxx_qt_lib::QString,
        new_body: &cxx_qt_lib::QString,
    ) {
        self.as_mut().ensure_initialized();
        let message_id = message_id.to_string();
        let new_body = new_body.to_string();
        let mut this = self;
        let changed_idx: Option<usize> = {
            let rust = this.as_mut().rust_mut();
            let rust = rust.get_mut();
            if let Some((idx, msg)) = rust
                .messages
                .iter_mut()
                .enumerate()
                .find(|(_, m)| m.message_id == message_id)
            {
                msg.body = new_body;
                Some(idx)
            } else {
                None
            }
        };
        if let Some(idx) = changed_idx {
            let row = i32::try_from(idx).unwrap_or(i32::MAX);
            let parent = cxx_qt_lib::QModelIndex::default();
            let model_index = this.as_ref().index_for_row(row, 0, &parent);
            let mut roles: cxx_qt_lib::QList<i32> = cxx_qt_lib::QList::default();
            roles.append(Self::ROLE_BODY);
            this.as_mut().data_changed(&model_index, &model_index, &roles);
        }
    }

    pub fn regenerate(mut self: Pin<&mut Self>, message_id: &cxx_qt_lib::QString) {
        self.as_mut().ensure_initialized();
        let target_id = message_id.to_string();
        let mut this = self;
        let user_idx: usize = {
            let rust = this.as_mut().rust_mut();
            let rust = rust.get_mut();

            if rust.busy {
                return;
            }

            let idx = match rust.messages.iter().position(|m| m.message_id == target_id) {
                Some(i) => i,
                None => return,
            };
            if rust.messages.get(idx).map(|m| m.sender.as_str()) != Some("assistant") {
                return;
            }

            // Find previous user message.
            let mut user_idx: Option<usize> = None;
            for i in (0..idx).rev() {
                if rust.messages[i].sender == "user" && rust.messages[i].kind == "chat" {
                    user_idx = Some(i);
                    break;
                }
            }
            match user_idx {
                Some(i) => i,
                None => return,
            }
        };

        // Truncate to just after the user message.
        this.as_mut().begin_reset_model();
        {
            let rust = this.as_mut().rust_mut();
            let rust = rust.get_mut();
            rust.messages.truncate(user_idx + 1);
        }
        this.as_mut().end_reset_model();

        let prompt = {
            let this2 = this.as_mut();
            this2.rust().messages[user_idx].body.clone()
        };

        // Re-run as if the user just sent this prompt.
        this.as_mut()
            .submit_input(&cxx_qt_lib::QString::from(prompt));
    }

    pub fn paste_image_from_clipboard(mut self: Pin<&mut Self>) -> cxx_qt_lib::QString {
        self.as_mut().ensure_initialized();

        fn try_wl_paste_bytes(mime: &str) -> Option<Vec<u8>> {
            let out = Command::new("wl-paste")
                .arg("--type")
                .arg(mime)
                .output()
                .ok()?;
            if !out.status.success() || out.stdout.is_empty() {
                return None;
            }
            Some(out.stdout)
        }

        // NOTE: Wayland clipboard access requires the Quickshell window to be focused.
        // For images, we rely on wl-clipboard since Quickshell only exposes clipboardText.
        let (mime, bytes) = if let Some(b) = try_wl_paste_bytes("image/png") {
            ("image/png".to_string(), b)
        } else if let Some(b) = try_wl_paste_bytes("image/jpeg") {
            ("image/jpeg".to_string(), b)
        } else if let Some(b) = try_wl_paste_bytes("image/webp") {
            ("image/webp".to_string(), b)
        } else {
            return cxx_qt_lib::QString::from("");
        };

        // Keep a conservative bound; we're going to base64 it and ship it over JSON.
        const MAX_IMAGE_BYTES: usize = 8 * 1024 * 1024;
        if bytes.len() > MAX_IMAGE_BYTES {
            self.as_mut().append_info(&cxx_qt_lib::QString::from(format!(
                "Clipboard image too large ({} bytes; max {}).",
                bytes.len(),
                MAX_IMAGE_BYTES
            )));
            return cxx_qt_lib::QString::from("");
        }

        let ext = if mime == "image/png" {
            "png"
        } else if mime == "image/jpeg" {
            "jpg"
        } else {
            "img"
        };

        let dir = Path::new("/tmp/quickshell-ai-paste");
        let _ = fs::create_dir_all(dir);
        let filename = format!("paste-{}.{}", Utc::now().timestamp_millis(), ext);
        let path = dir.join(filename);
        if let Ok(mut f) = fs::File::create(&path) {
            let _ = f.write_all(&bytes);
        }

        let b64 = BASE64_STANDARD.encode(&bytes);
        let attachment = ChatAttachment {
            mime,
            b64,
            path: path.to_string_lossy().to_string(),
        };
        match serde_json::to_string(&attachment) {
            Ok(s) => cxx_qt_lib::QString::from(s),
            Err(_) => cxx_qt_lib::QString::from(""),
        }
    }

    pub fn paste_attachment_from_clipboard(mut self: Pin<&mut Self>) -> cxx_qt_lib::QString {
        self.as_mut().ensure_initialized();

        let out = Command::new("wl-paste")
            .arg("--type")
            .arg("text/uri-list")
            .output();
        let Ok(out) = out else {
            return cxx_qt_lib::QString::from("");
        };
        if !out.status.success() || out.stdout.is_empty() {
            return cxx_qt_lib::QString::from("");
        }

        let raw = String::from_utf8_lossy(&out.stdout).to_string();
        let paths = parse_uri_list_to_paths(&raw);
        if paths.is_empty() {
            return cxx_qt_lib::QString::from("");
        }

        // Convert the clipboard file list to attachments. For images, we eagerly base64 so we can
        // send to providers that accept images. For PDFs, we send the path and extract text later.
        const MAX_IMAGE_BYTES: usize = 8 * 1024 * 1024;
        let mut attachments: Vec<ChatAttachment> = Vec::new();
        for path in paths.into_iter() {
            let lp = path.to_lowercase();
            if lp.ends_with(".pdf") {
                attachments.push(ChatAttachment {
                    mime: "application/pdf".to_string(),
                    b64: "".to_string(),
                    path,
                });
                continue;
            }

            let (mime, _ext) = if lp.ends_with(".png") {
                ("image/png", "png")
            } else if lp.ends_with(".jpg") || lp.ends_with(".jpeg") {
                ("image/jpeg", "jpg")
            } else if lp.ends_with(".webp") {
                ("image/webp", "webp")
            } else {
                // Unsupported file type for now.
                continue;
            };

            let Ok(bytes) = fs::read(&path) else {
                continue;
            };
            if bytes.len() > MAX_IMAGE_BYTES {
                self.as_mut().append_info(&cxx_qt_lib::QString::from(format!(
                    "Image file too large ({} bytes; max {}).",
                    bytes.len(),
                    MAX_IMAGE_BYTES
                )));
                continue;
            }

            attachments.push(ChatAttachment {
                mime: mime.to_string(),
                b64: BASE64_STANDARD.encode(&bytes),
                path: path.clone(),
            });
        }

        if attachments.is_empty() {
            return cxx_qt_lib::QString::from("");
        }

        match serde_json::to_string(&attachments) {
            Ok(s) => cxx_qt_lib::QString::from(s),
            Err(_) => cxx_qt_lib::QString::from(""),
        }
    }

    pub fn submit_input_with_attachments(
        mut self: Pin<&mut Self>,
        text: &cxx_qt_lib::QString,
        attachments_json: &cxx_qt_lib::QString,
    ) {
        self.as_mut().ensure_initialized();

        let raw = text.to_string();
        let input = raw.trim();
        let attachments_raw = attachments_json.to_string();

        let attachments: Vec<ChatAttachment> =
            serde_json::from_str(&attachments_raw).unwrap_or_else(|_| Vec::new());

        // If this is a command, route through the normal handler (attachments ignored).
        if input.starts_with('/') {
            self.as_mut().submit_input(text);
            return;
        }

        // Allow image-only sends.
        if input.is_empty() && attachments.is_empty() {
            return;
        }

        let mut this = self;
        let qt_thread = this.qt_thread();

        let (model_id, system_prompt, openai_key, gemini_key, base_url, busy) = {
            let rust = this.as_mut().rust_mut();
            let rust = rust.get_mut();
            (
                rust.model_id.to_string(),
                rust.system_prompt.to_string(),
                rust.openai_api_key.to_string(),
                rust.gemini_api_key.to_string(),
                rust.openai_base_url.to_string(),
                rust.busy,
            )
        };

        if busy {
            return;
        }

        // Append user message immediately (store a small marker so conversation logs show that an image was sent).
        let mut stored_body = input.to_string();
        if !attachments.is_empty() {
            let mut image_count: usize = 0;
            let mut pdf_count: usize = 0;
            let mut other_count: usize = 0;
            for a in attachments.iter() {
                if looks_like_pdf_attachment(a) {
                    pdf_count = pdf_count.saturating_add(1);
                    continue;
                }
                let media_type = image_media_type_from_mime(a.mime.trim());
                if media_type.is_some() && !a.b64.trim().is_empty() {
                    image_count = image_count.saturating_add(1);
                } else {
                    other_count = other_count.saturating_add(1);
                }
            }

            if !stored_body.is_empty() {
                stored_body.push_str("\n\n");
            }
            let mut parts: Vec<String> = Vec::new();
            if image_count > 0 {
                parts.push(format!(
                    "{} image{}",
                    image_count,
                    if image_count == 1 { "" } else { "s" }
                ));
            }
            if pdf_count > 0 {
                parts.push(format!(
                    "{} pdf{}",
                    pdf_count,
                    if pdf_count == 1 { "" } else { "s" }
                ));
            }
            if other_count > 0 {
                parts.push(format!(
                    "{} file{}",
                    other_count,
                    if other_count == 1 { "" } else { "s" }
                ));
            }
            if parts.is_empty() {
                parts.push(format!(
                    "{} attachment{}",
                    attachments.len(),
                    if attachments.len() == 1 { "" } else { "s" }
                ));
            }
            stored_body.push_str(&format!("[Attached {}]", parts.join(", ")));
        }
        Self::append_message(this.as_mut(), "user", stored_body, "chat");
        this.as_mut().scroll_to_end_requested();

        if !Self::has_required_api_key(&model_id, &openai_key, &gemini_key) {
            let key_name = if model_id.starts_with("gemini") {
                "GEMINI_API_KEY"
            } else {
                "OPENAI_API_KEY"
            };
            this.as_mut()
                .append_info(&cxx_qt_lib::QString::from(format!(
                    "Set {key_name} to enable replies."
                )));
            return;
        }

        // Build conversation history excluding info messages and excluding the last user prompt
        // (the prompt we just inserted into the model). We always use the raw `input` string as
        // the text part so we don't send UI markers like "[Attached 1 image]" to the provider.
        let history_msgs = {
            let rust = this.as_mut().rust_mut();
            let rust = rust.get_mut();

            let mut convo: Vec<ChatMessage> = rust
                .messages
                .iter()
                .filter(|m| m.kind == "chat")
                .cloned()
                .collect();
            if !convo.is_empty() {
                convo.pop();
            }
            convo
        };
        let prompt_text = input.to_string();

        // HTTP client
        let http_client = {
            let rust = this.as_mut().rust_mut();
            let rust = rust.get_mut();
            match Self::get_or_build_http_client(rust) {
                Ok(c) => c,
                Err(err) => {
                    this.as_mut().set_status(cxx_qt_lib::QString::from("Error"));
                    this.as_mut().set_error(cxx_qt_lib::QString::from(err.clone()));
                    Self::append_message(
                        this.as_mut(),
                        "assistant",
                        format!("Error: {err}"),
                        "info",
                    );
                    this.as_mut().scroll_to_end_requested();
                    return;
                }
            }
        };

        // Build/reuse provider clients (cached) so we keep connections alive and keep provider
        // differences behind rig.
        let provider_is_gemini = model_id.starts_with("gemini");
        let (openai_client, gemini_client) = {
            let rust = this.as_mut().rust_mut();
            let rust = rust.get_mut();
            if provider_is_gemini {
                match Self::get_or_build_gemini_client(rust, http_client.clone(), &gemini_key) {
                    Ok(client) => (None, Some(client)),
                    Err(err) => {
                        this.as_mut().set_status(cxx_qt_lib::QString::from("Error"));
                        this.as_mut()
                            .set_error(cxx_qt_lib::QString::from(err.clone()));
                        Self::append_message(
                            this.as_mut(),
                            "assistant",
                            format!("Error: {err}"),
                            "info",
                        );
                        this.as_mut().scroll_to_end_requested();
                        return;
                    }
                }
            } else {
                match Self::get_or_build_openai_completions(
                    rust,
                    http_client.clone(),
                    &openai_key,
                    &base_url,
                ) {
                    Ok(client) => (Some(client), None),
                    Err(err) => {
                        this.as_mut().set_status(cxx_qt_lib::QString::from("Error"));
                        this.as_mut()
                            .set_error(cxx_qt_lib::QString::from(err.clone()));
                        Self::append_message(
                            this.as_mut(),
                            "assistant",
                            format!("Error: {err}"),
                            "info",
                        );
                        this.as_mut().scroll_to_end_requested();
                        return;
                    }
                }
            }
        };

        {
            let rust = this.as_mut().rust_mut();
            let rust = rust.get_mut();
            rust.last_request_at = Some(Utc::now());
            rust.last_latency_ms = None;
            this.as_mut().set_busy(true);
            this.as_mut().set_error(cxx_qt_lib::QString::from(""));
            this.as_mut()
                .set_status(cxx_qt_lib::QString::from("Thinking..."));
        }

        let assistant_message_id =
            Self::append_message(this.as_mut(), "assistant", "".to_string(), "chat");
        this.as_mut().scroll_to_end_requested();

        let started = Instant::now();
        tokio_runtime().spawn(async move {
            let result: Result<(), String> = async {
                let prompt_msg = {
                    let mut parts: Vec<UserContent> = Vec::new();
                    if !prompt_text.trim().is_empty() {
                        parts.push(UserContent::text(prompt_text));
                    }
                    // Attachments: images are sent as image parts; PDFs are converted to text and injected as text parts.
                    // This keeps the same "attachments_json" pathway used by image paste/addition, but makes PDFs usable.
                    const MAX_PDF_TEXT_CHARS: usize = 100_000;
                    const MAX_PDF_BYTES: usize = 25 * 1024 * 1024;
                    for a in attachments.into_iter() {
                        if looks_like_pdf_attachment(&a) {
                            // Prefer reading from `path`; if missing, fall back to decoding `b64` into a temp file.
                            let mut pdf_path = a.path.trim().to_string();
                            let mut temp_path: Option<String> = None;
                            if pdf_path.is_empty() {
                                let b64 = a.b64.trim();
                                if !b64.is_empty() {
                                    if let Ok(bytes) = BASE64_STANDARD.decode(b64.as_bytes()) {
                                        if bytes.len() > MAX_PDF_BYTES {
                                            let label = "document.pdf";
                                            parts.push(UserContent::text(format!(
                                                "PDF ({label}) was too large to attach ({} bytes; max {}).",
                                                bytes.len(),
                                                MAX_PDF_BYTES
                                            )));
                                            continue;
                                        }
                                        let dir = Path::new("/tmp/quickshell-ai-attach");
                                        let _ = fs::create_dir_all(dir);
                                        let filename =
                                            format!("attach-{}.pdf", Utc::now().timestamp_millis());
                                        let path = dir.join(filename);
                                        if let Ok(mut f) = fs::File::create(&path) {
                                            let _ = f.write_all(&bytes);
                                            pdf_path = path.to_string_lossy().to_string();
                                            temp_path = Some(pdf_path.clone());
                                        }
                                    }
                                }
                            }

                            if pdf_path.is_empty() {
                                continue;
                            }

                            let label = pdf_label_from_path(&pdf_path);
                            if let Ok(meta) = fs::metadata(&pdf_path) {
                                if meta.len() as usize > MAX_PDF_BYTES {
                                    parts.push(UserContent::text(format!(
                                        "PDF ({label}) was too large to attach ({} bytes; max {}).",
                                        meta.len(),
                                        MAX_PDF_BYTES
                                    )));
                                    // Clean up temp PDF if we created one from base64.
                                    if let Some(tp) = temp_path {
                                        let _ = fs::remove_file(tp);
                                    }
                                    continue;
                                }
                            }
                            let extracted_res: Result<String, String> =
                                match tokio::task::spawn_blocking(move || pdf_extract_to_string(&pdf_path)).await {
                                    Ok(inner) => inner,
                                    Err(e) => Err(format!("PDF extraction task failed: {e}")),
                                };

                            // Clean up temp PDF if we created one from base64.
                            if let Some(tp) = temp_path {
                                let _ = fs::remove_file(tp);
                            }

                            match extracted_res {
                                Ok(extracted) => {
                                    let mut text = extracted;
                                    if text.len() > MAX_PDF_TEXT_CHARS {
                                        text.truncate(MAX_PDF_TEXT_CHARS);
                                        text.push_str("\n\n[PDF text truncated]");
                                    }

                                    let blob = format!(
                                        "PDF ({label}) contents:\n\n```text\n{}\n```",
                                        text.trim()
                                    );
                                    parts.push(UserContent::text(blob));
                                }
                                Err(err) => {
                                    parts.push(UserContent::text(format!(
                                        "PDF ({label}) could not be converted to text: {err}"
                                    )));
                                }
                            }
                            continue;
                        }

                        let mime = a.mime.trim();
                        let b64 = a.b64.trim();
                        if mime.is_empty() || b64.is_empty() {
                            continue;
                        }

                        let media_type = image_media_type_from_mime(mime);
                        // Gemini requires a known media type for images.
                        if provider_is_gemini && media_type.is_none() {
                            continue;
                        }

                        parts.push(UserContent::image_base64(
                            b64.to_string(),
                            media_type,
                            None,
                        ));
                    }

                    let content = OneOrMany::many(parts).map_err(|_| "No valid attachments to send.".to_string())?;
                    rig::message::Message::User { content }
                };

                let rig_messages: Vec<rig::message::Message> = history_msgs
                    .into_iter()
                    .map(|m| {
                        if m.sender == "user" {
                            rig::message::Message::user(m.body)
                        } else {
                            rig::message::Message::assistant(m.body)
                        }
                    })
                    .collect();

                if provider_is_gemini {
                    let client =
                        gemini_client.ok_or_else(|| "Internal error: missing Gemini client".to_string())?;
                    let model = client.completion_model(model_id.clone());
                    let req = model
                        .completion_request(prompt_msg)
                        .messages(rig_messages)
                        .preamble(system_prompt.clone())
                        .build();
                    let mut stream = model
                        .stream(req)
                        .await
                        .map_err(|e| format!("Gemini request failed: {e}"))?;

                    let mut pending = String::new();
                    let mut last_flush = Instant::now();
                    while let Some(chunk) = stream.next().await {
                        match chunk {
                            Ok(StreamedAssistantContent::Text(t)) => {
                                pending.push_str(&t.text);
                                if last_flush.elapsed() >= Duration::from_millis(50) {
                                    let delta = std::mem::take(&mut pending);
                                    let msg_id = assistant_message_id.clone();
                                    qt_thread
                                        .queue(move |mut obj| {
                                            let mut changed_row: Option<i32> = None;
                                            {
                                                let rust = obj.as_mut().rust_mut();
                                                let rust = rust.get_mut();
                                                if let Some((idx, msg)) = rust
                                                    .messages
                                                    .iter_mut()
                                                    .enumerate()
                                                    .find(|(_, m)| m.message_id == msg_id)
                                                {
                                                    msg.body.push_str(&delta);
                                                    changed_row =
                                                        Some(i32::try_from(idx).unwrap_or(i32::MAX));
                                                }
                                            }
                                            if let Some(row) = changed_row {
                                                let parent = cxx_qt_lib::QModelIndex::default();
                                                let model_index =
                                                    obj.as_ref().index_for_row(row, 0, &parent);
                                                let mut roles: cxx_qt_lib::QList<i32> =
                                                    cxx_qt_lib::QList::default();
                                                roles.append(Self::ROLE_BODY);
                                                obj.as_mut().data_changed(&model_index, &model_index, &roles);
                                            }
                                        })
                                        .ok();
                                    last_flush = Instant::now();
                                }
                            }
                            Ok(_) => {}
                            Err(e) => return Err(format!("Gemini request failed: {e}")),
                        }
                    }

                    if !pending.is_empty() {
                        let delta = pending;
                        let msg_id = assistant_message_id.clone();
                        qt_thread
                            .queue(move |mut obj| {
                                let mut changed_row: Option<i32> = None;
                                {
                                    let rust = obj.as_mut().rust_mut();
                                    let rust = rust.get_mut();
                                    if let Some((idx, msg)) = rust
                                        .messages
                                        .iter_mut()
                                        .enumerate()
                                        .find(|(_, m)| m.message_id == msg_id)
                                    {
                                        msg.body.push_str(&delta);
                                        changed_row =
                                            Some(i32::try_from(idx).unwrap_or(i32::MAX));
                                    }
                                }
                                if let Some(row) = changed_row {
                                    let parent = cxx_qt_lib::QModelIndex::default();
                                    let model_index =
                                        obj.as_ref().index_for_row(row, 0, &parent);
                                    let mut roles: cxx_qt_lib::QList<i32> =
                                        cxx_qt_lib::QList::default();
                                    roles.append(Self::ROLE_BODY);
                                    obj.as_mut().data_changed(&model_index, &model_index, &roles);
                                }
                            })
                            .ok();
                    }

                    Ok(())
                } else {
                    let client =
                        openai_client.ok_or_else(|| "Internal error: missing OpenAI client".to_string())?;
                    let model = client.completion_model(model_id.clone());
                    let req = model
                        .completion_request(prompt_msg)
                        .messages(rig_messages)
                        .preamble(system_prompt.clone())
                        .build();
                    let mut stream = model
                        .stream(req)
                        .await
                        .map_err(|e| format!("OpenAI request failed: {e}"))?;

                    let mut pending = String::new();
                    let mut last_flush = Instant::now();
                    while let Some(chunk) = stream.next().await {
                        match chunk {
                            Ok(StreamedAssistantContent::Text(t)) => {
                                pending.push_str(&t.text);
                                if last_flush.elapsed() >= Duration::from_millis(50) {
                                    let delta = std::mem::take(&mut pending);
                                    let msg_id = assistant_message_id.clone();
                                    qt_thread
                                        .queue(move |mut obj| {
                                            let mut changed_row: Option<i32> = None;
                                            {
                                                let rust = obj.as_mut().rust_mut();
                                                let rust = rust.get_mut();
                                                if let Some((idx, msg)) = rust
                                                    .messages
                                                    .iter_mut()
                                                    .enumerate()
                                                    .find(|(_, m)| m.message_id == msg_id)
                                                {
                                                    msg.body.push_str(&delta);
                                                    changed_row =
                                                        Some(i32::try_from(idx).unwrap_or(i32::MAX));
                                                }
                                            }
                                            if let Some(row) = changed_row {
                                                let parent = cxx_qt_lib::QModelIndex::default();
                                                let model_index =
                                                    obj.as_ref().index_for_row(row, 0, &parent);
                                                let mut roles: cxx_qt_lib::QList<i32> =
                                                    cxx_qt_lib::QList::default();
                                                roles.append(Self::ROLE_BODY);
                                                obj.as_mut().data_changed(&model_index, &model_index, &roles);
                                            }
                                        })
                                        .ok();
                                    last_flush = Instant::now();
                                }
                            }
                            Ok(_) => {}
                            Err(e) => return Err(format!("OpenAI request failed: {e}")),
                        }
                    }

                    if !pending.is_empty() {
                        let delta = pending;
                        let msg_id = assistant_message_id.clone();
                        qt_thread
                            .queue(move |mut obj| {
                                let mut changed_row: Option<i32> = None;
                                {
                                    let rust = obj.as_mut().rust_mut();
                                    let rust = rust.get_mut();
                                    if let Some((idx, msg)) = rust
                                        .messages
                                        .iter_mut()
                                        .enumerate()
                                        .find(|(_, m)| m.message_id == msg_id)
                                    {
                                        msg.body.push_str(&delta);
                                        changed_row =
                                            Some(i32::try_from(idx).unwrap_or(i32::MAX));
                                    }
                                }
                                if let Some(row) = changed_row {
                                    let parent = cxx_qt_lib::QModelIndex::default();
                                    let model_index =
                                        obj.as_ref().index_for_row(row, 0, &parent);
                                    let mut roles: cxx_qt_lib::QList<i32> =
                                        cxx_qt_lib::QList::default();
                                    roles.append(Self::ROLE_BODY);
                                    obj.as_mut().data_changed(&model_index, &model_index, &roles);
                                }
                            })
                            .ok();
                    }

                    Ok(())
                }
            }
            .await;

            let elapsed_ms = started.elapsed().as_millis();
            qt_thread
                .queue(move |mut obj| {
                    {
                        let rust = obj.as_mut().rust_mut();
                        let rust = rust.get_mut();
                        rust.last_latency_ms = Some(elapsed_ms);
                    }
                    obj.as_mut().set_busy(false);

                    match result {
                        Ok(()) => {
                            // Streaming already filled the message body.
                            {
                                let rust = obj.as_mut().rust_mut();
                                let rust = rust.get_mut();
                                rust.last_success_at = Some(Utc::now());
                            }
                            obj.as_mut().set_status(cxx_qt_lib::QString::from("Ready"));
                            obj.as_mut().set_error(cxx_qt_lib::QString::from(""));
                            obj.as_mut().scroll_to_end_requested();
                        }
                        Err(err) => {
                            let cleaned = try_extract_error_message_from_rig_error_text(&err)
                                .unwrap_or_else(|| err.clone());
                            {
                                let rust = obj.as_mut().rust_mut();
                                let rust = rust.get_mut();
                                rust.last_error_at = Some(Utc::now());
                            }
                            obj.as_mut().set_status(cxx_qt_lib::QString::from("Error"));
                            obj.as_mut()
                                .set_error(cxx_qt_lib::QString::from(cleaned.clone()));
                            let _ = Self::remove_message(obj.as_mut(), &assistant_message_id);
                            Self::append_message(
                                obj.as_mut(),
                                "assistant",
                                format!("Error: {cleaned}"),
                                "info",
                            );
                            obj.as_mut().scroll_to_end_requested();
                        }
                    }
                })
                .ok();
        });
    }

    pub fn submit_input(mut self: Pin<&mut Self>, text: &cxx_qt_lib::QString) {
        self.as_mut().ensure_initialized();

        let raw = text.to_string();
        let input = raw.trim();
        if input.is_empty() {
            return;
        }

        // Commands.
        if input.starts_with('/') {
            let cmd = input.to_lowercase();
            match cmd.as_str() {
                "/debug" => {
                    let qt_thread = self.qt_thread();
                    let (provider_is_gemini, model_id, base_url, openai_set, gemini_set) = {
                        let rust = self.as_mut().rust_mut();
                        let rust = rust.get_mut();
                        (
                            rust.model_id.to_string().starts_with("gemini"),
                            rust.model_id.to_string(),
                            rust.openai_base_url.to_string(),
                            !rust.openai_api_key.to_string().is_empty(),
                            !rust.gemini_api_key.to_string().is_empty(),
                        )
                    };

                    let snapshot = {
                        let rust = self.as_mut().rust_mut();
                        let rust = rust.get_mut();
                        let provider = if provider_is_gemini { "gemini" } else { "openai" };
                        let http_cached = if rust.http_client.is_some() { "yes" } else { "no" };
                        let openai_cached = if rust.openai_cache.is_some() { "yes" } else { "no" };
                        let gemini_cached = if rust.gemini_cache.is_some() { "yes" } else { "no" };
                        let last_latency = rust
                            .last_latency_ms
                            .map(|ms| format!("{ms}ms"))
                            .unwrap_or_else(|| "n/a".to_string());
                        let last_verify_latency = rust
                            .last_verify_latency_ms
                            .map(|ms| format!("{ms}ms"))
                            .unwrap_or_else(|| "n/a".to_string());
                        let last_verify_ok = match rust.last_verify_ok {
                            Some(true) => "ok",
                            Some(false) => "failed",
                            None => "n/a",
                        };

                        format!(
                            "**Debug**\n\n\
- Provider: `{provider}`\n\
- Model: `{model_id}`\n\
- Busy: `{}`\n\
- Status: `{}`\n\
- Error: `{}`\n\
- HTTP pooled client cached: `{http_cached}`\n\
- OpenAI client cached: `{openai_cached}`\n\
- Gemini client cached: `{gemini_cached}`\n\
- OpenAI key set: `{}`\n\
- Gemini key set: `{}`\n\
- OpenAI base URL: `{}`\n\
- Last request: `{}`\n\
- Last success: `{}`\n\
- Last error: `{}`\n\
- Last latency: `{last_latency}`\n\
- Last verify: `{}` ({last_verify_ok}, {last_verify_latency})\n\n\
Running connectivity verify in background...",
                            if rust.busy { "true" } else { "false" },
                            rust.status.to_string(),
                            rust.error.to_string(),
                            if openai_set { "true" } else { "false" },
                            if gemini_set { "true" } else { "false" },
                            if base_url.trim().is_empty() {
                                "<default>".to_string()
                            } else {
                                base_url.trim().to_string()
                            },
                            Self::fmt_opt_time(rust.last_request_at),
                            Self::fmt_opt_time(rust.last_success_at),
                            Self::fmt_opt_time(rust.last_error_at),
                            Self::fmt_opt_time(rust.last_verify_at),
                        )
                    };

                    self.as_mut()
                        .append_info(&cxx_qt_lib::QString::from(snapshot));

                    // Build clients (and ensure we use the pooled HTTP client), then verify async.
                    let clients = {
                        let rust = self.as_mut().rust_mut();
                        let rust = rust.get_mut();

                        let http_client = match Self::get_or_build_http_client(rust) {
                            Ok(c) => c,
                            Err(err) => {
                                self.as_mut().append_info(&cxx_qt_lib::QString::from(format!(
                                    "**Debug**\n\nVerify skipped: {err}"
                                )));
                                return;
                            }
                        };

                        if provider_is_gemini {
                            let key = rust.gemini_api_key.to_string();
                            if key.is_empty() {
                                self.as_mut().append_info(&cxx_qt_lib::QString::from(
                                    "**Debug**\n\nVerify skipped: GEMINI_API_KEY not set.",
                                ));
                                return;
                            }
                            match Self::get_or_build_gemini_client(rust, http_client, &key) {
                                Ok(c) => (None, Some(c)),
                                Err(err) => {
                                    self.as_mut().append_info(&cxx_qt_lib::QString::from(format!(
                                        "**Debug**\n\nVerify failed to start: {err}"
                                    )));
                                    return;
                                }
                            }
                        } else {
                            let key = rust.openai_api_key.to_string();
                            if key.is_empty() {
                                self.as_mut().append_info(&cxx_qt_lib::QString::from(
                                    "**Debug**\n\nVerify skipped: OPENAI_API_KEY not set.",
                                ));
                                return;
                            }
                            let base_url = rust.openai_base_url.to_string();
                            match Self::get_or_build_openai_completions(rust, http_client, &key, &base_url)
                            {
                                Ok(c) => (Some(c), None),
                                Err(err) => {
                                    self.as_mut().append_info(&cxx_qt_lib::QString::from(format!(
                                        "**Debug**\n\nVerify failed to start: {err}"
                                    )));
                                    return;
                                }
                            }
                        }
                    };

                    tokio_runtime().spawn(async move {
                        let start = Instant::now();
                        let result: Result<(), String> = if provider_is_gemini {
                            match clients.1 {
                                Some(client) => client
                                    .verify()
                                    .await
                                    .map_err(|e| format!("verify failed: {e}")),
                                None => Err("Internal error: missing Gemini client".to_string()),
                            }
                        } else {
                            match clients.0 {
                                Some(client) => client
                                    .verify()
                                    .await
                                    .map_err(|e| format!("verify failed: {e}")),
                                None => Err("Internal error: missing OpenAI client".to_string()),
                            }
                        };
                        let elapsed_ms = start.elapsed().as_millis();
                        let ok = result.is_ok();
                        let msg = match result {
                            Ok(_) => format!("**Debug**\n\nVerify: ok ({elapsed_ms}ms)"),
                            Err(err) => format!("**Debug**\n\nVerify: failed ({elapsed_ms}ms)\n\n{err}"),
                        };

                        qt_thread
                            .queue(move |mut obj| {
                                {
                                    let rust = obj.as_mut().rust_mut();
                                    let rust = rust.get_mut();
                                    rust.last_verify_at = Some(Utc::now());
                                    rust.last_verify_ok = Some(ok);
                                    rust.last_verify_latency_ms = Some(elapsed_ms);
                                }
                                obj.as_mut()
                                    .append_info(&cxx_qt_lib::QString::from(msg));
                                obj.as_mut().scroll_to_end_requested();
                            })
                            .ok();
                    });

                    return;
                }
                "/model" => {
                    self.as_mut().open_model_picker_requested();
                    return;
                }
                "/mood" => {
                    self.as_mut().open_mood_picker_requested();
                    return;
                }
                "/clear" => {
                    let mut this = self;
                    this.as_mut().begin_reset_model();
                    {
                        let rust = this.as_mut().rust_mut();
                        let rust = rust.get_mut();
                        rust.messages.clear();
                    }
                    this.as_mut().end_reset_model();
                    Self::append_message(
                        this.as_mut(),
                        "assistant",
                        "Chat cleared.".to_string(),
                        "info",
                    );
                    this.as_mut().scroll_to_end_requested();
                    return;
                }
                "/copy" => {
                    let text = self.as_mut().copy_all_text();
                    self.as_mut().copy_all_requested(text);
                    self.as_mut().scroll_to_end_requested();
                    return;
                }
                "/help" => {
                    self.as_mut().append_info(&cxx_qt_lib::QString::from(
                        "**Commands**\n\n\
- `/model` Choose AI model\n\
- `/mood` Set conversation mood\n\
- `/clear` Clear chat history\n\
- `/copy` Copy conversation\n\
- `/help` Show this help\n\
- `/status` Show current settings\n\
- `/debug` Connection/client statistics",
                    ));
                    return;
                }
                "/status" => {
                    let model_id = {
                        let this = self.as_mut();
                        this.rust().model_id.to_string()
                    };
                    let provider = if model_id.starts_with("gemini") {
                        "gemini"
                    } else {
                        "openai"
                    };
                    let (openai_set, gemini_set) = {
                        let this = self.as_mut();
                        let rust = this.rust();
                        (
                            !rust.openai_api_key.to_string().is_empty(),
                            !rust.gemini_api_key.to_string().is_empty(),
                        )
                    };
                    self.as_mut()
                        .append_info(&cxx_qt_lib::QString::from(format!(
                            "**Current Settings**\n\n\
- Model: `{model_id}`\n\
- Provider: {provider}\n\
- OpenAI Key: {}\n\
- Gemini Key: {}",
                            if openai_set { "Set" } else { "Not set" },
                            if gemini_set { "Set" } else { "Not set" },
                        )));
                    return;
                }
                _ => {
                    self.as_mut()
                        .append_info(&cxx_qt_lib::QString::from(format!(
                            "Unknown command: {input}\nType /help for available commands."
                        )));
                    return;
                }
            }
        }

        // Normal message send.
        let mut this = self;
        let qt_thread = this.qt_thread();

        let (model_id, system_prompt, openai_key, gemini_key, base_url, busy) = {
            let rust = this.as_mut().rust_mut();
            let rust = rust.get_mut();

            let busy = rust.busy;
            let model_id = rust.model_id.to_string();
            let system_prompt = rust.system_prompt.to_string();
            let openai_key = rust.openai_api_key.to_string();
            let gemini_key = rust.gemini_api_key.to_string();
            let base_url = rust.openai_base_url.to_string();
            (
                model_id,
                system_prompt,
                openai_key,
                gemini_key,
                base_url,
                busy,
            )
        };

        if busy {
            return;
        }

        // Append user message immediately.
        Self::append_message(this.as_mut(), "user", input.to_string(), "chat");
        this.as_mut().scroll_to_end_requested();

        if !Self::has_required_api_key(&model_id, &openai_key, &gemini_key) {
            let key_name = if model_id.starts_with("gemini") {
                "GEMINI_API_KEY"
            } else {
                "OPENAI_API_KEY"
            };
            this.as_mut()
                .append_info(&cxx_qt_lib::QString::from(format!(
                    "Set {key_name} to enable replies."
                )));
            return;
        }

        // Build conversation history excluding info messages and excluding the last user prompt
        // (we pass that as the rig prompt, which is always appended as the last message).
        let (history_msgs, prompt) = {
            let rust = this.as_mut().rust_mut();
            let rust = rust.get_mut();

            let mut convo: Vec<ChatMessage> = rust
                .messages
                .iter()
                .filter(|m| m.kind == "chat")
                .cloned()
                .collect();
            if convo.is_empty() {
                (Vec::new(), input.to_string())
            } else {
                let prompt = convo
                    .pop()
                    .map(|m| m.body)
                    .unwrap_or_else(|| input.to_string());
                (convo, prompt)
            }
        };

        // Build/reuse a pooled HTTP client and cache provider clients so we keep connections alive.
        let provider_is_gemini = model_id.starts_with("gemini");
        let (openai_client, gemini_client) = {
            let rust = this.as_mut().rust_mut();
            let rust = rust.get_mut();
            let http_client = match Self::get_or_build_http_client(rust) {
                Ok(c) => c,
                Err(err) => {
                    this.as_mut().set_status(cxx_qt_lib::QString::from("Error"));
                    this.as_mut()
                        .set_error(cxx_qt_lib::QString::from(err.clone()));
                    Self::append_message(
                        this.as_mut(),
                        "assistant",
                        format!("Error: {err}"),
                        "info",
                    );
                    this.as_mut().scroll_to_end_requested();
                    return;
                }
            };

            if provider_is_gemini {
                match Self::get_or_build_gemini_client(rust, http_client, &gemini_key) {
                    Ok(client) => (None, Some(client)),
                    Err(err) => {
                        this.as_mut().set_status(cxx_qt_lib::QString::from("Error"));
                        this.as_mut()
                            .set_error(cxx_qt_lib::QString::from(err.clone()));
                        Self::append_message(
                            this.as_mut(),
                            "assistant",
                            format!("Error: {err}"),
                            "info",
                        );
                        this.as_mut().scroll_to_end_requested();
                        return;
                    }
                }
            } else {
                match Self::get_or_build_openai_completions(
                    rust,
                    http_client,
                    &openai_key,
                    &base_url,
                ) {
                    Ok(client) => (Some(client), None),
                    Err(err) => {
                        this.as_mut().set_status(cxx_qt_lib::QString::from("Error"));
                        this.as_mut()
                            .set_error(cxx_qt_lib::QString::from(err.clone()));
                        Self::append_message(
                            this.as_mut(),
                            "assistant",
                            format!("Error: {err}"),
                            "info",
                        );
                        this.as_mut().scroll_to_end_requested();
                        return;
                    }
                }
            }
        };

        {
            let rust = this.as_mut().rust_mut();
            let rust = rust.get_mut();
            rust.last_request_at = Some(Utc::now());
            rust.last_latency_ms = None;
            this.as_mut().set_busy(true);
            this.as_mut().set_error(cxx_qt_lib::QString::from(""));
            this.as_mut()
                .set_status(cxx_qt_lib::QString::from("Thinking..."));
        }

        // Insert the assistant message up-front so streaming can fill it in.
        let assistant_message_id =
            Self::append_message(this.as_mut(), "assistant", "".to_string(), "chat");
        this.as_mut().scroll_to_end_requested();
        let started = Instant::now();
        tokio_runtime().spawn(async move {
            let result: Result<(), String> = async {
                let rig_messages: Vec<rig::message::Message> = history_msgs
                    .into_iter()
                    .map(|m| {
                        if m.sender == "user" {
                            rig::message::Message::user(m.body)
                        } else {
                            rig::message::Message::assistant(m.body)
                        }
                    })
                    .collect();

                if provider_is_gemini {
                    let client = gemini_client
                        .ok_or_else(|| "Internal error: missing Gemini client".to_string())?;
                    let model = client.completion_model(model_id.clone());
                    let req = model
                        .completion_request(rig::message::Message::user(prompt))
                        .messages(rig_messages)
                        .preamble(system_prompt.clone())
                        .build();
                    let mut stream = model
                        .stream(req)
                        .await
                        .map_err(|e| format!("Gemini request failed: {e}"))?;

                    // Throttle UI updates to avoid rebuilding the whole model for every token.
                    let mut pending = String::new();
                    let mut last_flush = Instant::now();
                    while let Some(chunk) = stream.next().await {
                        match chunk {
                            Ok(StreamedAssistantContent::Text(t)) => {
                                pending.push_str(&t.text);
                                if last_flush.elapsed() >= Duration::from_millis(50) {
                                    let delta = std::mem::take(&mut pending);
                                    let msg_id = assistant_message_id.clone();
                                    qt_thread
                                        .queue(move |mut obj| {
                                            let mut changed_row: Option<i32> = None;
                                            {
                                                let rust = obj.as_mut().rust_mut();
                                                let rust = rust.get_mut();
                                                if let Some((idx, msg)) = rust
                                                    .messages
                                                    .iter_mut()
                                                    .enumerate()
                                                    .find(|(_, m)| m.message_id == msg_id)
                                                {
                                                    msg.body.push_str(&delta);
                                                    changed_row =
                                                        Some(i32::try_from(idx).unwrap_or(i32::MAX));
                                                }
                                            }
                                            if let Some(row) = changed_row {
                                                let parent = cxx_qt_lib::QModelIndex::default();
                                                let model_index =
                                                    obj.as_ref().index_for_row(row, 0, &parent);
                                                let mut roles: cxx_qt_lib::QList<i32> =
                                                    cxx_qt_lib::QList::default();
                                                roles.append(Self::ROLE_BODY);
                                                obj.as_mut()
                                                    .data_changed(&model_index, &model_index, &roles);
                                            }
                                        })
                                        .ok();
                                    last_flush = Instant::now();
                                }
                            }
                            Ok(_) => {
                                // Ignore tool calls/reasoning for now (MVP).
                            }
                            Err(e) => {
                                return Err(format!("Gemini request failed: {e}"));
                            }
                        }
                    }

                    if !pending.is_empty() {
                        let delta = pending;
                        let msg_id = assistant_message_id.clone();
                        qt_thread
                            .queue(move |mut obj| {
                                let mut changed_row: Option<i32> = None;
                                {
                                    let rust = obj.as_mut().rust_mut();
                                    let rust = rust.get_mut();
                                    if let Some((idx, msg)) = rust
                                        .messages
                                        .iter_mut()
                                        .enumerate()
                                        .find(|(_, m)| m.message_id == msg_id)
                                    {
                                        msg.body.push_str(&delta);
                                        changed_row =
                                            Some(i32::try_from(idx).unwrap_or(i32::MAX));
                                    }
                                }
                                if let Some(row) = changed_row {
                                    let parent = cxx_qt_lib::QModelIndex::default();
                                    let model_index =
                                        obj.as_ref().index_for_row(row, 0, &parent);
                                    let mut roles: cxx_qt_lib::QList<i32> =
                                        cxx_qt_lib::QList::default();
                                    roles.append(Self::ROLE_BODY);
                                    obj.as_mut()
                                        .data_changed(&model_index, &model_index, &roles);
                                }
                            })
                            .ok();
                    }

                    Ok(())
                } else {
                    let client = openai_client
                        .ok_or_else(|| "Internal error: missing OpenAI client".to_string())?;
                    let model = client.completion_model(model_id.clone());
                    let req = model
                        .completion_request(rig::message::Message::user(prompt))
                        .messages(rig_messages)
                        .preamble(system_prompt.clone())
                        .build();
                    let mut stream = model
                        .stream(req)
                        .await
                        .map_err(|e| format!("OpenAI request failed: {e}"))?;

                    let mut pending = String::new();
                    let mut last_flush = Instant::now();
                    while let Some(chunk) = stream.next().await {
                        match chunk {
                            Ok(StreamedAssistantContent::Text(t)) => {
                                pending.push_str(&t.text);
                                if last_flush.elapsed() >= Duration::from_millis(50) {
                                    let delta = std::mem::take(&mut pending);
                                    let msg_id = assistant_message_id.clone();
                                    qt_thread
                                        .queue(move |mut obj| {
                                            let mut changed_row: Option<i32> = None;
                                            {
                                                let rust = obj.as_mut().rust_mut();
                                                let rust = rust.get_mut();
                                                if let Some((idx, msg)) = rust
                                                    .messages
                                                    .iter_mut()
                                                    .enumerate()
                                                    .find(|(_, m)| m.message_id == msg_id)
                                                {
                                                    msg.body.push_str(&delta);
                                                    changed_row =
                                                        Some(i32::try_from(idx).unwrap_or(i32::MAX));
                                                }
                                            }
                                            if let Some(row) = changed_row {
                                                let parent = cxx_qt_lib::QModelIndex::default();
                                                let model_index =
                                                    obj.as_ref().index_for_row(row, 0, &parent);
                                                let mut roles: cxx_qt_lib::QList<i32> =
                                                    cxx_qt_lib::QList::default();
                                                roles.append(Self::ROLE_BODY);
                                                obj.as_mut()
                                                    .data_changed(&model_index, &model_index, &roles);
                                            }
                                        })
                                        .ok();
                                    last_flush = Instant::now();
                                }
                            }
                            Ok(_) => {}
                            Err(e) => {
                                return Err(format!("OpenAI request failed: {e}"));
                            }
                        }
                    }

                    if !pending.is_empty() {
                        let delta = pending;
                        let msg_id = assistant_message_id.clone();
                        qt_thread
                            .queue(move |mut obj| {
                                let mut changed_row: Option<i32> = None;
                                {
                                    let rust = obj.as_mut().rust_mut();
                                    let rust = rust.get_mut();
                                    if let Some((idx, msg)) = rust
                                        .messages
                                        .iter_mut()
                                        .enumerate()
                                        .find(|(_, m)| m.message_id == msg_id)
                                    {
                                        msg.body.push_str(&delta);
                                        changed_row =
                                            Some(i32::try_from(idx).unwrap_or(i32::MAX));
                                    }
                                }
                                if let Some(row) = changed_row {
                                    let parent = cxx_qt_lib::QModelIndex::default();
                                    let model_index =
                                        obj.as_ref().index_for_row(row, 0, &parent);
                                    let mut roles: cxx_qt_lib::QList<i32> =
                                        cxx_qt_lib::QList::default();
                                    roles.append(Self::ROLE_BODY);
                                    obj.as_mut()
                                        .data_changed(&model_index, &model_index, &roles);
                                }
                            })
                            .ok();
                    }

                    Ok(())
                }
            }
            .await;
            let elapsed_ms = started.elapsed().as_millis();

            qt_thread
                .queue(move |mut obj| {
                    {
                        let rust = obj.as_mut().rust_mut();
                        let rust = rust.get_mut();
                        rust.last_latency_ms = Some(elapsed_ms);
                    }
                    obj.as_mut().set_busy(false);

                    match result {
                        Ok(()) => {
                            {
                                let rust = obj.as_mut().rust_mut();
                                let rust = rust.get_mut();
                                rust.last_success_at = Some(Utc::now());
                            }
                            obj.as_mut().set_status(cxx_qt_lib::QString::from("Ready"));
                            obj.as_mut().set_error(cxx_qt_lib::QString::from(""));
                            obj.as_mut().scroll_to_end_requested();
                        }
                        Err(err) => {
                            let cleaned = try_extract_error_message_from_rig_error_text(&err)
                                .unwrap_or_else(|| err.clone());
                            {
                                let rust = obj.as_mut().rust_mut();
                                let rust = rust.get_mut();
                                rust.last_error_at = Some(Utc::now());
                            }
                            obj.as_mut().set_status(cxx_qt_lib::QString::from("Error"));
                            obj.as_mut()
                                .set_error(cxx_qt_lib::QString::from(cleaned.clone()));
                            // Remove the empty streaming assistant message (if present) and
                            // replace with an info error.
                            let _ = Self::remove_message(obj.as_mut(), &assistant_message_id);
                            Self::append_message(
                                obj.as_mut(),
                                "assistant",
                                format!("Error: {cleaned}"),
                                "info",
                            );
                            obj.as_mut().scroll_to_end_requested();
                        }
                    }
                })
                .ok();
        });
    }
}
