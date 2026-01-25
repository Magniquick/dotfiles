# common

## Overview

Shared Quickshell theme/config primitives and utilities used across modules.

## Key Files

- `Config.qml`: Design tokens and color roles (from `Colors.qml`).
- `Colors.qml`: Matugen-driven colors + palettes via `JsonAdapter`.
- `Colors.js`: Legacy static palette (kept for reference).
- `colors.json.template`: Matugen template for generating `colors.json`.
- `types/`: Type scale, spacing, motion, shapes.
- `services/DependencyCheck.qml`: Dependency verification helper.
- `GlobalState.qml`: Shared runtime state.

## Matugen Workflow

- Template: `colors.json.template`
- Output location: `Quickshell.dataPath("colors.json")`
- Reload quickshell after generating new colors.

## Conventions

- Use 2-space indentation.
- Prefer `Common.Config` tokens for colors, spacing, motion, and typography.
- Keep singletons stateless; no side effects outside explicit file I/O.
