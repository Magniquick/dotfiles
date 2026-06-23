# Repository Guidelines

This file provides guidance for working with code in this repository.

## Project Overview

Custom Quickshell configuration for Wayland/Hyprland featuring a modular status bar, left/right panels, powermenu, resident lock controller, and screenshot/recording utilities through HyprQuickshot. Quickshell is a Qt/QML-based compositor shell toolkit.

## Compatibility Policy

Backward compatibility inside this configuration is not a goal unless the user explicitly asks for it. Prefer full-sweep migrations: update every in-tree caller, binding, config shape, and doc in the same change, then delete the old path. Do not keep legacy shims, compatibility facades, aliases, or dead fallback branches just to preserve edge-case behavior in this codebase.

For persisted local state such as SQLite rows or generated config, migrate or rewrite the stored data directly when the shape changes. Do not add runtime converters, normalizers, or "read old shape" branches for stale local rows unless the user explicitly asks for a compatibility layer.

## Documentation

Use Context7 to look up Quickshell documentation as needed (e.g: when debugging complex issues or when implementing new features).
The Quickshell binary locally tracks the master branch.

## Build and Run Commands

**Running the shell:**

- Main shell (bar + panels + lock controller + HyprQuickshot/powermenu loaders): `./qs` from the root directory.
- Powermenu: `quickshell -c powermenu` or `qs -c powermenu`
- HyprQuickshot (screenshot utility): run the main shell with `./qs`, then trigger it via your keybind or `qs ipc call hyprquickshot open`
- Reload: auto reload is disabled; use `bash tools/reload-quickshell.sh` for the normal manual check. It restarts `quickshell.service`, waits briefly, then prints recent warnings/errors.
- Global config is at `quickshell.conf`

**Native modules (Rust/C++/QML):**

- Build, import-path, and module notes live in `common/modules/AGENTS.md`.
- Current native/module directories include `qs-native` (primary Rust/CXX-Qt Qt plugin), `qs-capture` (native capture), `qsmath` (math rendering), `material-popups` (Rust/CXX-Qt clipboard popup backend), `unified-lyrics-api`, and `rounded_polygon_qmljs`.
- Prefer Rust/CXX-Qt modules for new reusable native integrations unless asked otherwise.

## Architecture

### Entry Points and Shell Structure

- **Root shell** (`shell.qml`): Loads bar per screen via `Variants` over `Quickshell.screens`, left/right panels, resident lock controller, powermenu, and HyprQuickshot
- **Powermenu** (`powermenu/shell.qml` → `powermenu/Powermenu.qml`): Overlay with system actions (poweroff/reboot/lock/hibernate/suspend/windows/etc)
- **Lockscreen** (`lockscreen/shell.qml` + `lockscreen/LockController.qml`): resident lock controller in the main shell with a standalone fallback shell
- **HyprQuickshot** (`hyprquickshot/HyprQuickshot.qml`): Screenshot tool with region/window/monitor selection

### Module System

The bar uses a **modular architecture** with key directories:

1. **`bar/components/`** : Reusable UI building blocks

   - `ModuleContainer.qml`: Base wrapper for bar modules
   - `TooltipPopup.qml`: Tooltip system with scrolling support (Flickable + ScrollIndicator)
   - `IconLabel.qml`, `IconTextRow.qml`, `BarLabel.qml`, `ActionChip.qml`, `ActionIconButton.qml`: Common UI primitives
   - `ProcessMonitor.qml`, `TrafficGraph.qml`, `TooltipCard.qml`, `UpdatesTooltip.qml`, `CalendarTooltip.qml`: Shared behavior/tooltip helpers
   - `common/JsonUtils.js`: Robust JSON parsing utilities (`safeParse`, `parseObject`, `parseArray`, `formatTooltip`)
   - `CommandRunner.qml`: Process execution helper with stderr capture, timeout, error signals

1. **`bar/`** (singletons in qmldir):

   - `Config`: Design tokens (fonts, spacing, colors, slider constants) from `common/Config.qml`
  - `Colors`: Material palette + color roles from `common/Colors.qml` / `common/colors.json`
   - `DependencyCheck`: Centralized dependency checking with notify-send alerts
   - `GlobalState`: Shared runtime state (panels, powermenu, HyprQuickshot, recording, idle-inhibit, lock state)
   - Service singletons: `BrightnessService`, `CalendarService`, `NetworkService`, `PrivacyService`, `SystemdFailedService`, `TodoistService`, `UpdatesService`

1. **`bar/modules/`** : Feature modules, organized into groups

   - **Groups**: `StartMenuGroup`, `WorkspaceGroup`, `ControlsGroup`, `WirelessGroup`, `PanelGroup`
   - **Individual modules**: `MprisModule`, `NetworkModule`, `BluetoothModule`, `BatteryModule`, `BacklightModule`, `IdleInhibitModule`, `ScreenRecordingModule`, `PowerProfilesModule`, `NotificationModule`, `PrivacyModule`, `TrayModule`, `SystemdFailedModule`, `UpdatesModule`, `ClockModule`, `WireplumberModule`, `ToDoModule`, etc.

