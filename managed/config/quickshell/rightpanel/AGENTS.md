# Repository Guidelines

## Project Structure & Module Organization
This repo is a Quickshell (Qt/QML) configuration. Key entry points:
- `shell.qml`: root shell (bar per screen + clock)
- `bar/`: main bar (`bar/shell.qml`, `bar/BarWindow.qml`)
- `powermenu/`: overlay system actions
- `hyprquickshot/`: screenshot tool
- `rightpanel/`: right-side notification panel UI
- `common/`, `bar/components/`, `bar/modules/`: shared tokens, UI primitives, and feature modules

Rust helpers live under `bar/scripts/src/` (e.g., `ical-cache`, `todoist-api`). There are no automated tests.

## Build, Test, and Development Commands
- `quickshell` (or `qs`): run the main shell from repo root
- `quickshell -c bar`: run bar only
- `quickshell -c powermenu`: run powermenu only
- `quickshell -c hyprquickshot -n`: run screenshot tool (no duplicates)
- `cd bar/scripts/src/ical-cache && cargo build --release`: build calendar helper
- `cd bar/scripts/src/todoist-api && cargo build --release`: build todo helper

QML changes require a restart of `quickshell` (no hot reload).

## Coding Style & Naming Conventions
- QML/JS: 2-space indentation
- Types/IDs: `CamelCase` (e.g., `ModuleContainer`, `root`)
- Properties/functions: `lowerCamelCase`
- Constants: `UPPER_SNAKE`
- Avoid deprecated APIs (`Quickshell.shellDir`/`Quickshell.shellPath()` instead of `configDir/configPath`)

Use `common/Config.qml` (`Config.color` / `Config.palette`) for tokens and palette. Keep modules small and self-contained.

## Testing Guidelines
No automated tests. Manually verify:
- powermenu: `Esc`/`q` closes, actions work
- bar modules: layout stable, tooltips anchor correctly
- notification panel: dismiss, actions, inline reply, and images work
- performance: idle CPU ~0% with hidden overlays

## Commit & Pull Request Guidelines
- Commits: short imperative subject (e.g., "Add powermenu action")
- PRs: describe behavior changes, list manual checks, include screenshots/gifs for UI changes

## Security & Configuration Tips
System actions use `systemctl`/`loginctl`. Review permissions before adding actions. Keep animations gated by visibility to avoid idle CPU usage.
