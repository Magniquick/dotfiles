# Repository Guidelines

This directory contains native/QML modules consumed by the Quickshell config (Wayland/Hyprland). Prefer Quickshell built-in services/APIs where possible; use these modules for capabilities that need native code or vendored QML.

## Project Structure

- `qs-go/`: Go → CGO → C++ Qt plugin (import: `qsgo`). **Primary native module.**
- `unified-lyrics-api/`: Go helper + C++ QML plugin with transparent Spotify/LRCLIB fallback.
- `../materialkit/`: Local MaterialKit QML primitives (Pane/Card/Button/IconButton/Slider/Progress/Ripple).
- `rounded-polygon-qmljs/`: JS/QML shape helpers (vendored).

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
  - Quick test: `QML_IMPORT_PATH=~/.config/quickshell/common/modules/qs-go/build/qml quickshell`
- `unified-lyrics-api`:
  - `cd common/modules/unified-lyrics-api && cmake -S . -B build && cmake --build build`
  - Import path: `common/modules/unified-lyrics-api/build/qml`

No automated test runner is wired up here; verify changes by rebuilding and restarting `quickshell`.

## qs-go (Go / C++ Qt Plugin) Notes

Module: `common/modules/qs-go` (import as `qsgo`).

Pattern: Go packages in `internal/` → C ABI in `capi/main.go` (//export) → C++ QObject in `cpp/` → QML plugin.

Source layout:

- `capi/main.go`: All `//export` C ABI functions + callback typedefs
- `cpp/qsgo_go_api.h`: C header consumed by C++ Qt classes
- `cpp/qsgo_plugin.cpp`: `QQmlExtensionPlugin` registering all types as `qsgo 1.0`
- `internal/sysinfo/`, `internal/backlight/`, `internal/pacman/`, `internal/ical/`, `internal/ai/`, `internal/todoist/`
- AI-specific layout:
  - `internal/ai/providers/`: self-contained inference providers; each provider implements the shared provider interface and owns its HTTP/payload logic
  - `internal/ai/models/helpers/`: shared model capability enrichment and cache helpers keyed by canonical `provider/model` ids
  - `internal/ai/shared/`: provider-agnostic request/response/domain structs shared by providers and the AI entrypoints
  - `internal/ai/mcp/`: MCP 2025-11-25 client runtime built on `github.com/modelcontextprotocol/go-sdk` for HTTP servers, typed server/tool/prompt/resource snapshots, and tool execution

QML types (all in `import qsgo`):

- `SysInfoProvider`
  - Invokable: `refresh(diskDevice)`
  - Properties: `cpu`, `mem`, `mem_used`, `mem_total`, `disk`, `disk_health`, `disk_wear`, `temp`, `uptime`,
    `psi_cpu_some`, `psi_cpu_full`, `psi_mem_some`, `psi_mem_full`, `psi_io_some`, `psi_io_full`, `disk_device`, `error`
- `BacklightProvider`
  - Invokables: `start()`, `refresh()`, `setBrightness(percent)`, `stopMonitor()`
  - Properties: `available`, `brightness_percent`, `device`, `error`
- `AiChatSession`
  - Invokables: `submitInput`, `submitInputWithAttachments`, `cancel`, `pasteImageFromClipboard`, `regenerate`, `deleteMessage`,
    `editMessage`, `resetForModelSwitch`, `appendInfo`, `copyAllText`, `refreshMcp`, `getMcpPrompt`, `readMcpResource`
  - Properties: `model_id`, `system_prompt`, `provider_config`, `mcp_config`, `busy`, `status`, `error`, `commands`,
    `mcp_servers`, `mcp_tools`, `mcp_prompts`, `mcp_resources`, `mcp_status`, `mcp_error`
  - Signals: `streamDone`, `openModelPickerRequested`, `openMoodPickerRequested`, `scrollToEndRequested`, `copyAllRequested(text)`
  - Notes:
    - `QAbstractListModel`; roles: `messageId`, `sender`, `body`, `kind`, `metrics`, `attachments`
    - `model_id` is canonical `provider/model` form, for example `openai/gpt-4o`
    - `provider_config` is a typed `QVariantMap` keyed by provider name; do not add provider-specific top-level properties back
    - `mcp_config` is a typed `QVariantList` of MCP server definitions; the runtime returns typed `mcp_servers`, `mcp_tools`, `mcp_prompts`, and `mcp_resources`
    - slash-command helpers now include `/mcp add`, which opens a QML wizard and persists a minimal MCP server entry into `leftpanel/mcp_servers.json`
    - structured QML-facing data must use Qt native types (`QVariantMap`, `QVariantList`, model roles), not JSON strings
- `AiModelCatalog`
  - Invokable: `refresh()`
  - Properties: `provider_config`, `busy`, `status`, `error`, `providers`
  - Notes:
    - `providers` is a typed `QVariantList` of provider entries, each containing provider metadata, `recommended_models`, and `models`
    - catalog entries expose canonical model ids plus raw provider model ids and structured capability metadata
- `PacmanUpdatesProvider`
  - Invokables: `refresh(noAur)`, `sync()`
  - Properties: `updates_count`, `aur_updates_count`, `items_count`, `updates_text`, `aur_updates_text`, `last_checked`, `has_updates`, `error`
  - Notes: `QAbstractListModel`; roles: `name`, `old_version`, `new_version`, `source`
- `IcalCache`
  - Invokable: `refreshFromEnv(envFile, days)`
  - Properties: `events_json`, `generated_at`, `status`, `error`
- `TodoistClient`
  - Invokables: `refresh()`, `action(verb, argsJson)`
  - Properties: `env_file`, `data`, `loading`, `error`, `last_updated`
  - Verbs: `"close"`, `"delete"`, `"add"`, `"update"` with `argsJson` as a JSON object string

Runtime requirements:

- `smartctl` for disk health (optional; shows "Unknown" if unavailable)
- `checkupdates` for package update detection
- `.env` file referenced by `Config.envFile` for calendar URLs and Todoist token

All network operations run off the UI thread and queue updates back onto Qt via `QMetaObject::invokeMethod(..., Qt::QueuedConnection)`.

AI architecture notes:

- Provider selection is registry-based, not hardcoded by model-name prefix.
- Providers must remain self-contained under `internal/ai/providers/<name>/`.
- Shared enrichment logic belongs in `internal/ai/models/helpers/` or `internal/ai/shared/`, not inside a provider package.
- MCP server config is separate from provider config and is consumed as typed Qt data from the left panel.
- MCP support currently targets remote HTTP servers with static auth headers / bearer tokens.
- Chat streams temporarily install MCP sampling/elicitation handlers onto the shared runtime so server-initiated sampling can reuse the active provider/model.
- When extending the catalog or chat surface, prefer Qt-native structured data at the C++/QML boundary and keep any unavoidable JSON confined to the Go/C ABI layer.

## Coding Style & Naming

- QML/JS: 2-space indentation; explicit `function(args)` handlers; avoid deprecated Quickshell APIs (use `Quickshell.shellDir`/`Quickshell.shellPath()`).
- Naming: QML types/ids `CamelCase`; properties `lowerCamelCase`; constants `UPPER_SNAKE`.
- Performance: never leave animations running while hidden (gate `running` on window visibility).

## Commit & PR Guidelines

- Commits: short, imperative subjects (often lowercase); optional scope prefix like `quickshell: ...`.
- PRs: describe user-visible behavior changes, list manual checks performed, and include screenshots/gifs for UI/animation tweaks.

## Agent Notes

- Use Context7 for Quickshell API lookups (local `quickshell` tracks master).
