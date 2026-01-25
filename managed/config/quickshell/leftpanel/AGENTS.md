@../AGENTS.md

# left-panel

## Overview

This is a Quickshell panel for Hyprland/Wayland that provides an AI chat interface with multi-provider support (OpenAI and Gemini) and a metrics view. It runs as a left-side panel overlay.

## Running

The panel is loaded by Quickshell automatically. To test changes, reload quickshell or restart it:
```bash
quickshell
```

## Architecture

### Entry Point
- `shell.qml` - Creates a `PanelWindow` anchored to the left edge using WlrLayershell

### Main Component
- `LeftPanel.qml` - Core panel logic containing:
  - Multi-provider AI chat (OpenAI/Gemini) using curl via `Process`
  - Mood system with configurable system prompts
  - Slash commands (`/model`, `/mood`, `/clear`, `/help`, `/status`)
  - Tab navigation between Chat and Metrics views

### Components (`./components/`)
- `ChatView.qml` - Message list with copy-all functionality
- `ChatMessage.qml` - Individual message bubbles with copy button
- `ChatComposer.qml` - Input field with command detection
- `CommandPicker.qml` - Modal picker for models/moods with accent colors
- `NavPill.qml` - Tab navigation with connection status
- `MetricsView.qml`, `StatCard.qml`, `CircularGauge.qml` - System metrics display

### Configuration
- `./common/` - Symlink to `../common/` containing shared config
- `Common.Config` - Singleton with design tokens, spacing, typography
- `Common.Config.color` / `Common.Config.palette` - Material color roles and palette

### Data Files
- `./system-prompts/moods.json` - Mood configurations with optional `default_model`
- `./assets/` - Provider logos (SVG for OpenAI, PNG for Gemini)

## Key Patterns

### Adding Models
Add to `availableModels` in `LeftPanel.qml`:
```qml
{ value: "model-id", label: "Display Name", iconImage: "./assets/icon.svg", description: "...", accent: Common.Config.color.primary }
```

### Adding Moods
Add to `./system-prompts/moods.json`:
```json
{ "name": "Name", "subtext": "Description", "icon": "\uf123", "default_model": "optional-model-id", "prompt": "System prompt..." }
```

### Provider Detection
Models starting with `gemini` use Gemini API, others use OpenAI. Switching models clears chat history.

### Environment Variables
- `OPENAI_API_KEY` - OpenAI API key
- `GEMINI_API_KEY` - Gemini API key
- `OPENAI_MODEL` - Default model (defaults to `gpt-4o-mini`)

## Styling

Use Material tokens from `Common.Config.color`:
- Colors: `primary`, `surface`, `surface_dim`, `error`, `secondary`, `tertiary`
- Spacing: `Common.Config.space.{xs,sm,md,lg,xl}`
- Typography: `Common.Config.type.{bodySmall,bodyMedium,bodyLarge}.*`
- Corners: `Common.Config.shape.corner.{sm,md,lg,xl}`

Icons use Nerd Fonts via `Common.Config.iconFontFamily`.
