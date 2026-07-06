//! `MarkdownStreamModel` provider.
//!
//! Incremental streaming markdown block parser backing the QML
//! `MarkdownStreamModel` list model. `setContent`/`setStreaming` feed the
//! `mdstream` incremental parser and deliver the *current full row snapshot*
//! to C++ as a borrowed `#[repr(C)]` `MarkdownRowC` array (homogeneous rows,
//! zero-copy for the call). Everything here runs synchronously on the calling
//! (Qt) thread: parsing is pure CPU work with no D-Bus/HTTP/subprocess, so no
//! worker thread or cross-thread marshal is needed — the C++
//! `QsNativeMarkdownStream` `QObject` diffs the delivered snapshot against its
//! own cached rows to decide whether to grow the model incrementally
//! (`beginInsertRows` + `dataChanged` for the last row) or, if committed block
//! ids no longer match a prefix of the new snapshot, fall back to a full
//! `beginResetModel`.

use std::ffi::{c_void, CStr, CString};
use std::os::raw::c_char;

use mdstream::{BlockKind, DocumentState, MdStream, Options};

/// A single resolved markdown row, borrowed for the duration of the callback.
#[repr(C)]
pub struct MarkdownRowC {
    pub block_id: u64,
    pub kind: *const c_char,
    pub block_type: *const c_char,
    pub content: *const c_char,
    pub raw: *const c_char,
    pub display: *const c_char,
    pub completed: bool,
    pub language: *const c_char,
}

/// Delivers the current full row snapshot (borrowed for the call only) to the
/// C++ side. Called synchronously, on the caller's thread.
pub type MarkdownRowsFn = unsafe extern "C" fn(*mut c_void, *const MarkdownRowC, usize);

/// Reads a borrowed C string into an owned `String` (empty on null).
///
/// # Safety
/// `ptr` must be null or a valid NUL-terminated string for the call duration.
unsafe fn c_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    CStr::from_ptr(ptr).to_string_lossy().into_owned()
}

/// Builds a `CString`, falling back to empty on an interior NUL.
fn cstr(value: &str) -> CString {
    CString::new(value).unwrap_or_default()
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct MarkdownRow {
    block_id: u64,
    kind: String,
    block_type: String,
    content: String,
    raw: String,
    display: String,
    completed: bool,
    language: String,
}

#[derive(Debug)]
struct MarkdownStreamCore {
    content: String,
    streaming: bool,
    stream: MdStream,
    state: DocumentState,
    rows: Vec<MarkdownRow>,
}

impl MarkdownStreamCore {
    fn new() -> Self {
        Self {
            content: String::new(),
            streaming: true,
            stream: MdStream::new(Options::default()),
            state: DocumentState::new(),
            rows: Vec::new(),
        }
    }

    fn set_content(&mut self, content: &str) {
        if content == self.content {
            return;
        }

        if let Some(delta) = content.strip_prefix(&self.content) {
            self.content.push_str(delta);
            let update = self.stream.append(delta);
            self.apply_update(update);
        } else {
            self.reset_stream();
            self.content.push_str(content);
            let update = self.stream.append(content);
            self.apply_update(update);
        }

        if self.streaming {
            self.refresh_rows();
        } else {
            self.finalize();
        }
    }

    fn set_streaming(&mut self, streaming: bool) {
        if self.streaming == streaming {
            return;
        }
        self.streaming = streaming;
        if !streaming {
            self.finalize();
        }
    }

    fn finalize(&mut self) {
        let update = self.stream.finalize();
        self.apply_update(update);
        self.refresh_rows();
    }

    fn reset_stream(&mut self) {
        self.content.clear();
        self.stream.reset();
        self.state.clear();
        self.rows.clear();
    }

    fn apply_update(&mut self, update: mdstream::Update) {
        self.state.apply(update);
    }

    fn refresh_rows(&mut self) {
        self.rows.clear();
        self.rows.extend(
            self.state
                .committed()
                .iter()
                .map(|block| row_from_block(block, true)),
        );
        if let Some(pending) = self.state.pending() {
            self.rows.push(row_from_block(pending, false));
        }
    }
}

fn row_from_block(block: &mdstream::Block, completed: bool) -> MarkdownRow {
    let raw = block.raw.clone();
    let display = block.display_or_raw().to_string();
    let is_code = block.kind == BlockKind::CodeFence;
    let language = block
        .code_fence_language()
        .filter(|value| !value.is_empty())
        .unwrap_or("txt")
        .to_string();
    let content = if is_code {
        code_fence_body(&raw)
    } else {
        display.clone()
    };

    MarkdownRow {
        block_id: block.id.0,
        kind: kind_name(block.kind).to_string(),
        block_type: if is_code { "code" } else { "text" }.to_string(),
        content,
        raw,
        display,
        completed,
        language: if is_code { language } else { String::new() },
    }
}

fn kind_name(kind: BlockKind) -> &'static str {
    match kind {
        BlockKind::Paragraph => "paragraph",
        BlockKind::Heading => "heading",
        BlockKind::ThematicBreak => "thematicBreak",
        BlockKind::CodeFence => "codeFence",
        BlockKind::List => "list",
        BlockKind::BlockQuote => "blockQuote",
        BlockKind::Table => "table",
        BlockKind::HtmlBlock => "htmlBlock",
        BlockKind::MathBlock => "mathBlock",
        BlockKind::FootnoteDefinition => "footnoteDefinition",
        BlockKind::Unknown => "unknown",
    }
}

