# Repository Guidelines

This directory contains native/QML modules consumed by the Quickshell config (Wayland/Hyprland). Prefer Quickshell built-in services/APIs where possible; use these modules for capabilities that need native code or vendored QML.

## Migration Policy

For `qs-go` and the other Go-backed plugins/helpers, use full-sweep migrations. When replacing an API, model shape, provider path, config format, C ABI, or QML-facing type, migrate all in-tree callsites in the same change and remove the superseded path. Backward-compatible wrappers, dual formats, legacy aliases, and compatibility shims are not needed unless the user explicitly requests them; simpler current behavior is preferred even if edge cases change.

## Project Structure

- `qs-go/`: Go -> CGO -> C++ Qt plugin (import: `qsgo`). **Primary native module.**
- `qs-capture/`: C++/Qt capture plugin used by HyprQuickshot.
- `qsmath/`: C++/Qt math rendering plugin used by left-panel message math blocks.
- `material-popups/`: Rust/CXX-Qt clipboard and input watcher backend for the QML clipboard popup.
- `unified-lyrics-api/`: Go helper + C++ QML plugin with transparent Spotify/LRCLIB fallback.
- `../materialkit/`: Local MaterialKit QML primitives (Pane/Card/Button/IconButton/Slider/Progress/Ripple).
- `rounded_polygon_qmljs/`: JS/QML shape helpers tracked as a git submodule.

Related entry points live above this folder (examples: `shell.qml`, `bar/`, `powermenu/`, `hyprquickshot/`).

## Build, Test, and Dev Commands

From the Quickshell config root:

- Run main shell: `./qs`
- Run a config: `quickshell -c powermenu` (or `./qs -c powermenu`)
- HyprQuickshot: run `./qs`, then trigger it via your keybind or `qs ipc call hyprquickshot open`

Build native modules:

- `qs-go`: `./tools/build-qs-go.sh`
  - Import path: `common/modules/qs-go/build/qml`
  - On first build, run `cd common/modules/qs-go && go mod tidy` to populate go.sum
  - When Go source changes: `./tools/build-qs-go.sh` (CMake tracks Go sources via GLOB_RECURSE; only use `rm -rf common/modules/qs-go/build` if C++ headers change or the build is corrupt)
  - Quick test from repo root: `env QML_IMPORT_PATH="$PWD/common/modules/qs-go/build/qml" quickshell`
- `qs-capture`: `bash tools/build-qs-capture.sh`
  - Import path: `common/modules/qs-capture/build/qml`
- `qsmath`: `bash tools/build-qsmath.sh`
  - Import path: `common/modules/qsmath/build/qml`
- `material-popups`: `bash tools/build-material-popups.sh`
  - Import path: `common/modules/material-popups/build/qml`
- `unified-lyrics-api`:
  - `bash tools/build-cmake-module.sh unified-lyrics-api`
  - Import path: `common/modules/unified-lyrics-api/build/qml`

No root-level test runner is wired up. For Go changes, run focused package tests in the module you touched (for example `cd common/modules/qs-go && go test ./... -count=1`), rebuild the affected native module, then finish with `bash tools/reload-quickshell.sh`.

## qs-go (Go / C++ Qt Plugin) Notes

Module: `common/modules/qs-go` (import as `qsgo`).

