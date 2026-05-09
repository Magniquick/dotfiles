# common

## Overview

Shared Quickshell theme/config primitives and utilities used across modules.

## Key Files

- `Config.qml`: Design tokens and color roles (from `Colors.qml`).
- `Colors.qml`: Matugen-driven colors + palettes via `JsonAdapter`.
- `archived/Colors.js`: Legacy static palette kept only for reference.
- `archived/mocha*.json`: Old Catppuccin/Machado palette experiments kept only for reference.
- `colors.json.template`: Matugen template for generating `colors.json`.
- `types/`: Type scale, spacing, motion, shapes.
- `services/DependencyCheck.qml`: Dependency verification helper.
- `GlobalState.qml`: Shared runtime state.

## Matugen Workflow

- Template: `colors.json.template`
- Output location: `common/colors.json` beside `Colors.qml`; `Colors.qml` loads it with `Qt.resolvedUrl("colors.json")` and watches for changes.
- Reload quickshell after generating new colors.

## Conventions

- Use 2-space indentation.
- Prefer `Common.Config` tokens for colors, spacing, motion, and typography.
- Keep config/type singletons side-effect-light; isolate mutable runtime state in `GlobalState.qml` or explicit service singletons.
