# Repository Guidelines

This file provides guidance for working with code in this repository.

## Project Overview

Custom Quickshell configuration for Wayland/Hyprland featuring a modular status bar, powermenu, screenshot utility (HyprQuickshot), and system clock. Quickshell is a Qt/QML-based compositor shell toolkit.

## Build and Run Commands

**Running the shell:**
- Main shell (bar + clock): `quickshell` (or `qs`) from repo root
- Bar only: `quickshell -c bar` or `qs -c bar`
- Powermenu: `quickshell -c powermenu` or `qs -c powermenu`
- HyprQuickshot (screenshot utility): `quickshell -c hyprquickshot -n` (the `-n` prevents multiple instances)
- Reload: Restart `quickshell` after QML changes (no hot reload)

**Building Rust helper scripts:**
- ical-cache: `cd bar/scripts/src/ical-cache && cargo build --release`
- todoist-api: `cd bar/scripts/src/todoist-api && cargo build --release`

**Configuration:**
- HyprQuickshot saves screenshots to `$HQS_DIR` → `$XDG_SCREENSHOTS_DIR` → `$XDG_PICTURES_DIR` → `$HOME/Pictures`
- Global config: `quickshell.conf`

**QML Language Server:**
- VS Code: Ensure `"qt-qml.qmlls.useQmlImportPathEnvVar": true` in `.vscode/settings.json`

## Architecture

### Entry Points and Shell Structure

- **Root shell** (`shell.qml`): Loads bar per screen via `Variants` over `Quickshell.screens` + clock widget
- **Bar** (`bar/shell.qml` → `bar/BarWindow.qml`): Status bar with three-section layout (left/center/right)
- **Powermenu** (`powermenu/shell.qml` → `powermenu/Powermenu.qml`): Overlay with system actions (lock/logout/reboot/shutdown)
- **HyprQuickshot** (`hyprquickshot/shell.qml`): Screenshot tool with region/window/monitor selection

### Module System

The bar uses a **modular architecture** with key directories:

1. **`bar/components/`** (~21 files): Reusable UI building blocks
   - `ModuleContainer.qml`: Base wrapper for bar modules
   - `TooltipPopup.qml`: Tooltip system with scrolling support (Flickable + ScrollIndicator)
   - `IconTextRow.qml`, `BarLabel.qml`, `ActionChip.qml`: Common UI primitives (ActionChip has flash animation + loading spinner)
   - `JsonUtils.js`: Robust JSON parsing utilities (`safeParse`, `parseObject`, `parseArray`, `formatTooltip`)
   - `CommandRunner.qml`: Process execution helper with stderr capture, timeout, error signals

2. **`bar/`** (singletons in qmldir):
   - `Config.qml`: Design tokens (fonts, spacing, colors, slider constants); sourced from `common/Config.qml`
   - `Colors.qml`: Material palette + color roles (from `common/colors.json`)
   - `DependencyCheck.qml`: Centralized dependency checking with notify-send alerts

3. **`bar/modules/`** (~24 files): Feature modules, organized into groups
   - **Groups**: `StartMenuGroup`, `WorkspaceGroup`, `ControlsGroup`, `WirelessGroup`, `PanelGroup`
   - **Individual modules**: `ClockModule`, `MprisModule`, `NetworkModule`, `BatteryModule`, `BacklightModule`, `BluetoothModule`, `NotificationModule`, `PrivacyModule`, `TrayModule`, `UpdatesModule`, `SystemdFailedModule`, etc.

### Data Sources & Runtime Integration

Modules integrate with system services via:
- **Quickshell services**: `Quickshell.Services.Mpris`, `Quickshell.Services.SystemTray`, `Quickshell.Hyprland` (workspaces)
- **Sysfs/udev**: Backlight (`/sys/class/backlight/<device>/actual_brightness` + `udevadm monitor`)
- **External commands**:
  - `nmcli` for network status/wifi
  - `systemctl --failed` + `busctl monitor` for systemd units
  - `swaync-client -swb` for notifications
  - `pw-dump` + `fuser /dev/video*` for privacy monitoring (camera/microphone detection)
  - Custom scripts: `waybar/scripts/status.sh` (Arch icon tooltip), `waybar-module-pacman-updates` (system updates JSON stream)
- **Rust helpers**: `ical-cache` (calendar), `todoist-api` (task management)

### Styling System