### Native Modules (Rust/C++/QML)

Native module notes live in `common/modules/AGENTS.md`. The primary QML plugin is `qs-native` (`import qsnative`), with focused modules for capture (`qs-capture`), math rendering (`qsmath`), lyrics (`unified-lyrics-api`), and rounded shape helpers (`rounded_polygon_qmljs`).

### Data Sources & Runtime Integration

Modules integrate with system services via:

- **Quickshell services/APIs**: `Quickshell.Services.Mpris`, `Quickshell.Services.SystemTray`, `Quickshell.Hyprland`, `Quickshell.Networking`, `Quickshell.Bluetooth`, `Quickshell.Services.Pipewire`, `Quickshell.Services.UPower`
- **Native helpers**: `qsnative.BacklightProvider`, `NetStatsProvider`, `PacmanUpdatesProvider`, `IcalCache`, `TodoistClient`, `SysInfoProvider`, `AiChatSession`, plus `qs-capture`, `qsmath`, and `unifiedlyrics`
- **External commands**:
  - `ip` for current address/gateway details that `Quickshell.Networking` does not expose; ethernet sysfs/udev metadata is owned by `qsnative.NetStatsProvider`
  - `ddcutil` for external monitor brightness
  - `qsnative.SystemdFailedProvider` for failed unit lists; it snapshots with structured `systemctl --output=json` and refreshes from systemd D-Bus events
  - `inotifywait` + `fuser` + `ps` for camera device ownership; PipeWire covers microphone/screencast state
  - Debug-only `busctl`, `dbus-monitor`, and `ps` for Bluetooth discovery diagnostics and librepods tray metadata
  - `hp-charge-control` for battery charge policy controls
  - `wl-screenrec`, `wl-copy`, and `pactl` for HyprQuickshot recording/copy/audio flows
  - Updates: `checkupdates` and `yay -Qua` (via `qsnative` PacmanUpdatesProvider)

Prefer native Quickshell APIs when available. If not, prefer the existing `qs-native` Rust-native path for reusable integrations; shell out only for narrow command-backed gaps or when the user asks for it.

For AI MCP/tool-call rows, the UI must only show content that is sent back to the model. If a row shows structured result data, provider serialization must include that same data through the shared qs-native tool-result helpers; do not add provider-specific result/data splits.

### Styling System

- **Theme**: Material colors from Matugen JSON in `common/colors.json` via `common/Colors.qml`
- **Config**: Design tokens in `common/Config.qml` (singleton), imported directly or via bar singleton
  - Fonts: `fontFamily: "Google Sans Flex"`, `iconFontFamily: "Symbols Nerd Font Mono"`
  - Spacing/motion: `Config.space.*`, `Config.motion.duration.*`, `Config.shape.corner.*`
  - Colors: `Config.color` and `Config.palette` (from `common/Colors.qml`)
  - Typography: `Config.type.*` defines Material type scale (display/headline/title/body/label)
- **Layering**: Bar uses `WlrLayershell.layer: WlrLayer.Top`; left/right panels use overlay windows with on-demand focus; powermenu uses overlay + exclusive keyboard focus

### Color Roles (Material 3)

Use semantic roles from `Config.color.*` instead of hardcoding hex values. These are generated by Matugen and mapped to Material roles.

**Primary / Accent**

- `primary`: high-emphasis actions (primary buttons, active toggles)
- `on_primary`: text/icons on `primary`
- `primary_container`: selected/tonal fills (chips, highlighted rows)
- `on_primary_container`: text/icons on `primary_container`

**Secondary / Tertiary**

- `secondary`, `tertiary`: supporting accents (secondary actions, subtle emphasis)
- `on_secondary`, `on_tertiary`: text/icons on those accents
- `secondary_container`, `tertiary_container`: softer fills for low-priority highlights

**Surfaces & Backgrounds**

- `background`: app root background
- `surface`: large surfaces/sheets
- `surface_container_*`: elevation ladder for cards, popups, dialogs (`low` → `highest`)
- `on_background`, `on_surface`: standard text/icon colors on those surfaces
- `on_surface_variant`: medium-emphasis text (subtitles, metadata)

**Outlines & Dividers**

- `outline`, `outline_variant`: borders, dividers, input outlines

**Status / Feedback**

- `error`: error states and critical indicators
- `on_error`: text/icons on error fills

**Inverse roles**

- `inverse_surface`, `inverse_on_surface`, `inverse_primary`: contrast surfaces (snackbars/tooltips or inverted UI)

**Palette notes**

- `Config.palette.*` is the raw tonal palette; prefer roles unless implementing custom tone ramps.

