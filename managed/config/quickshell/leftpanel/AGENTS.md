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
  - Multi-provider AI chat backed by `qsgo.AiChatSession` / `qsgo.AiModelCatalog`
  - MCP-backed tool/prompt/resource runtime backed by `AiChatSession.mcp_*`
  - Mood system with configurable system prompts
  - Slash commands (`/model`, `/mood`, `/clear`, `/help`, `/status`, `/mcp`, `/mcp add`)
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
- `./mcp_servers.json` - MCP HTTP server definitions consumed by `services/McpConfig.qml`
- `./assets/` - Provider logos (SVG for OpenAI, PNG for Gemini)

## Key Patterns

### Adding Models

The model list is provided by `qsgo.AiModelCatalog` and exposed to QML as typed provider entries through the `providers` property.

Catalog shape:

- `providers`: provider-grouped entries with `id`, `label`, `enabled`, `recommended_models`, and `models`
- each model includes canonical `id` in `provider/model` form, raw provider model id, description, recommendation flag, and structured `capabilities`

Fallback/recommended models are provider-defined in the `qs-go` AI backend, not in left-panel QML.

### Adding Moods

Add to `./system-prompts/moods.json`:

```json
{ "name": "Name", "subtext": "Description", "icon": "\uf123", "default_model": "optional-model-id", "prompt": "System prompt..." }
```

### Provider Detection

Model ids are canonical `provider/model`, for example `openai/gpt-4o` or `gemini/gemini-2.5-flash`.

Provider routing happens inside the `qs-go` provider registry, not in left-panel QML. Switching models still clears chat history.

The panel should treat provider config and catalog data as native QML objects/lists. Do not reintroduce JSON-string parsing for:

- provider config
- MCP server config
- model catalogs
- command lists
- attachments
- per-message metrics

`McpConfig.qml` loads `mcp_servers.json` as a typed list and passes it into `AiChatSession.mcp_config`. The session then exposes typed `mcp_servers`, `mcp_tools`, `mcp_prompts`, `mcp_resources`, `mcp_status`, and `mcp_error` properties for the rest of the panel.

`/mcp add` opens an in-panel wizard that appends a minimal server entry to `mcp_servers.json`, generates a unique `id`, and refreshes the live MCP runtime. The wizard only captures URL and optional label; auth and headers remain manual JSON edits.

### Environment Variables

- `OPENAI_API_KEY` - OpenAI API key
- `OPENAI_BASE_URL` - Optional OpenAI-compatible base URL override
- `GEMINI_API_KEY` - Gemini API key
- `OPENAI_MODEL` - Default model; may be raw legacy id or canonical `provider/model`

`EnvLoader.qml` normalizes the default model to canonical `provider/model` form and builds the typed `providerConfig` map consumed by `AiChatSession` and `AiModelCatalog`.

### MCP Server Definitions

`leftpanel/mcp_servers.json` is an array of objects with:

- `id`
- `label`
- `url`
- `enabled`
- `auto_connect`
- `bearer_token`
- `headers`

## Styling

Use Material tokens from `Common.Config.color`:

- Colors: `primary`, `surface`, `surface_dim`, `error`, `secondary`, `tertiary`
- Spacing: `Common.Config.space.{xs,sm,md,lg,xl}`
- Typography: `Common.Config.type.{bodySmall,bodyMedium,bodyLarge}.*`
- Corners: `Common.Config.shape.corner.{sm,md,lg,xl}`

Icons use Nerd Fonts via `Common.Config.iconFontFamily`.
