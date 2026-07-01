@../AGENTS.md

# Repository Guidelines

## Project Structure & Module Organization

- Main component: `HyprQuickshot.qml` orchestrates UI state, selectors, and screenshot logic. It is loaded by the root `shell.qml`.
- Components: `src/` holds reusable QML (e.g., `FreezeScreen.qml`, `RegionSelector.qml`, `WindowSelector.qml`).
- Assets: `icons/` for SVG glyphs, `shaders/` for dimming/overlay effects, `common/Config.qml` for theming.

## Build, Test, and Development Commands

- Run locally: start the main shell with `./qs`, then trigger HyprQuickshot via your keybind or `qs ipc call hyprquickshot open`.
- Native capture support lives in `common/modules/qs-capture`; build it with `bash tools/build-qs-capture.sh` before running the shell after native-module changes.
- No automated test suite is currently defined.

## Coding Style & Naming Conventions

- QML/JS: 4-space indentation, descriptive `id` values (e.g., `recordButton`, `windowSelector`).
- Colors: use `Common.Config.color` / `Common.Config.palette` and `applyAlpha` helpers; avoid hardcoded hex unless matching existing palette.
- Animations: prefer `Behavior` with `NumberAnimation`/`ColorAnimation` for smooth state changes.
- Files: keep components small and focused; place shared widgets in `src/`.

## Testing Guidelines

- Manual testing only:
  - Launch the main shell, trigger HyprQuickshot, and verify mode switching (region/window/screen), screenshot save/copy, and recording badge interactions.
  - Check keyboard/mouse passthrough in recording state.
- No coverage targets or automated runners are present.

## Commit & Pull Request Guidelines

- Commits: concise present-tense summaries (e.g., “Add screen record confirmation click”). Group related changes.
- PRs: include a short description, rationale, testing notes (manual steps), and visuals if UI changes. Link issues when applicable.
- Avoid reformat-only diffs; keep changes scoped to the described feature/fix.

## Security & Configuration Tips

- Quickshell depends on Wayland; ensure `/run/user/$UID` paths are writable or expect log/IPC warnings.
- `wl-copy` must be present in `PATH` for clipboard copy mode; screenshot capture itself now comes from the native `qs-capture` module.
- Watch `[freeze]` and `[window-targets]` logs when debugging frozen capture state or per-window cache failures.
- Do not commit user-specific paths or secrets; configuration is read via environment (`HQS_DIR`, `XDG_*`).