## Coding Conventions

**QML/JS Style:**

- 2-space indentation
- Concise arrow functions/inline handlers
- Keep signal handlers readable and scoped
- Avoid deprecated Quickshell APIs:
  - Use `Quickshell.shellDir`/`Quickshell.shellPath()` NOT `configDir`/`configPath`
  - Use explicit `function(args)` handlers instead of parameter injection
- Prefer `Qt.alpha(color, alpha)` over `Qt.rgba(color.r, color.g, color.b, alpha)`
- Keep base colors opaque and apply alpha at use sites; avoid `Qt.alpha(Qt.rgba(..., 1), alpha)` for constants

**Naming:**

- QML types/IDs: `CamelCase` (e.g., `ModuleContainer`, `root`)
- Properties/functions: `lowerCamelCase` (e.g., `activePlayer`, `displayTitle`)
- Constants: `UPPER_SNAKE` (e.g., `MAX_LENGTH`)
- Module-specific names: Explicit prefixes (e.g., `powermenuVisible`, `powermenuHover`)

**Component Design:**

- Prefer small, focused components
- Shared colors in `Config.color` / `Config.palette`
- Keep modules self-contained with clear data flow

## Error Handling Patterns

**Dependency Checking:**

- Use `DependencyCheck.require(cmd, moduleName, callback)` for PATH commands
- Use `DependencyCheck.requireExecutable(path, moduleName, callback)` for scripts
- Notifies user via `notify-send` if dependency missing (once per dep)
- Example:
  ```qml
  Component.onCompleted: {
      DependencyCheck.require("ddcutil", "BrightnessService", function(available) {
          root.ddcutilAvailable = available;
      });
  }
  ```

**Process Crash Recovery:**

- Long-running monitors (`dbus-monitor`, `inotifywait`, Bluetooth diagnostics, etc.) use exponential backoff restart where they are expected to stay alive
- Pattern: `monitorRestartAttempts`, `monitorRestartTimer`, `monitorBackoffResetTimer`
- Backoff: 1s → 2s → 4s → ... → 30s max, resets after 60s stability
- Set `monitorDegraded: true` on crash for optional UI indicator

**CommandRunner:**

- Supports `timeoutMs`, `onError(errorOutput, exitCode)`, `onTimeout()` signals
- Stderr captured in `errorOutput` property
- Triggers immediately when enabled (no initial interval wait)

## UI/UX Principles

- **Material-inspired, intentional layouts**: No default system fonts; use explicit `Config` families
- **Design quality for additions**: Any new UI/feature must follow well thought out UI/UX principles, including complete UX flows (entry points, state transitions, empty/error/loading states, and exit paths).
- **Color semantics**: Use `Config.color.*` roles (primary/secondary/error/success)
- **Animations**: Meaningful transitions only (open/close reveals, tooltip fades); avoid noisy micro-motions
  - Always gate animations with visibility checks. Hidden components with `running: true` animations burn idle CPU.
- **Tooltips**: Anchor above targets, stay unclipped; modules can collapse when empty
- **Powermenu**: Animates cleanly, retains focus on open, hides on `Esc`/`q`, quits on dismiss
- **Fallback policy**: Do not add fallback handling for failures or missing functionality unless explicitly requested.

## Testing

No root-wide QML test suite is defined. Native modules have focused checks; follow `common/modules/AGENTS.md` when changing those paths.

Manual verification should usually use `bash tools/reload-quickshell.sh`; the happy path is a service restart followed by "No warnings or errors" from the recent log tail.
- In sandboxed/CI-like environments, `libEGL`/`MESA` warnings about `/dev/dri` (for example `failed to open /dev/dri/renderD128: Permission denied`) are expected and can be ignored.
- **Lockscreen safety**: Never terminate/kill a running lockscreen instance unless authentication has succeeded and the session unlock path is executing. Do not use timeout/force-kill smoke tests (`timeout ... quickshell --path lockscreen`) against active lock sessions, as this can leave Hyprland in an invalid lock state.

## Dependencies

- **Build**: Qt6 QML modules; native module builds use CMake, Corrosion/Cargo for Rust/CXX-Qt modules, and Qt C++ tooling for C++ plugins (see `common/modules/AGENTS.md`)
- **Versioning**: Track Quickshell `master` branch; when using Context7, target the `master` branch docs.

## Commit & PR Guidelines

- Commits: short imperative subject (e.g., `Add powermenu action`, `Tighten esc shortcut`); group related edits.
- PRs: describe behavior changes, mention manual checks performed, and include screenshots/gifs for UI tweaks.

## Performance Notes

- Animations in hidden windows (`visible: false`) still consume CPU if `running: true`
- Always gate animation `running` property with window visibility checks
- Example fix: `running: root.QsWindow.window && root.QsWindow.window.visible`
