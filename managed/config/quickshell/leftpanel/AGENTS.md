@../AGENTS.md

# left-panel

## Overview

This is a Quickshell panel for Hyprland/Wayland that provides an AI chat interface with local/OpenAI/Gemini provider support, MCP tools, chat history/resume, and a metrics view. It runs as a left-side panel overlay.

## Running

The panel is loaded by the root shell automatically. To test changes, reload the main shell:

```bash
bash tools/reload-quickshell.sh
```

## Architecture

### Entry Point

- Root `shell.qml` - Creates the left `PanelWindow`, focus grab, and slide animation, then loads `LeftPanel.qml`

### Main Component

- `LeftPanel.qml` - Core panel logic containing:
  - Multi-provider AI chat backed by `qsnative.AiChatSession`
  - Code-defined local MCP tools backed by `AiChatSession.mcp_*`
  - Chat history restore and `/resume` picker backed by qs-native `internal/chatstore`
  - Mood system with configurable system prompts
  - Slash commands (`/model`, `/mood`, `/resume`, `/clear`, `/help`, `/status`, `/mcp`)
  - Tab navigation between Chat and Metrics views

### Components (`./components/`)

- `ChatView.qml` - Message list with copy-all functionality
- `ChatMessage.qml` - Individual message bubbles with copy button
- `ChatComposer.qml` - Input field with command detection
- `CommandPicker.qml` - Modal picker for models, moods, and resumable chats
- `MessageCodeBlock.qml`, `MessageMathBlock.qml`, `ToolCallRow.qml` - Rich message rendering helpers
- `NavPill.qml` - Tab navigation with connection status
- `MetricsView.qml`, `StatCard.qml`, `CircularGauge.qml` - System metrics display

### Configuration

- `./common/` - Symlink to `../common/` containing shared config
- `Common.Config` - Singleton with design tokens, spacing, typography
- `Common.Config.color` / `Common.Config.palette` - Material color roles and palette

### Data Files

- `./config.json` - Mood configurations with optional `default_model`
- `./models.json` - Model picker entries, including recommended local/OpenAI/Gemini choices
- `./config.example.toml` - Tracked shape for ignored local `config.toml`
- `./assets/` - Provider logos

## Key Patterns

### Adding Models

Add entries to `./models.json`. `services/ModelConfig.qml` reads the file and exposes typed picker options with canonical `provider/model` values.

Each entry should include `raw_id`, `label`, `description`, and `recommended`. Provider support and priority are resolved by qsnative. Optional `capabilities` can override the default image/tool/multimodal flags.

### Adding Moods

Add to `./config.json`:

```json
{ "name": "Name", "subtext": "Description", "icon": "\uf123", "default_model": "optional-model-id", "prompt": "System prompt..." }
```

### Provider Detection

Model ids are canonical `provider/model`, for example `local/gpt-5.4-mini`, `openai/gpt-5.5`, or `gemini/gemini-3.5-flash`.

Provider routing happens inside the `qs-native` provider registry, not in left-panel QML. Switching models still clears chat history.

The panel should treat provider config and catalog data as native QML objects/lists. Do not reintroduce JSON-string parsing for:

- provider config
- model config
- command lists
- attachments
- tool calls
- per-message metrics
- resume conversation options

The MCP runtime exposes only code-defined local servers:

- `builtin` / `Leftpanel Built-ins`: `shell_command`
- `email` / `Email Accounts`: `email_accounts`, `email_search`, `email_read`

Email metadata is read from ignored local TOML at `leftpanel/config.toml`; use `leftpanel/config.example.toml` for the tracked shape. Gmail OAuth tokens are read from Secret Service via qs-native `internal/secrets`, not from QML. The default email MCP surface is read-only; send is not advertised and direct `email_send` calls return a disabled error.

### Config And Secrets

- Secret Service service name: `quickshell`.
- Secret keys: `OPENAI_API_KEY`, `GEMINI_API_KEY`, optional `LOCAL_API_KEY`, `TODOIST_API_TOKEN`, `SP_DC`, shared Google OAuth keys `GOOGLE_<ID>_TOKEN_JSON` / `GOOGLE_<ID>_CLIENT_JSON`, and `EMAIL_<ID>_PASSWORD` only for non-Gmail IMAP accounts.
- TOML config: `leftpanel/config.toml` stores non-secret model/provider/email metadata.
- Gmail email accounts only need `provider = "gmail"` plus identity fields; qs-native defaults IMAP to `imap.gmail.com:993` with TLS.

`EnvLoader.qml` reads values through qs-native `ConfigResolver`, normalizes the default model to canonical `provider/model` form, and builds the typed `providerConfig` map consumed by `AiChatSession` and `ModelConfig.qml`. Do not parse local config or Secret Service directly in QML.

## Styling

Use Material tokens from `Common.Config.color`:

- Colors: `primary`, `surface`, `surface_dim`, `error`, `secondary`, `tertiary`
- Spacing: `Common.Config.space.{xs,sm,md,lg,xl}`
- Typography: `Common.Config.type.{bodySmall,bodyMedium,bodyLarge}.*`
- Corners: `Common.Config.shape.corner.{sm,md,lg,xl}`

Icons use Nerd Fonts via `Common.Config.iconFontFamily`.
