# Repository Guidelines

## Project Structure & Module Organization
- Root contains eww config for the powermenu only. Key paths:
  - `windows/` — Yuck views (currently `powermenu.yuck`).
  - `animations.scss`, `colors.scss`, `eww.scss` — shared styling and globals.
  - `scripts/` — helper scripts (`manage`, `do-powermenu-action`).
  - `powermenu.sh` — entry point to open the powermenu.
- No tests or assets directories are present; keep additions minimal and powermenu-focused.

## Run, Build, and Development Commands
- Start eww if not already running: `eww daemon`.
- Open the powermenu: `./powermenu.sh` (uses `scripts/manage show powermenu`).
- Toggle from the helper directly: `scripts/manage toggle powermenu`.
- Reload styling/layout after edits: `eww reload`.
- Apply a power action once selected: `scripts/do-powermenu-action poweroff|reboot|suspend|hibernate|exit|lock`.

## Coding Style & Naming Conventions
- Indentation: two spaces in Yuck and SCSS; avoid tabs.
- Keep names explicit and powermenu-scoped (e.g., `powermenu-visible`, `powermenu-button-selected`).
- SCSS: prefer variables from `colors.scss`; avoid hard-coded colors when possible.
- Bash: `set -euo pipefail` for new scripts; use lowercase function names with hyphen-free commands.

## Testing Guidelines
- No automated test suite. Validate manually:
  - Run `eww reload` and `./powermenu.sh` to confirm the menu opens, animates, and closes cleanly.
  - Click each action; ensure `do-powermenu-action` receives the expected selection and hides the menu where appropriate.
- If adding behavior, note manual steps in your PR.

## Commit & Pull Request Guidelines
- Use clear, imperative commit messages (e.g., `Simplify powermenu toggler`).
- For PRs, include: purpose, key changes, manual verification steps (commands run), and screenshots/gifs only if UI changes materially.
- Keep scope narrow and avoid reintroducing removed widgets or unused scaffolding.

## Security & Configuration Tips
- Power actions call `systemctl`/`loginctl`; avoid running scripts as root. Keep paths within this repo or `~/.config/eww`.
- Prefer environment overrides via `EWW` (see `scripts/manage`) rather than hardcoding binary paths.