Pattern: Go packages in `internal/` → C ABI in `capi/main.go` (//export) → C++ QObject in `cpp/` → QML plugin.

Source layout:

- `capi/main.go`: All `//export` C ABI functions + callback typedefs
- `cpp/qsgo_go_api.h`: C header consumed by C++ Qt classes
- `cpp/qsgo_plugin.cpp`: `QQmlExtensionPlugin` registering all types as `qsgo 1.0`
- `internal/sysinfo/`, `internal/backlight/`, `internal/pacman/`, `internal/ical/`, `internal/ai/`, `internal/todoist/`
- `internal/appconfig/`: non-secret TOML config loader for `leftpanel/config.toml`
- `internal/secrets/`: Secret Service lookup boundary for keys/tokens/passwords
- AI-specific layout:
  - `internal/ai/providers/`: self-contained inference providers; each provider implements the shared provider interface and owns its HTTP/payload logic
  - `internal/ai/models/helpers/`: shared model capability helpers keyed by canonical `provider/model` ids
  - `internal/ai/shared/`: provider-agnostic request/response/domain structs shared by providers and the AI entrypoints
  - `internal/ai/mcp/`: MCP 2025-11-25 client runtime built on `github.com/modelcontextprotocol/go-sdk` for HTTP servers, local built-in tools, typed server/tool/prompt/resource snapshots, and tool execution

QML types (all in `import qsgo`):

- `SysInfoProvider`
  - Invokable: `refresh()`
  - Properties: `cpu`, `mem`, `mem_used`, `mem_total`, `disk`, `disk_health`, `disk_wear`, `temp`, `uptime`,
    `disk_worst_case`, `disk_btrfs_available`, `disk_btrfs_free_est_gib`, `disk_btrfs_free_min_gib`,
    `psi_cpu_some`, `psi_cpu_full`, `psi_mem_some`, `psi_mem_full`, `psi_io_some`, `psi_io_full`, `disk_device`, `error`
- `BacklightProvider`
  - Invokables: `start()`, `startMonitor()`, `refresh()`, `setBrightness(percent)`, `stopMonitor()`
  - Properties: `available`, `brightness_percent`, `device`, `error`
- `ConfigResolver`
  - Invokable: `refresh()`
  - Properties: `values`
  - Notes: central QML-facing bridge combining `internal/appconfig` non-secret TOML with `internal/secrets` provider API keys
- `AiChatSession`
  - Invokables: `submitInput`, `submitInputWithAttachments`, `cancel`, `pasteImageFromClipboard`, `regenerate`, `deleteMessage`,
    `editMessage`, `resetForModelSwitch`, `appendInfo`, `copyAllText`, `pasteAttachmentFromClipboard`, `restoreHistory`,
    `refreshMcp`, `getMcpPrompt`, `readMcpResource`, `refreshResumeConversations`, `resumeConversation`
  - Properties: `model_id`, `system_prompt`, `provider_config`, `mcp_config`, `busy`, `status`, `error`, `commands`,
    `mcp_servers`, `mcp_tools`, `mcp_prompts`, `mcp_resources`, `mcp_status`, `mcp_error`, `resume_conversations`
  - Signals: `streamDone`, `openModelPickerRequested`, `openMoodPickerRequested`, `openResumePickerRequested`, `openMcpAddRequested`, `scrollToEndRequested`, `copyAllRequested(text)`
  - Notes:
    - `QAbstractListModel`; roles: `messageId`, `sender`, `body`, `kind`, `metrics`, `attachments`, `tool`, `showHeader`
    - `model_id` is canonical `provider/model` form, for example `openai/gpt-4o`
    - `provider_config` is a typed `QVariantMap` keyed by provider name; do not add provider-specific top-level properties back
    - `mcp_config` is a typed `QVariantList` of remote MCP server definitions; the runtime also appends local built-in MCP servers and returns typed `mcp_servers`, `mcp_tools`, `mcp_prompts`, and `mcp_resources`
    - slash-command helpers now include `/mcp add`, which opens a QML wizard and persists a minimal MCP server entry into `leftpanel/mcp_servers.json`
    - Todoist is configured from Secret Service as a hosted streamable MCP server at `https://ai.todoist.net/mcp`; do not use an `npx` Todoist server.
    - chat history/resume is persisted by the qs-go `internal/chatstore` layer; keep resume data as typed Qt values at the QML boundary
    - structured QML-facing data must use Qt native types (`QVariantMap`, `QVariantList`, model roles), not JSON strings
- `PacmanUpdatesProvider`
  - Invokables: `refresh(noAur)`, `sync()`
  - Properties: `updates_count`, `aur_updates_count`, `items_count`, `updates_text`, `aur_updates_text`, `last_checked`, `has_updates`, `error`
  - Notes: `QAbstractListModel`; roles: `name`, `old_version`, `new_version`, `source`
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
- Secret Service service `quickshell` for API keys, Todoist token, calendar URL, Spotify `SP_DC`, and email passwords
- Ignored `leftpanel/config.toml` for non-secret model/provider/email metadata; tracked shape lives in `leftpanel/config.example.toml`

All network operations run off the UI thread and queue updates back onto Qt via `QMetaObject::invokeMethod(..., Qt::QueuedConnection)`.

AI architecture notes:

- Provider selection is registry-based, not hardcoded by model-name prefix.
- Providers must remain self-contained under `internal/ai/providers/<name>/`.
- Shared enrichment logic belongs in `internal/ai/models/helpers/` or `internal/ai/shared/`, not inside a provider package.
- MCP server config is separate from provider config and is consumed as typed Qt data from the left panel.
- MCP support includes remote HTTP servers with static auth headers / bearer tokens plus local built-in servers such as `builtin` and `email`.
- The local email MCP server is read-only by default. It reads account metadata from ignored `leftpanel/config.toml` and passwords from Secret Service as `EMAIL_<ID>_PASSWORD` or compatible secret keys. `provider = "gmail"` defaults IMAP to `imap.gmail.com:993` with TLS. Do not expose send tools unless the user explicitly asks for a separate opt-in design.
- Chat streams temporarily install MCP sampling/elicitation handlers onto the shared runtime so server-initiated sampling can reuse the active provider/model.
- When extending the catalog or chat surface, prefer Qt-native structured data at the C++/QML boundary and keep any unavoidable JSON confined to the Go/C ABI layer.
- MCP/tool-call UI rows must only show content that is sent back to the model. Keep provider output serialization aligned through `internal/ai/shared.ToolResultTranscriptPayload` and `ToolResultTranscriptOutput`; do not maintain provider-specific result/data shapes.

## Coding Style & Naming

- QML/JS: 2-space indentation; explicit `function(args)` handlers; avoid deprecated Quickshell APIs (use `Quickshell.shellDir`/`Quickshell.shellPath()`).
- Naming: QML types/ids `CamelCase`; properties `lowerCamelCase`; constants `UPPER_SNAKE`.
- Performance: never leave animations running while hidden (gate `running` on window visibility).

## Commit & PR Guidelines

- Commits: short, imperative subjects (often lowercase); optional scope prefix like `quickshell: ...`.
- PRs: describe user-visible behavior changes, list manual checks performed, and include screenshots/gifs for UI/animation tweaks.

## Agent Notes

- Use Context7 for Quickshell API lookups (local `quickshell` tracks master).
