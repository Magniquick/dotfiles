# Repository Guidelines

## Project Structure & Module Organization
- Entry point: `shell.qml` loads `BarWindow.qml` per screen; powermenu lives under `powermenu/` with `shell.qml` → `Powermenu.qml`.
- Core UI pieces:
  - `components/` (shared building blocks like `ModuleContainer.qml`, `TooltipPopup.qml`, `IconTextRow.qml`, `JsonUtils.js`).
  - `modules/` (bar modules such as `ClockModule.qml`, `WorkspaceGroup.qml`, `NetworkModule.qml`).
  - Powermenu pieces: `powermenu/Powermenu.qml` plus `ActionPanel.qml`, `GreetingPane.qml`, `FooterStatus.qml`, `BunnyBlock.qml`, `ActionGrid.qml`, `PowermenuButton.qml`.
- Basic file layout (top-level):
  - `shell.qml`, `BarWindow.qml`, `Config.qml`, `Colors.js`, `ColorPalette.qml`
  - `components/`, `modules/`, `powermenu/`
  - `waybar/config.jsonc`, `waybar/style.css`
- Styling/config: `Config.qml`, `Colors.js`, `ColorPalette.qml` (Catppuccin palette). Waybar reference: `waybar/config.jsonc`, `waybar/style.css`.
- Runtime data sources/services:
  - Backlight: `/sys/class/backlight/<device>/actual_brightness` + `udevadm monitor`.
  - MPRIS via `Quickshell.Services.Mpris` (ignore `playerctld`).
  - Notifications: `swaync-client -swb`.
  - Systemd failed units: `systemctl --failed` plus `busctl monitor`.
  - Tray: `Quickshell.Services.SystemTray` (right-click opens menu).
  - Arch icon: `waybar/scripts/status.sh` on tooltip hover.
  - Updates: `waybar-module-pacman-updates` JSON stream.
  - Privacy: `pw-dump` + `fuser /dev/video*` for camera on udev video4linux.
  - Network: `nmcli` status/wifi; wired uses `/sys/class/net/<dev>/device/subsystem` to detect USB and `udevadm info` for a human-friendly USB NIC label (underscores → spaces).

## UI / Design Notes
- Catppuccin-inspired, but aim for intentional, bold layouts; avoid default system fonts—set explicit families in `Config`.
- Use clear color direction (no purple-by-default bias); prefer gradients/patterns over flat fills when adding backgrounds.
- Keep animations meaningful (open/close reveals, tooltip fades); avoid noisy micro-motions.
- Tooltips anchor above targets, stay unclipped; bar modules can collapse when empty.
- Powermenu overlay should animate cleanly, retain focus when opened, and hide on `Esc`/`q`.
- Use `Config.m3` colors where possible so modules stay aligned with the shared palette.

## Build, Test, and Development Commands
- Run bar locally: `quickshell -c bar` (or `qs` here). Powermenu: `quickshell` (or `qs`) from repo root to load `powermenu/shell.qml`.
- IPC controls: `quickshell ipc call powermenu toggle|show|hide`.
- Manual reload: restart `quickshell` after QML changes. No automated tests.

## Coding Style & Naming Conventions
- QML/JS: 2-space indentation, concise handlers, readable signal scopes.
- Naming: QML types/IDs `CamelCase`; properties/functions `lowerCamelCase`; constants `UPPER_SNAKE`.
- Keep powermenu names explicit (e.g., `powermenuVisible`); prefer small, focused components.
- Shared colors live in `Colors.js`; use `Quickshell.shellDir`/`Quickshell.shellPath()` (not deprecated `configDir`/`configPath`).
- Avoid deprecated parameter injection in signal handlers; use `function(args)` handlers.

## Testing Guidelines
- Manual checks:
  - `Esc`/`q` close powermenu; IPC toggle works.
  - Buttons trigger expected system actions.
  - Overlay animation/focus are correct; tray right-click menus open.
  - Tooltips anchor above targets, stay unclipped; bar reload keeps module layout.
  - Network tooltip shows USB NIC model + USB icon when subsystem is `usb`; polling resumes only while tooltip is open.

## Commit & Pull Request Guidelines
- Commits: short, imperative subjects (e.g., `Tighten esc shortcut`).
- PRs: describe behavior changes, list manual checks, add screenshots/GIFs for UI changes.

## Security & Configuration Notes
- System actions use `systemctl`/`loginctl`; review permissions before expanding actions.
- `WlrLayershell` uses Overlay + Exclusive keyboard focus; validate compositor compatibility when adjusting focus.
