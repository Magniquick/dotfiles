use core::pin::Pin;

use cxx_qt::CxxQtType;
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QModelIndex, QString, QVariant};
use mdstream::{BlockKind, DocumentState, MdStream, Options};

const BLOCK_ID_ROLE: i32 = 0x0100;
const KIND_ROLE: i32 = 0x0101;
const TYPE_ROLE: i32 = 0x0102;
const CONTENT_ROLE: i32 = 0x0103;
const RAW_ROLE: i32 = 0x0104;
const DISPLAY_ROLE: i32 = 0x0105;
const COMPLETED_ROLE: i32 = 0x0106;
const LANGUAGE_ROLE: i32 = 0x0107;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MarkdownRow {
    pub block_id: u64,
    pub kind: String,
    pub block_type: String,
    pub content: String,
    pub raw: String,
    pub display: String,
    pub completed: bool,
    pub language: String,
}

#[derive(Debug)]
pub struct MarkdownStreamCore {
    content: String,
    streaming: bool,
    stream: MdStream,
    state: DocumentState,
    rows: Vec<MarkdownRow>,
}

pub struct MarkdownStreamModelRust {
    content: QString,
    streaming: bool,
    block_count: i32,
    core: MarkdownStreamCore,
}

impl Default for MarkdownStreamModelRust {
    fn default() -> Self {
        Self {
            content: QString::default(),
            streaming: true,
            block_count: 0,
            core: MarkdownStreamCore::new(),
        }
    }
}

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++Qt" {
        include!("QtCore/QAbstractListModel");
        #[qobject]
        type QAbstractListModel;
    }

    unsafe extern "C++" {
        include!("cxx-qt-lib/qbytearray.h");
        type QByteArray = cxx_qt_lib::QByteArray;
        include!("cxx-qt-lib/qhash_i32_QByteArray.h");
        type QHash_i32_QByteArray = cxx_qt_lib::QHash<cxx_qt_lib::QHashPair_i32_QByteArray>;
        include!("cxx-qt-lib/qmodelindex.h");
        type QModelIndex = cxx_qt_lib::QModelIndex;
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[base = QAbstractListModel]
        #[qproperty(QString, content)]
        #[qproperty(bool, streaming)]
        #[qproperty(i32, block_count, cxx_name = "blockCount")]
        type MarkdownStreamModel = super::MarkdownStreamModelRust;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qinvokable]
        #[cxx_override]
        #[cxx_name = "rowCount"]
        fn row_count(self: &MarkdownStreamModel, parent: &QModelIndex) -> i32;

        #[qinvokable]
        #[cxx_override]
        fn data(self: &MarkdownStreamModel, index: &QModelIndex, role: i32) -> QVariant;

        #[qinvokable]
        #[cxx_override]
        #[cxx_name = "roleNames"]
        fn role_names(self: &MarkdownStreamModel) -> QHash_i32_QByteArray;

        #[qinvokable]
        fn finalize(self: Pin<&mut MarkdownStreamModel>);

        #[inherit]
        #[cxx_name = "beginResetModel"]
        unsafe fn begin_reset_model(self: Pin<&mut MarkdownStreamModel>);

        #[inherit]
        #[cxx_name = "endResetModel"]
        unsafe fn end_reset_model(self: Pin<&mut MarkdownStreamModel>);
    }

    impl cxx_qt::Initialize for MarkdownStreamModel {}
}

impl cxx_qt::Initialize for ffi::MarkdownStreamModel {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut()
            .on_content_changed(|mut model| model.as_mut().sync_content())
            .release();
        self.as_mut()
            .on_streaming_changed(|mut model| model.as_mut().sync_streaming())
            .release();
    }
}

impl ffi::MarkdownStreamModel {
    pub fn row_count(&self, parent: &QModelIndex) -> i32 {
        if parent.is_valid() {
            0
        } else {
            self.rust().core.block_count() as i32
        }
    }

    pub fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        if !index.is_valid() || index.column() != 0 {
            return QVariant::default();
        }
        let row = index.row();
        if row < 0 {
            return QVariant::default();
        }
        let Some(block) = self.rust().core.rows().get(row as usize) else {
            return QVariant::default();
        };

