# Repository Guidelines

This directory contains native/QML modules consumed by the Quickshell config (Wayland/Hyprland). Prefer Quickshell built-in services/APIs where possible; use these modules for capabilities that need native code or vendored QML.

## Migration Policy

For native plugins/helpers, use full-sweep migrations. When replacing an API, model shape, provider path, config format, C ABI, or QML-facing type, migrate all in-tree callsites in the same change and remove the superseded path. Backward-compatible wrappers, dual formats, legacy aliases, and compatibility shims are not needed unless the user explicitly requests them; simpler current behavior is preferred even if edge cases change.

## Project Structure

- `qs-native/`: Rust/CXX-Qt + C++ Qt plugin (import: `qsnative`). **Primary native module.**
- `qs-capture/`: C++/Qt capture plugin used by HyprQuickshot.
- `qsmath/`: C++/Qt math rendering plugin used by left-panel message math blocks.
- `material-popups/`: Rust/CXX-Qt clipboard and input watcher backend for the QML clipboard popup.
- `unified-lyrics-api/`: Rust staticlib + C++ QML plugin with NetEase/LRCLIB fallback.
- `../materialkit/`: Local MaterialKit QML primitives (Pane/Card/Button/IconButton/Slider/Progress/Ripple).
- `rounded_polygon_qmljs/`: JS/QML shape helpers tracked as a git submodule.

Related entry points live above this folder (examples: `shell.qml`, `bar/`, `powermenu/`, `hyprquickshot/`).

## Build, Test, and Dev Commands

From the Quickshell config root:

- Run main shell: `./qs`
- Run a config: `quickshell -c powermenu` (or `./qs -c powermenu`)
- HyprQuickshot: run `./qs`, then trigger it via your keybind or `qs ipc call hyprquickshot open`

Build native modules:

- `qs-native`: `./tools/build-qs-native.sh`
  - Import path: `common/modules/qs-native/build/qml`
  - Rust/CXX-Qt sources build through the grouped `common/modules/cxxqt` project and shared Cargo target directory.
  - Re-run `./tools/build-qs-native.sh` after Rust or C++ changes; only use `rm -rf common/modules/qs-native/build` if C++ headers change or the build is corrupt.
  - Quick test from repo root: `env QML_IMPORT_PATH="$PWD/common/modules/qs-native/build/qml" quickshell`
- `qs-capture`: `bash tools/build-qs-capture.sh`
  - Import path: `common/modules/qs-capture/build/qml`
- `qsmath`: `bash tools/build-qsmath.sh`
  - Import path: `common/modules/qsmath/build/qml`
- `material-popups`: `bash tools/build-material-popups.sh`
  - Import path: `common/modules/material-popups/build/qml`
- `unified-lyrics-api`:
  - `bash tools/build-cmake-module.sh unified-lyrics-api`
  - Import path: `common/modules/unified-lyrics-api/build/qml`

Rust/CXX-Qt modules (`qs-native`, `qsmath`, `material-popups`, `unified-lyrics-api`) are built through the grouped CMake project at `common/modules/cxxqt`. The per-module build scripts still print and maintain the old import paths (`common/modules/<module>/build/qml`) by linking each module `build/` directory to its grouped sub-build. This keeps QML tooling stable while sharing one Corrosion/Cargo target directory.

Clean Rust/CXX-Qt build output with `bash tools/rust-clean.sh`; use `bash tools/rust-clean.sh --full` when CMake state or generated CXX-Qt headers are corrupt.

Cargo commands must use the grouped workspace manifest and release profile. Do not run bare `cargo test`, `cargo check`, or `cargo clippy` from a crate directory: that creates a separate debug build and wastes cache. The root `.cargo/config.toml` pins the shared target directory and `x86_64-unknown-linux-gnu` target.

Preferred Rust checks from the config root:

- Format: `cargo fmt --manifest-path common/modules/Cargo.toml --all`
- Focused tests: `cargo test --manifest-path common/modules/Cargo.toml -p qsnative_rust --release <test-name-or-module>`
- Package tests when needed: `cargo test --manifest-path common/modules/Cargo.toml -p qsnative_rust --release`
- Clippy gate: `cargo clippy --manifest-path common/modules/Cargo.toml -p qsnative_rust --release --all-targets -- -D warnings`