fn code_fence_body(raw: &str) -> String {
    let Some(header) = mdstream::parse_code_fence_header_from_block(raw) else {
        return raw.trim_end_matches('\n').to_string();
    };

    let mut lines: Vec<&str> = raw.split('\n').collect();
    if !lines.is_empty() {
        lines.remove(0);
    }
    while lines.last() == Some(&"") {
        lines.pop();
    }
    if lines.last().is_some_and(|line| {
        mdstream::is_code_fence_closing_line(line, header.fence_char, header.fence_len)
    }) {
        lines.pop();
    }
    lines.join("\n").trim_end_matches('\n').to_string()
}

/// Opaque per-instance handle owned by the C++ `QsNativeMarkdownStream` `QObject`.
pub struct MarkdownStreamHandle {
    core: MarkdownStreamCore,
}

#[no_mangle]
pub extern "C" fn QsNative_MarkdownStream_New() -> *mut MarkdownStreamHandle {
    Box::into_raw(Box::new(MarkdownStreamHandle {
        core: MarkdownStreamCore::new(),
    }))
}

/// # Safety
/// `handle` must be null or a pointer from `QsNative_MarkdownStream_New` not yet freed.
#[no_mangle]
pub unsafe extern "C" fn QsNative_MarkdownStream_Delete(handle: *mut MarkdownStreamHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Feeds the full content text (delta-appended when it extends the previous
/// content, otherwise a hard reset) and delivers the resulting row snapshot
/// via `cb`, called synchronously before this function returns.
///
/// # Safety
/// `handle` must be valid; `content` must be null or a valid C string;
/// `ctx`/`cb` must remain valid for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn QsNative_MarkdownStream_SetContent(
    handle: *mut MarkdownStreamHandle,
    content: *const c_char,
    ctx: *mut c_void,
    cb: MarkdownRowsFn,
) {
    if handle.is_null() {
        return;
    }
    (*handle).core.set_content(&c_string(content));
    deliver_rows(&(*handle).core, ctx, cb);
}

/// Sets streaming mode (finalizing the pending block when turned off) and
/// delivers the resulting row snapshot via `cb`, called synchronously before
/// this function returns.
///
/// # Safety
/// `handle` must be valid; `ctx`/`cb` must remain valid for the duration of
/// this call.
#[no_mangle]
pub unsafe extern "C" fn QsNative_MarkdownStream_SetStreaming(
    handle: *mut MarkdownStreamHandle,
    streaming: bool,
    ctx: *mut c_void,
    cb: MarkdownRowsFn,
) {
    if handle.is_null() {
        return;
    }
    (*handle).core.set_streaming(streaming);
    deliver_rows(&(*handle).core, ctx, cb);
}

/// Commits the pending block and delivers the resulting row snapshot via
/// `cb`, called synchronously before this function returns.
///
/// # Safety
/// `handle` must be valid; `ctx`/`cb` must remain valid for the duration of
/// this call.
#[no_mangle]
pub unsafe extern "C" fn QsNative_MarkdownStream_Finalize(
    handle: *mut MarkdownStreamHandle,
    ctx: *mut c_void,
    cb: MarkdownRowsFn,
) {
    if handle.is_null() {
        return;
    }
    (*handle).core.finalize();
    deliver_rows(&(*handle).core, ctx, cb);
}

/// Owned `CString`s for one row, kept alive across the callback; `MarkdownRowC`
/// borrows their pointers.
struct OwnedRowStrings {
    kind: CString,
    block_type: CString,
    content: CString,
    raw: CString,
    display: CString,
    language: CString,
}

impl OwnedRowStrings {
    fn from_row(row: &MarkdownRow) -> Self {
        Self {
            kind: cstr(&row.kind),
            block_type: cstr(&row.block_type),
            content: cstr(&row.content),
            raw: cstr(&row.raw),
            display: cstr(&row.display),
            language: cstr(&row.language),
        }
    }
}

/// Builds the borrowed `MarkdownRowC` array for the current rows and invokes
/// `cb` once, synchronously, with all string pointers valid only for the call.
///
/// # Safety
/// `ctx`/`cb` must remain valid for the duration of this call.
unsafe fn deliver_rows(core: &MarkdownStreamCore, ctx: *mut c_void, cb: MarkdownRowsFn) {
    // Keep the CStrings alive across the callback; entries borrow them.
    let owned: Vec<OwnedRowStrings> = core.rows.iter().map(OwnedRowStrings::from_row).collect();
    let entries: Vec<MarkdownRowC> = core
        .rows
        .iter()
        .zip(owned.iter())
        .map(|(row, strings)| MarkdownRowC {
            block_id: row.block_id,
            kind: strings.kind.as_ptr(),
            block_type: strings.block_type.as_ptr(),
            content: strings.content.as_ptr(),
            raw: strings.raw.as_ptr(),
            display: strings.display.as_ptr(),
            completed: row.completed,
            language: strings.language.as_ptr(),
        })
        .collect();
    cb(ctx, entries.as_ptr(), entries.len());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn append_partial_text_produces_one_pending_block_with_repaired_display() {
        let mut stream = MarkdownStreamCore::new();

        stream.set_content("Hello **wor");

        assert_eq!(stream.rows.len(), 1);
        let row = &stream.rows[0];
        assert_eq!(row.block_type, "text");
        assert!(!row.completed);
        assert_eq!(row.raw, "Hello **wor");
        assert_ne!(row.display, row.raw);
        assert!(row.display.contains("wor"));
    }

    #[test]
    fn blank_line_transition_commits_paragraph_and_creates_pending_code_block() {
        let mut stream = MarkdownStreamCore::new();

        stream.set_content("Intro paragraph\n\n```rust\nfn main() {}");

        assert_eq!(stream.rows.len(), 2);
        assert_eq!(stream.rows[0].block_type, "text");
        assert!(stream.rows[0].completed);
        assert_eq!(stream.rows[1].block_type, "code");
        assert_eq!(stream.rows[1].language, "rust");
        assert_eq!(stream.rows[1].content, "fn main() {}");
        assert!(!stream.rows[1].completed);
    }

    #[test]
    fn fenced_code_extracts_language_and_body() {
        let mut stream = MarkdownStreamCore::new();

        stream.set_content("```ts\nconst x = 1;\n```\n\nDone");

        let row = &stream.rows[0];
        assert_eq!(row.block_type, "code");
        assert_eq!(row.language, "ts");
        assert_eq!(row.content, "const x = 1;");
        assert!(row.completed);
    }

    #[test]
    fn pending_dollar_math_display_survives_for_qml_role_data() {
        let mut stream = MarkdownStreamCore::new();

        stream.set_content("The value is $x^2");

        let row = &stream.rows[0];
        assert_eq!(row.block_type, "text");
        assert!(!row.completed);
        assert_eq!(row.raw, "The value is $x^2");
        assert_eq!(row.content, row.display);
        assert!(row.display.contains("$x^2"));
    }

    #[test]
    fn finalize_commits_pending_block() {
        let mut stream = MarkdownStreamCore::new();

        stream.set_content("Hello **world");
        stream.set_streaming(false);

        assert_eq!(stream.rows.len(), 1);
        assert!(stream.rows[0].completed);
        assert_eq!(stream.rows[0].raw, "Hello **world");
    }

    #[test]
    fn append_updates_preserve_committed_block_ids_and_nonappend_resets() {
        let mut stream = MarkdownStreamCore::new();

        stream.set_content("First\n\nSecond");
        let first_id = stream.rows[0].block_id;
        stream.set_content("First\n\nSecond line");
        assert_eq!(stream.rows[0].block_id, first_id);

        stream.set_content("Replacement");
        assert_eq!(stream.rows.len(), 1);
        assert_eq!(stream.rows[0].raw, "Replacement");
    }
}