        match role {
            BLOCK_ID_ROLE => QVariant::from(&(block.block_id as i32)),
            KIND_ROLE => QVariant::from(&QString::from(block.kind.as_str())),
            TYPE_ROLE => QVariant::from(&QString::from(block.block_type.as_str())),
            CONTENT_ROLE => QVariant::from(&QString::from(block.content.as_str())),
            RAW_ROLE => QVariant::from(&QString::from(block.raw.as_str())),
            DISPLAY_ROLE => QVariant::from(&QString::from(block.display.as_str())),
            COMPLETED_ROLE => QVariant::from(&block.completed),
            LANGUAGE_ROLE => QVariant::from(&QString::from(block.language.as_str())),
            _ => QVariant::default(),
        }
    }

    pub fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut roles = QHash::<QHashPair_i32_QByteArray>::default();
        roles.insert_clone(&BLOCK_ID_ROLE, &QByteArray::from("blockId"));
        roles.insert_clone(&KIND_ROLE, &QByteArray::from("kind"));
        roles.insert_clone(&TYPE_ROLE, &QByteArray::from("type"));
        roles.insert_clone(&CONTENT_ROLE, &QByteArray::from("content"));
        roles.insert_clone(&RAW_ROLE, &QByteArray::from("raw"));
        roles.insert_clone(&DISPLAY_ROLE, &QByteArray::from("display"));
        roles.insert_clone(&COMPLETED_ROLE, &QByteArray::from("completed"));
        roles.insert_clone(&LANGUAGE_ROLE, &QByteArray::from("language"));
        roles
    }

    pub fn finalize(mut self: Pin<&mut Self>) {
        self.as_mut()
            .reset_model_for_core_change(|core| core.finalize());
    }

    fn sync_content(self: Pin<&mut Self>) {
        let content = self.content().to_string();
        self.reset_model_for_core_change(|core| core.set_content(&content));
    }

    fn sync_streaming(self: Pin<&mut Self>) {
        let streaming = *self.streaming();
        self.reset_model_for_core_change(|core| core.set_streaming(streaming));
    }

    fn reset_model_for_core_change<F>(mut self: Pin<&mut Self>, mutate: F)
    where
        F: FnOnce(&mut MarkdownStreamCore),
    {
        unsafe {
            self.as_mut().begin_reset_model();
            let mut rust = self.as_mut().rust_mut();
            mutate(&mut rust.as_mut().get_mut().core);
            self.as_mut().end_reset_model();
        }
        let block_count = self.as_ref().rust().core.block_count() as i32;
        if *self.as_ref().block_count() != block_count {
            self.set_block_count(block_count);
        }
    }
}

impl Default for MarkdownStreamCore {
    fn default() -> Self {
        Self::new()
    }
}

impl MarkdownStreamCore {
    pub fn new() -> Self {
        Self {
            content: String::new(),
            streaming: true,
            stream: MdStream::new(Options::default()),
            state: DocumentState::new(),
            rows: Vec::new(),
        }
    }

    pub fn content(&self) -> &str {
        &self.content
    }

    pub fn streaming(&self) -> bool {
        self.streaming
    }

    pub fn block_count(&self) -> usize {
        self.rows.len()
    }

    pub fn rows(&self) -> &[MarkdownRow] {
        &self.rows
    }

    pub fn set_content(&mut self, content: &str) {
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

        if !self.streaming {
            self.finalize();
        } else {
            self.refresh_rows();
        }
    }

    pub fn set_streaming(&mut self, streaming: bool) {
        if self.streaming == streaming {
            return;
        }
        self.streaming = streaming;
        if !streaming {
            self.finalize();
        }
    }

    pub fn finalize(&mut self) {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn append_partial_text_produces_one_pending_block_with_repaired_display() {
        let mut stream = MarkdownStreamCore::new();

        stream.set_content("Hello **wor");

        assert_eq!(stream.block_count(), 1);
        let row = &stream.rows()[0];
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

        assert_eq!(stream.block_count(), 2);
        assert_eq!(stream.rows()[0].block_type, "text");
        assert!(stream.rows()[0].completed);
        assert_eq!(stream.rows()[1].block_type, "code");
        assert_eq!(stream.rows()[1].language, "rust");
        assert_eq!(stream.rows()[1].content, "fn main() {}");
        assert!(!stream.rows()[1].completed);
    }

    #[test]
    fn fenced_code_extracts_language_and_body() {
        let mut stream = MarkdownStreamCore::new();

        stream.set_content("```ts\nconst x = 1;\n```\n\nDone");

        let row = &stream.rows()[0];
        assert_eq!(row.block_type, "code");
        assert_eq!(row.language, "ts");
        assert_eq!(row.content, "const x = 1;");
        assert!(row.completed);
    }

    #[test]
    fn pending_dollar_math_display_survives_for_qml_role_data() {
        let mut stream = MarkdownStreamCore::new();

        stream.set_content("The value is $x^2");

        let row = &stream.rows()[0];
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

        assert_eq!(stream.block_count(), 1);
        assert!(stream.rows()[0].completed);
        assert_eq!(stream.rows()[0].raw, "Hello **world");
    }

    #[test]
    fn append_updates_preserve_committed_block_ids_and_nonappend_resets() {
        let mut stream = MarkdownStreamCore::new();

        stream.set_content("First\n\nSecond");
        let first_id = stream.rows()[0].block_id;
        stream.set_content("First\n\nSecond line");
        assert_eq!(stream.rows()[0].block_id, first_id);

        stream.set_content("Replacement");
        assert_eq!(stream.block_count(), 1);
        assert_eq!(stream.rows()[0].raw, "Replacement");
    }
}
