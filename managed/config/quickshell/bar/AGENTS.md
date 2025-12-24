# Repository Guidelines

## Project Structure & Module Organization
- Entry point: `shell.qml` loads `BarWindow.qml` per screen.
- Core UI pieces:
  - `components/` (shared building blocks like `ModuleContainer.qml`, `TooltipPopup.qml`).
  - `components/JsonUtils.js` (shared safe JSON parsing helpers for module output).
  - `components/IconTextRow.qml` (shared icon + label row used by multiple modules).
  - `modules/` (bar modules such as `ClockModule.qml`, `WorkspaceGroup.qml`).
- Styling/config: `Config.qml`, `Colors.js`, `ColorPalette.qml` (Catppuccin palette).
- Waybar reference config: `waybar/config.jsonc`, `waybar/style.css` (used as design source).
- No tests or assets beyond the above; add new QML files under the most relevant folder.
- Runtime data sources/services:
  - `modules/BacklightModule.qml` reads `/sys/class/backlight/<device>/actual_brightness`/`max_brightness` and uses `udevadm monitor` to trigger refresh.
  - `modules/MprisModule.qml` uses `Quickshell.Services.Mpris` (ignore `playerctld`).
  - `modules/NotificationModule.qml` consumes `swaync-client -swb`.
  - `modules/SystemdFailedModule.qml` polls `systemctl --failed` and uses `busctl monitor` for events.
  - `modules/TrayModule.qml` uses `Quickshell.Services.SystemTray` (right-click opens menu).
  - `modules/ArchIconModule.qml` runs `waybar/scripts/status.sh` on tooltip hover for Google Tasks.
  - `modules/UpdatesModule.qml` streams `waybar-module-pacman-updates` JSON output.
  - `modules/PrivacyModule.qml` uses `pw-dump -m --no-colors` as an event trigger and runs `pw-dump --no-colors` to parse mic/screen streams; camera status is derived from `fuser /dev/video*` on udev video4linux events.

## Build, Test, and Development Commands
- Run the bar locally: `quickshell -c bar` (or `qs` from this directory).
- IPC controls:
  - `quickshell ipc call powermenu toggle|show|hide`
- Manual reload: restart `quickshell` after QML changes.
- No automated build/test commands are defined.

## Coding Style & Naming Conventions
- QML/JS: 2-space indentation, concise handlers, readable signal scopes.
- Naming:
  - QML types/IDs: `CamelCase` (e.g., `WorkspaceGroup`).
  - Properties/functions: `lowerCamelCase`.
  - Constants: `UPPER_SNAKE`.
- Keep powermenu-specific names explicit (e.g., `powermenuVisible`).
- Prefer small, focused components; shared colors live in `Colors.js`.
- Use `Quickshell.shellDir`/`Quickshell.shellPath()` (avoid deprecated `configDir`/`configPath`).
- Avoid deprecated parameter injection in signal handlers; use `function(args)` handlers instead.

## Testing Guidelines
- No automated tests. Manually verify:
  - `Esc`/`q` close the powermenu.
  - IPC calls work (`quickshell ipc call powermenu toggle`).
  - Buttons trigger expected system actions.
  - Overlay animation and focus behavior are correct.
  - Tooltips anchor above their target and remain unclipped at screen edges.
  - Tray right-click menus open as expected.

## Commit & Pull Request Guidelines
- Commits: short, imperative subjects (e.g., `Tighten esc shortcut`).
- PRs: describe behavior changes, list manual checks, add screenshots/GIFs for UI changes.

## Security & Configuration Notes
- System actions use `systemctl`/`loginctl`; review permissions before expanding actions.
- `WlrLayershell` uses Overlay + Exclusive keyboard focus; validate compositor compatibility when adjusting focus.
