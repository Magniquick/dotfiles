# qs-native (CXX-Qt QML Module) Notes

This directory builds the `qsnative` QML plugin (Rust via CXX-Qt). It provides native-backed QML types used by the Quickshell config (calendar, Todoist, updates, sysinfo, backlight, AI chat/model discovery).

QML import name: `import qsnative`

## Build And Quick Test

- Configure/build:
  - `cd common/modules/qs-native && cmake -S . -B build && cmake --build build`
- QML import path (after build):
  - `common/modules/qs-native/build/qml`
- Quick runtime load check:
  - `QML_IMPORT_PATH=~/.config/quickshell/common/modules/qs-native/build/qml quickshell`

Notes:
- The plugin is a shared library; you must set `QML_IMPORT_PATH` when running Quickshell from the repo.
- The `udev` crate is used; ensure the system has libudev available.

## Source Layout

- `common/modules/qs-native/src/lib.rs`
  - The `#[cxx_qt::bridge]` and QObject backing structs (`*Rust`).
  - Keep `#[qproperty]`-backed fields here so generated code can access them.
- Feature modules:
  - `common/modules/qs-native/src/ai/` (chat + model catalog; uses `rig`)
  - `common/modules/qs-native/src/ical/` (ICS fetching/parsing/cache)
  - `common/modules/qs-native/src/todoist/` (Todoist API)
  - `common/modules/qs-native/src/pacman/` (updates, AUR integration)
  - `common/modules/qs-native/src/sysinfo/` (CPU/mem/disk/temp/uptime/PSI)
  - `common/modules/qs-native/src/backlight/` (internal backlight via sysfs + udev, no polling)
  - `common/modules/qs-native/src/util/` (helpers, tokio runtime, env parsing)

## QML Types (Summary)

Defined in `common/modules/qs-native/src/lib.rs` as `#[qml_element]`:

- `IcalCache`
  - Invokable: `refreshFromEnv(envFile, days)`
  - Properties: `status`, `generated_at`, `error`, `events_json`
  - Notes: Background refresh; caches ETag + ICS in-memory across refreshes.

- `TodoistClient`
  - Invokables: `listTasks(envFile)`, `listTasklists(envFile)`, `completeTask(envFile, id)`, `deleteTask(envFile, id)`
  - Properties: `data_json`, `error`, `last_updated`
  - Notes: Async calls; updates properties on success.

- `PacmanUpdatesProvider`
  - Invokables: `refresh(noAur)`, `sync()`
  - Properties: `updates_count`, `aur_updates_count`, `updates_text`, `aur_updates_text`, `last_checked`, `error`, `has_updates`
  - Notes: `checkupdates` + AUR RPC; bursty refresh calls are coalesced.

- `SysInfoProvider`
  - Invokable: `refresh()`
  - Properties: `cpu`, `mem`, `mem_used`, `mem_total`, `disk`, `disk_health`, `disk_wear`, `temp`, `uptime`, PSI metrics, `disk_device`, `error`
  - Notes: Uses `/proc` + sysfs; disk SMART is cached.

- `BacklightProvider`
  - Invokables: `start()`, `refresh()`, `setBrightness(percent)`
  - Properties: `available`, `device`, `brightness_percent`, `error`
  - Notes:
    - Internal panel only (sysfs `/sys/class/backlight/*`).
    - Watches for changes via libudev monitor and `poll()` on the udev fd (event-driven, no periodic polling).
    - Setting brightness writes `brightness` directly; requires permission to write sysfs backlight files.

- `AiChatSession`
  - Invokables: `submitInput`, `submitInputWithAttachments`, `pasteImageFromClipboard`, `regenerate`, `deleteMessage`, `editMessage`, `resetForModelSwitch`, `appendInfo`, `copyAllText`
  - Properties: `model_id`, `system_prompt`, API keys/base url, `busy`, `status`, `error`, `messages_json`
  - Notes: `QAbstractListModel` streaming assistant output into the last assistant row.

- `AiModelCatalog`
  - Invokable: `refresh()`
  - Properties: API keys/base url, `busy`, `status`, `error`, `models_json`
  - Notes: Fetches provider model lists and outputs a merged JSON list for the model picker.

## Threading Pattern

Rules of thumb used in this module:
- Never block the Qt thread on IO/network.
- Use `self.qt_thread().queue(|obj| { ... })` to update QML properties from background threads.
- Use `tokio` for async network workflows (AI/model catalog), and plain `std::thread::spawn` for short blocking tasks.

## Where It’s Used In This Config

- `bar/services/CalendarService.qml` uses `qsnative.IcalCache`
- `bar/services/TodoistService.qml` uses `qsnative.TodoistClient`
- `bar/services/UpdatesService.qml` uses `qsnative.PacmanUpdatesProvider`
- `bar/services/BrightnessService.qml` uses `qsnative.BacklightProvider` for internal backlight
- `leftpanel/*` uses `qsnative.AiChatSession` and `qsnative.AiModelCatalog`

## Troubleshooting

- If QML errors say `module "qsnative" is not installed`, verify:
  - You built `common/modules/qs-native/build/qml/qsnative/libqsnative.so`
  - `QML_IMPORT_PATH` includes the build `qml` dir.
- If `BacklightProvider` can’t set brightness:
  - Check the sysfs permissions for `/sys/class/backlight/<device>/brightness`.
  - Ensure the session/user has the necessary permissions (udev rules / groups, depending on system setup).