- **Theme**: Material palette sourced from `common/colors.json` via `common/Colors.qml`
- **Config**: Design tokens in `common/Config.qml` (singleton), re-exported via per-project `Config.qml`
  - Fonts: `fontFamily: "Google Sans"`, `iconFontFamily: "JetBrainsMono NFP"`
  - Spacing/motion: `Config.space.*`, `Config.motion.duration.*`, `Config.shape.corner.*`
  - Colors: `Config.color` and `Config.palette` (from `common/Colors.qml`)
  - Typography: `Config.type.*` defines Material type scale (display/headline/title/body/label)
- **Layering**: Bar uses `WlrLayershell.layer: WlrLayer.Background`; powermenu uses `Overlay` + `Exclusive` keyboard focus

### File Locations

- **Managed config**: `/home/magni/.local/share/dotbak/managed/config/quickshell/`
- **Alternative config**: `/home/magni/.config/quickshell/` (both paths available)

## Coding Conventions

**QML/JS Style:**
- 2-space indentation
- Concise arrow functions/inline handlers
- Keep signal handlers readable and scoped
- Avoid deprecated Quickshell APIs:
  - Use `Quickshell.shellDir`/`Quickshell.shellPath()` NOT `configDir`/`configPath`
  - Use explicit `function(args)` handlers instead of parameter injection

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
- Long-running monitors (nmcli, swaync-client, udevadm, busctl) use exponential backoff restart
- Pattern: `monitorRestartAttempts`, `monitorRestartTimer`, `monitorBackoffResetTimer`
- Backoff: 1s → 2s → 4s → ... → 30s max, resets after 60s stability
- Set `monitorDegraded: true` on crash for optional UI indicator

**CommandRunner:**
- Supports `timeoutMs`, `onError(errorOutput, exitCode)`, `onTimeout()` signals
- Stderr captured in `errorOutput` property
- Triggers immediately when enabled (no initial interval wait)

## UI/UX Principles

- **Catppuccin-inspired, intentional layouts**: No default system fonts; use explicit `Config` families
- **Color semantics**: Use `Config.color.*` roles (primary/secondary/error/success)
- **Animations**: Meaningful transitions only (open/close reveals, tooltip fades); avoid noisy micro-motions
  - Always gate animations with visibility checks. Hidden components with `running: true` animations burn idle CPU.
- **Tooltips**: Anchor above targets, stay unclipped; modules can collapse when empty
- **Powermenu**: Animates cleanly, retains focus on open, hides on `Esc`/`q`, quits on dismiss

## Testing

**No automated tests.** Manual verification required:

- Powermenu: `Esc`/`q` close and quit; buttons execute correct actions
- Bar modules: Layout stable on reload; tooltips anchor correctly; tray right-click menus work
- Network tooltip: Shows USB NIC model + USB icon when subsystem is `usb`; polling only while tooltip is open
- Overlay animations: Clean reveals, correct focus behavior
- **Performance**: Idle CPU should be ~0% with hidden overlays (check with `pidstat`). If high idle CPU, look for unconditional animations.

## Dependencies

- **Runtime**: `quickshell`, `hyprland`, `grim`, `imagemagick`, `wl-clipboard`, `swaync`, `nmcli`, `systemctl`, `pipewire` (`pw-dump`), `brillo`, `udevadm`
- **Build**: `cargo` (for Rust scripts), Qt6 QML modules

## Known Issues

- HyprQuickshot: High-resolution monitors may cause grim delays; selecting options before save completes can lose screenshots

## Commit & PR Guidelines

- Commits: short imperative subject (e.g., `Add powermenu action`, `Tighten esc shortcut`); group related edits.
- PRs: describe behavior changes, mention manual checks performed, and include screenshots/gifs for UI tweaks.

## Security & Configuration Notes

- System actions use `systemctl`/`loginctl`; avoid expanding action lists without reviewing permissions.
- `WlrLayershell` uses `Overlay` + `Exclusive` keyboard focus; confirm compositor compatibility when adjusting focus settings.

## Performance Notes

- Animations in hidden windows (`visible: false`) still consume CPU if `running: true`
- Always gate animation `running` property with window visibility checks
- Example fix: `running: root.QsWindow.window && root.QsWindow.window.visible`
- To measure idle CPU after reload: `pid=$(pgrep -n quickshell); sleep 20; pidstat -p "$pid" 1 5 | awk '/Average:/{print $8}'`
