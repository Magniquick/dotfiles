@../AGENTS.md

# Repository Guidelines

## Project Structure & Module Organization

- Entry point: root `shell.qml` loads `bar/BarWindow.qml` once per screen via `Variants`.
- `BarWindow.qml`: Top-layer Wayland bar with left/center/right rows.
- `components/`: Shared bar primitives such as `ModuleContainer.qml`, `TooltipPopup.qml`, `CommandRunner.qml`, `ProcessMonitor.qml`, `ActionChip.qml`, `ActionIconButton.qml`, `TrafficGraph.qml`, and tooltip helpers.
- `modules/`: User-facing bar modules and groups such as `StartMenuGroup`, `WorkspaceGroup`, `ControlsGroup`, `WirelessGroup`, `PanelGroup`, `MprisModule`, `NetworkModule`, `BluetoothModule`, `BatteryModule`, `ClockModule`, `UpdatesModule`, and `TrayModule`.
- `services/`: Bar-scoped singleton backends registered in `bar/qmldir` (`BrightnessService`, `CalendarService`, `NetworkService`, `PrivacyService`, `SystemdFailedService`, `TodoistService`, `UpdatesService`).

## Runtime Data Sources

- Audio: `Quickshell.Services.Pipewire` in `WireplumberModule`.
- Backlight: internal display through `qsgo.BacklightProvider`; external monitors through `ddcutil` in `BrightnessService`.
- Bluetooth: `Quickshell.Bluetooth`; optional debug-only `dbus-monitor`/`busctl`/`ps` helpers can inspect discovery holders and librepods tray metadata.
- Calendar: `qsgo.IcalCache` through `CalendarService`.
- Failed units: `qsgo.SystemdFailedProvider` snapshots structured `systemctl --output=json` and refreshes from systemd D-Bus events.
- MPRIS: `Quickshell.Services.Mpris`; lyrics come from `unifiedlyrics`.
- Network: `Quickshell.Networking`; `ip` is used only for address/gateway details and sysfs/device metadata fills ethernet labels.
- Privacy: `Quickshell.Services.Pipewire` for mic/screencast, `inotifywait`/`fuser`/`ps` for camera owners, and `wl-present toggle-freeze` for the privacy freeze control.
- Updates: `qsgo.PacmanUpdatesProvider` (`checkupdates`, `yay -Qua`).

## UI / Design Notes

- Use `Config.color`, `Config.palette`, `Config.space`, `Config.type`, `Config.motion`, and `Config.shape` tokens.
- Bar windows use `WlrLayershell.layer: WlrLayer.Top` and `WlrKeyboardFocus.None`.
- Tooltips should anchor above targets, stay unclipped, and only keep expensive polling/animations active while visible.
- Modules should collapse when empty rather than leaving dead space.
- Use `Config.fontFamily` and `Config.iconFontFamily`; do not fall back to default system fonts for visible UI.

## Build, Test, and Development Commands

- Run the full shell from repo root with `./qs`.
- Reload after QML changes with `bash tools/reload-quickshell.sh`; the happy path ends with no recent warnings/errors.
- No automated test suite is currently defined.

## Coding Style & Naming Conventions

- QML/JS: 2-space indentation, concise handlers, readable signal scopes.
- Naming: QML types/IDs `CamelCase`; properties/functions `lowerCamelCase`; constants `UPPER_SNAKE`.
- Shared colors live in `Config.color` / `Config.palette`; use `Quickshell.shellDir`/`Quickshell.shellPath()` instead of deprecated `configDir`/`configPath`.
- Avoid deprecated parameter injection in signal handlers; use explicit `function(args)` handlers.

## Error Handling Patterns

- **Dependency checking**: Use `DependencyCheck.require(cmd, module, callback)` for PATH commands and `DependencyCheck.requireExecutable(path, module, callback)` for scripts.
- **CommandRunner**: Supports `timeoutMs`, `onError(errorOutput, exitCode)`, `onTimeout()`, and `onRan(output)`. Treat `output` as last-successful data and parse in `onRan(output)`.
- **ProcessMonitor**: Use for long-running monitor commands that should restart with backoff. Gate monitors and timers when the owning UI is hidden if live monitoring is not required.

## Manual Checks

- `Esc` closes left/right panels and powermenu when those surfaces are open.
- Tooltips anchor correctly, remain unclipped, and stop hidden animations/timers.
- Network/Bluetooth/Privacy/Updates modules reflect live service state after `bash tools/reload-quickshell.sh`.
- Tray right-click menus open and notification/panel buttons still route through `GlobalState`.
