# TODO

## Review Follow-Ups

### Stop provider-order saves from corrupting mood config

- File: `leftpanel/LeftPanel.qml`
- File: `leftpanel/services/MoodConfig.qml`
- Risk: `saveProviderOrder()` parses `leftpanel/config.json`, falls back to `{}` on failure, then writes only `provider_order`. The same file stores `moods`, so a parse failure can replace the mood catalog with a provider-order-only object.
- Fix: Store mutable provider order in a separate state file, or migrate it into `leftpanel/config.toml` and update it through a Rust config API with atomic writes. Do not overwrite config after parse failure.

### Make chat message deletion non-destructive

- File: `leftpanel/components/ChatMessage.qml`
- File: `leftpanel/LeftPanel.qml`
- File: `common/modules/qs-native/cpp/QsNativeAiSession.cpp`
- File: `common/modules/qs-native/qsnative-rust/src/chatstore.rs`
- Risk: The delete button calls `deleteMessage()` directly. The store physically deletes the message and matching response items, then compacts later ordinals. This removes history without undo and mutates ordinal identity used by replay/history state.
- Fix: Use soft delete/tombstones, keep ordinals immutable, and add undo or confirmation for destructive UI actions. Key replay pruning by stable message or turn IDs instead of rewritten ordinals.

### Replace files atomically in native copy helpers

- File: `common/modules/qs-capture/cpp/CaptureProvider.cpp`
- File: `common/modules/qsmath/cpp/MathRenderer.cpp`
- Risk: `copyImageFile()` and `copyRenderedSvg()` remove the destination before the replacement is guaranteed. If source read/copy/write fails, the previous file is lost.
- Fix: Write to a same-directory temporary file and atomically replace the destination after success, using `QSaveFile` or an equivalent temp-write-plus-rename pattern.

### Move lyric playback state out of QML

- File: `bar/modules/MprisModule.qml`
- Risk: QML owns lyric source selection, missing-key cache, playback-position math, current-line selection, and a 33 ms timer while the tooltip is visible. This is business/state-machine logic in the UI shell, while `unifiedlyrics` already owns lyric parsing/provider logic natively.
- Fix: Push lyric playback state into the native lyrics/player bridge. Expose current line index, display position, source, and error/loading state as properties; keep QML focused on rendering.

### Simplify custom Flickable physics

- File: `common/materialkit/Flickable.qml`
- Risk: The wrapper manually intercepts wheel events, tracks velocity samples, animates `contentY`, implements momentum, and toggles scrollbar policy. This duplicates Qt Flickable/ScrollBar behavior and leaves input physics in QML.
- Fix: Reduce this to a small styled `ScrollBar`/`ScrollView` wrapper using Qt's built-in Flickable movement and input handling. Keep only demonstrably missing custom behavior.
