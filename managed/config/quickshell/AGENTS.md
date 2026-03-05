# Repository Guidelines

This file provides guidance for working with code in this repository.

## Project Overview

Custom Quickshell configuration for Wayland/Hyprland featuring a modular status bar, left/right panels, powermenu, screenshot utilities (HyprQuickshot), and system clock. Quickshell is a Qt/QML-based compositor shell toolkit.

## Documentation

Always use Context7 to look up Quickshell documentation. The Quickshell binary locally tracks the master branch.

## Build and Run Commands

**Running the shell:**

- Main shell (bar + panels + clock + panels): `./qs` from the root directory.
- Powermenu: `quickshell -c powermenu` or `qs -c powermenu`
- HyprQuickshot (screenshot utility): `quickshell -c hyprquickshot -n` (the `-n` prevents multiple instances)
- Reload: Restart `quickshell` after QML changes (no hot reload)
- Global config is at `quickshell.conf`

**Native modules (Rust/Go/C++):**

- Build, import-path, and module notes live in `common/modules/AGENTS.md` (and module-specific `common/modules/*/AGENTS.md`).
- Prefer golang based modules unless asked otherwise.

## Architecture

### Entry Points and Shell Structure

- **Root shell** (`shell.qml`): Loads bar per screen via `Variants` over `Quickshell.screens` + left/right panels
- **Bar** (`bar/shell.qml` → `bar/BarWindow.qml`): Status bar with three-section layout (left/center/right)
- **Left panel** (`leftpanel/shell.qml` → `leftpanel/LeftPanel.qml`): Left-side overlay panel
- **Right panel** (`rightpanel/shell.qml` → `rightpanel/RightPanel.qml`): Right-side overlay panel
- **Powermenu** (`powermenu/shell.qml` → `powermenu/Powermenu.qml`): Overlay with system actions (poweroff/reboot/lock/hibernate/suspend/windows/etc)
- **HyprQuickshot** (`hyprquickshot/shell.qml`): Screenshot tool with region/window/monitor selection

### Module System

The bar uses a **modular architecture** with key directories:

1. **`bar/components/`** : Reusable UI building blocks

   - `ModuleContainer.qml`: Base wrapper for bar modules
   - `TooltipPopup.qml`: Tooltip system with scrolling support (Flickable + ScrollIndicator)
   - `IconTextRow.qml`, `BarLabel.qml`, `ActionChip.qml`: Common UI primitives (ActionChip has flash animation + loading spinner)
   - `JsonUtils.js`: Robust JSON parsing utilities (`safeParse`, `parseObject`, `parseArray`, `formatTooltip`)
   - `CommandRunner.qml`: Process execution helper with stderr capture, timeout, error signals

1. **`bar/`** (singletons in qmldir):

   - `Config`: Design tokens (fonts, spacing, colors, slider constants) from `common/Config.qml`
   - `ColorPalette`: Material palette + color roles from `common/ColorPalette.qml` / `common/colors.json`
   - `DependencyCheck`: Centralized dependency checking with notify-send alerts
   - `GlobalState`: Shared runtime state (left/right panel visibility)

1. **`bar/modules/`** : Feature modules, organized into groups

   - **Groups**: `StartMenuGroup`, `WorkspaceGroup`, `ControlsGroup`, `WirelessGroup`, `PanelGroup`
   - **Individual modules**: `MprisModule`, `NetworkModule`, `BatteryModule`, `BacklightModule`, `NotificationModule`, `PrivacyModule`, `TrayModule`, `SystemdFailedModule`, `WireplumberModule`, `ToDoModule`, etc.

### Native Modules (Rust/Go/C++)

Native module notes live in `common/modules/AGENTS.md` (plus module-specific docs like `common/modules/qs-native/AGENTS.md`).

### Data Sources & Runtime Integration

Modules integrate with system services via:

- **Quickshell services**: `Quickshell.Services.Mpris`, `Quickshell.Services.SystemTray`, `Quickshell.Hyprland` (workspaces)
- **Sysfs/udev**: Internal backlight via `qsgo.BacklightProvider` (sysfs + udev, no polling)
- **External commands**:
  - `nmcli` for network status/wifi
  - `systemctl --failed` + `busctl monitor` for systemd units
  - `pw-dump` + `fuser /dev/video*` for privacy monitoring (camera/microphone detection)
  - Updates: `checkupdates` + `pacman -Qm` (via `qsgo` PacmanUpdatesProvider)
- **Native helpers**: see `common/modules/AGENTS.md` (and module-specific docs under `common/modules/`)

However, try to use native quickshell modules if available. If not, fallback to shelling out or implementing a golang based module, based on user input.

### Styling System

- **Theme**: Material colors from Matugen JSON in `common/colors.json` via `common/Colors.qml`
- **Config**: Design tokens in `common/Config.qml` (singleton), imported directly or via bar singleton
  - Fonts: `fontFamily: "Google Sans"`, `iconFontFamily: "JetBrainsMono NFP"`
  - Spacing/motion: `Config.space.*`, `Config.motion.duration.*`, `Config.shape.corner.*`
  - Colors: `Config.color` and `Config.palette` (from `common/Colors.qml`)
  - Typography: `Config.type.*` defines Material type scale (display/headline/title/body/label)
- **Layering**: Bar uses `WlrLayershell.layer: WlrLayer.Background`; powermenu uses `Overlay` + `Exclusive` keyboard focus

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
      DependencyCheck.require("nmcli", "NetworkModule", function(available) {
          root.nmcliAvailable = available;
      });
  }
  ```

**Process Crash Recovery:**

- Long-running monitors (nmcli, udevadm, busctl) use exponential backoff restart
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

**No automated tests.** Manual verification required: run ./qs at repo root with a short timeout and monitor output logs.
- In sandboxed/CI-like environments, `libEGL`/`MESA` warnings about `/dev/dri` (for example `failed to open /dev/dri/renderD128: Permission denied`) are expected and can be ignored.
- **Lockscreen safety**: Never terminate/kill a running lockscreen instance unless authentication has succeeded and the session unlock path is executing. Do not use timeout/force-kill smoke tests (`timeout ... quickshell --path lockscreen`) against active lock sessions, as this can leave Hyprland in an invalid lock state.

## Dependencies

- **Build**: Qt6 QML modules; native module builds may require `cmake`, `cargo`, and/or `go` (see `common/modules/AGENTS.md`)
- **Versioning**: Track Quickshell `master` branch; when using Context7, target the `master` branch docs.

## Commit & PR Guidelines

- Commits: short imperative subject (e.g., `Add powermenu action`, `Tighten esc shortcut`); group related edits.
- PRs: describe behavior changes, mention manual checks performed, and include screenshots/gifs for UI tweaks.

## Performance Notes

- Animations in hidden windows (`visible: false`) still consume CPU if `running: true`
- Always gate animation `running` property with window visibility checks
- Example fix: `running: root.QsWindow.window && root.QsWindow.window.visible`