No root-level test runner is wired up. For Rust native changes, run focused release Cargo checks/tests through the grouped Rust workspace when useful, rebuild the affected native module, then finish with `bash tools/reload-quickshell.sh`.

## qs-native (Rust / C++ Qt Plugin) Notes

Module: `common/modules/qs-native` (import as `qsnative`).

Pattern: Rust crate in `qsnative-rust/` → CXX-Qt generated QObject code and Rust-owned C ABI symbols → C++ QObject glue in `cpp/` → QML plugin.

Source layout:

- `qsnative-rust/src/`: Rust providers, service clients, CXX-Qt bridges, helper binaries, and Rust-owned C ABI exports
- `cpp/qsnative_api.h`: C ABI header consumed by C++ Qt classes
- `cpp/qsnative_plugin.cpp`: `QQmlExtensionPlugin` registering all types as `qsnative 1.0`
- `qsnative-rust/src/app_config.rs`: non-secret TOML config loader for `leftpanel/config.toml`
- `qsnative-rust/src/secrets.rs`: Secret Service lookup boundary for keys/tokens/passwords
- AI-specific layout:
  - `qsnative-rust/src/ai.rs`: provider streaming, model capability helpers, metrics, response replay, and C ABI entrypoints
  - `qsnative-rust/src/mcp.rs`: local MCP catalog/execution for built-in email tools plus typed server/tool/prompt/resource snapshots
  - `qsnative-rust/src/chatstore.rs`: SQLite-backed chat history/resume storage

QML types (all in `import qsnative`):

- `SysInfoProvider`
  - Invokable: `refresh()`
  - Properties: `cpu`, `mem`, `mem_used`, `mem_total`, `disk`, `disk_health`, `disk_wear`, `temp`, `uptime`,
    `disk_worst_case`, `disk_btrfs_available`, `disk_btrfs_free_est_gib`, `disk_btrfs_free_min_gib`,
    `psi_cpu_some`, `psi_cpu_full`, `psi_mem_some`, `psi_mem_full`, `psi_io_some`, `psi_io_full`, `disk_device`, `error`
- `BacklightProvider`
  - Invokables: `start()`, `startMonitor()`, `refresh()`, `setBrightness(percent)`, `stopMonitor()`
  - Properties: `available`, `brightness_percent`, `device`, `error`
- `NetStatsProvider`
  - Invokables: `refresh()`, `updateTrafficRates(rxBytes, txBytes, nowMs)`, `resetTraffic()`, `setSourceEntries(entriesJson)`,
    `beginSourceSwitch(name)`, `failSourceSwitch(message)`, `clearSourceSwitch()`, `parseIpAddressJson(text)`,
    `parseGatewayJson(text)`, `ethernetMetadataJson(deviceName)`
  - Properties: `device`, `rx_bytes`, `tx_bytes`, `rxBytesPerSec`, `txBytesPerSec`, `rxHistoryJson`, `txHistoryJson`,
    `trafficScaleMax`, `sourceEntriesJson`, `sourceSwitching`, `sourceSwitchingName`, `sourceError`, `error`
  - Notes: QML keeps live `Quickshell.Networking` objects and Wi-Fi connect calls; Rust owns deterministic network parsing,
    source ordering/switch state, traffic smoothing/history, and ethernet sysfs/udev metadata lookup.
- `ConfigResolver`
  - Invokable: `refresh()`
  - Properties: `values`
  - Notes: central QML-facing bridge combining `internal/appconfig` non-secret TOML with `internal/secrets` provider API keys
- `AiChatSession`
  - Invokables: `submitInput`, `submitInputWithAttachments`, `cancel`, `pasteImageFromClipboard`, `regenerate`, `deleteMessage`,
    `editMessage`, `resetForModelSwitch`, `appendInfo`, `appendToolStatus`, `copyAllText`, `pasteAttachmentFromClipboard`,
    `restoreHistory`, `refreshMcp`, `refreshResumeConversations`, `resumeConversation`
  - Properties: `model_id`, `system_prompt`, `provider_config`, `disabled_tool_servers`, `busy`, `status`, `error`, `commands`,
    `mcp_servers`, `mcp_tools`, `mcp_status`, `mcp_error`, `resume_conversations`
  - Signals: `streamDone`, `openModelPickerRequested`, `openProviderPickerRequested`, `openToolPickerRequested`,
    `openMoodPickerRequested`, `openResumePickerRequested`, `scrollToEndRequested`, `copyAllRequested(text)`
  - Notes:
    - `QAbstractListModel`; roles: `messageId`, `sender`, `body`, `kind`, `metrics`, `attachments`, `tool`, `showHeader`
    - `model_id` is canonical `provider/model` form, for example `openai/gpt-4o`
    - `provider_config` is a typed `QVariantMap` keyed by provider name; do not add provider-specific top-level properties back
    - MCP exposes only code-defined local servers and returns typed `mcp_servers`, `mcp_tools`, `mcp_status`, and `mcp_error`
    - chat history/resume is persisted by the Rust `chatstore` layer; keep resume data as typed Qt values at the QML boundary
    - structured QML-facing data must use Qt native types (`QVariantMap`, `QVariantList`, model roles), not JSON strings
