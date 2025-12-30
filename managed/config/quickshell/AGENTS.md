# Repository Guidelines

## Project Structure & Modules
- `powermenu/shell.qml`: Entry point; shows powermenu, handles shortcuts and actions.
- `powermenu/Powermenu.qml` + `ActionPanel.qml`, `GreetingPane.qml`, `FooterStatus.qml`, `BunnyBlock.qml`, `ActionGrid.qml`, `PowermenuButton.qml`: UI composition for the overlay.
- `powermenu/Colors.js`: Shared Catppuccin palette constants (singleton JS module).
- Assets and tests are not present; add new files under their relevant module directories.

## Build, Run, and Dev Commands
- Run shell: `quickshell` (or `qs`) from this directory to load `shell.qml`.
- Manual reload: restart `quickshell` after QML changes.

## Coding Style & Naming
- QML/JS: 2-space indentation, concise arrow/inline handlers. Keep signal handlers readable and scoped.
- Naming: CamelCase for QML types/ids, lowerCamelCase for properties/functions, UPPER_SNAKE for constants.
- Keep powermenu-specific names explicit (e.g., `powermenuVisible`, `powermenuHover`).
- Prefer small, focused components; keep shared colors in `Colors.js`.

## Testing & Verification
- No automated tests. Manually verify:
  - `Esc`/`q` close the powermenu.
  - Buttons execute correct system actions and hide appropriately.
  - Overlay animates/reveals cleanly and regains focus on open.
  - Powermenu quits when dismissed.

## Commit & PR Guidelines
- Commits: short imperative subject (e.g., `Add powermenu action`, `Tighten esc shortcut`); group related edits.
- PRs: describe behavior changes, mention manual checks performed, and include screenshots/gifs for UI tweaks. Link related issues if any.

## Security & Configuration Notes
- System actions use `systemctl`/`loginctl`; avoid expanding action lists without reviewing permissions.
- `WlrLayershell` uses `Overlay` + `Exclusive` keyboard focus; confirm compositor compatibility when adjusting focus settings.
