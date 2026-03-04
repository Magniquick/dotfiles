# Repository Guidelines

This directory contains native/QML modules consumed by the Quickshell config (Wayland/Hyprland). Prefer Quickshell built-in services/APIs where possible; use these modules for capabilities that need native code or vendored QML.

## Project Structure

- `qs-go/`: Go → CGO → C++ Qt plugin (import: `qsgo`). **Primary native module.**
- `spotify-lyrics-api/`: Go helper package for Spotify lyrics (backend dependency of unified module).
- `unified-lyrics-api/`: Go helper + C++ QML plugin with transparent Spotify/LRCLIB fallback.
- `QmlMaterial/`: Vendored Material/QML library (CMake build).
- `rounded-polygon-qmljs/`: JS/QML shape helpers (vendored).

Related entry points live above this folder (examples: `shell.qml`, `bar/`, `powermenu/`, `hyprquickshot/`).

## Build, Test, and Dev Commands

From the Quickshell config root:

- Run main shell: `./qs`
- Run a config: `quickshell -c powermenu` (or `./qs -c powermenu`)
- HyprQuickshot: `quickshell -c hyprquickshot -n`

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
    `editMessage`, `resetForModelSwitch`, `appendInfo`, `copyAllText`
  - Properties: `model_id`, `system_prompt`, `openai_api_key`, `gemini_api_key`, `openai_base_url`, `busy`, `status`, `error`
  - Signals: `streamDone`, `openModelPickerRequested`, `openMoodPickerRequested`, `scrollToEndRequested`, `copyAllRequested(text)`
  - Notes: `QAbstractListModel`; roles: `messageId`, `sender`, `body`, `kind`
- `AiModelCatalog`
  - Invokable: `refresh()`
  - Properties: `openai_api_key`, `gemini_api_key`, `openai_base_url`, `busy`, `status`, `error`, `models_json`
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

## Coding Style & Naming

- QML/JS: 2-space indentation; explicit `function(args)` handlers; avoid deprecated Quickshell APIs (use `Quickshell.shellDir`/`Quickshell.shellPath()`).
- Naming: QML types/ids `CamelCase`; properties `lowerCamelCase`; constants `UPPER_SNAKE`.
- Performance: never leave animations running while hidden (gate `running` on window visibility).

## Commit & PR Guidelines

- Commits: short, imperative subjects (often lowercase); optional scope prefix like `quickshell: ...`.
- PRs: describe user-visible behavior changes, list manual checks performed, and include screenshots/gifs for UI/animation tweaks.

## Agent Notes

- Use Context7 for Quickshell API lookups (local `quickshell` tracks master).