- `PacmanUpdatesProvider`
  - Invokables: `refresh(noAur)`, `sync()`
  - Properties: `updates_count`, `aur_updates_count`, `items_count`, `updates_text`, `aur_updates_text`, `last_checked`, `has_updates`, `error`
  - Notes: Rust/CXX-Qt `QAbstractListModel`; roles: `name`, `old_version`, `new_version`, `source`; uses `checkupdates` and `yay -Qua`
- `IcalCache`
  - Invokable: `refresh(days)`
  - Properties: `events_json`, `generated_at`, `status`, `error`
- `TodoistClient`
  - Invokables: `refresh()`, `action(verb, argsJson)`
  - Properties: `data`, `loading`, `error`, `last_updated`
  - Verbs: `"close"`, `"delete"`, `"add"`, `"update"` with `argsJson` as a JSON object string

Runtime requirements:

- `smartctl` for disk health (optional; shows "Unknown" if unavailable)
- `checkupdates` for package update detection
- Secret Service service `quickshell` for API keys, Todoist token, calendar URL, and email passwords
- Ignored `leftpanel/config.toml` for non-secret model/provider/email metadata; tracked shape lives in `leftpanel/config.example.toml`

All network operations run off the UI thread and queue updates back onto Qt via `QMetaObject::invokeMethod(..., Qt::QueuedConnection)`.

AI architecture notes:

- Provider streaming currently lives in `qsnative-rust/src/ai.rs`; keep provider-specific HTTP/payload logic isolated in focused helpers before splitting it into new Rust modules.
- Shared model capability and transcript enrichment logic belongs near the Rust AI/MCP boundary, not in QML or C++ glue.
- MCP server config is separate from provider config and is consumed as typed Qt data from the left panel.
- MCP support includes the local read-only `email` server. Remote HTTP MCP server entries are surfaced as unsupported until a Rust MCP session client is wired in.
- The local email MCP server is read-only by default. It reads account metadata from ignored `leftpanel/config.toml` and Gmail OAuth tokens from Secret Service. Do not expose send tools unless the user explicitly asks for a separate opt-in design.
- When extending the catalog or chat surface, prefer Qt-native structured data at the C++/QML boundary and keep any unavoidable JSON confined to the Rust/C ABI layer.
- MCP/tool-call UI rows must only show content that is sent back to the model. Keep provider output serialization aligned between `ai.rs` and `mcp.rs`; do not maintain provider-specific result/data shapes.

## Coding Style & Naming

- QML/JS: 2-space indentation; explicit `function(args)` handlers; avoid deprecated Quickshell APIs (use `Quickshell.shellDir`/`Quickshell.shellPath()`).
- Naming: QML types/ids `CamelCase`; properties `lowerCamelCase`; constants `UPPER_SNAKE`.
- Performance: never leave animations running while hidden (gate `running` on window visibility).

## Commit & PR Guidelines

- Commits: short, imperative subjects (often lowercase); optional scope prefix like `quickshell: ...`.
- PRs: describe user-visible behavior changes, list manual checks performed, and include screenshots/gifs for UI/animation tweaks.

## Agent Notes

- Use Context7 for Quickshell API lookups (local `quickshell` tracks master).
- **Panic policy**: panics in qs-native are fatal. `lib.rs` installs an abort panic hook via `install_panic_hook()` (called from `IcalCache::initialize`). Do not add `catch_unwind` or swallow panics; let them crash the shell so they surface in logs. Graceful degradation on panics is an anti-pattern here.
