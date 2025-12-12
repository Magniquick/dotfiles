# Repository Guidelines

## Project Structure & Modules
- Root QML entrypoints live at `shell.qml` (bar) and `Bar.qml`, with shared Catppuccin palette in `ColorPalette.qml` and `Colors.js`.
- Bar modules are under `modules/` (e.g., `WorkspaceButtons.qml`, `SystemTrayView.qml`, `MprisModule.qml`), and styling tokens are in `theme/Theme.qml`.
- Legacy Waybar reference files remain under `waybar/` for parity; do not edit them for Quickshell behavior.
- Powermenu lives outside this repo at `../powermenu/`; keep imports scoped to the bar unless explicitly coordinating with that config.

## Build, Run, and Development Commands
- Launch bar: `quickshell -c bar` from this directory to load `shell.qml`.
- Powermenu IPC: `quickshell ipc call powermenu toggle` (requires powermenu config running).
- Manual reload after QML edits: restart `quickshell` or re-run `quickshell -c bar`.
- Inspect logs: `tail -f /run/user/$UID/quickshell/by-id/*/log.qslog`.

## Coding Style & Naming Conventions
- QML/JS: 2-space indentation, concise inline handlers; prefer CamelCase for types/ids, lowerCamelCase for properties/functions, UPPER_SNAKE for constants.
- Keep powermenu-specific names explicit (`powermenuVisible`, `powermenuHover`), and reuse shared colors via `Theme.colors`.
- Favor small, focused components; share palette or theme data via the Theme singleton instead of duplicating literals.

## Testing Guidelines
- No automated tests are present; rely on manual verification:
  - `Esc`/`q` close powermenu overlays.
  - `quickshell ipc call powermenu toggle` opens/closes powermenu.
  - Bar modules: buttons trigger expected system actions, overlays animate cleanly, tray icons respond to clicks/menus.

## Commit & Pull Request Guidelines
- Commits: short imperative subjects (e.g., `Add powermenu IPC handler`, `Tighten esc shortcut`); group related edits.
- PRs: describe behavior changes, manual checks performed, and include screenshots/gifs for UI tweaks. Link related issues when applicable.

## Security & Configuration Notes
- System actions use `systemctl`/`loginctl`; review permissions before extending action lists.
- `WlrLayershell` uses overlay + exclusive keyboard focus—confirm compositor compatibility before changing focus settings.
- Avoid adding networked dependencies in bar modules; prefer system tools already in use (`nmcli`, `wpctl`, `swaync-client`, etc.).
