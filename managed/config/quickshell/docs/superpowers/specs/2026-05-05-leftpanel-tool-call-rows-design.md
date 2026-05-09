# Leftpanel Tool Call Rows Design

Date: 2026-05-05

## Goal

Expose AI tool calls in the leftpanel chat UI as separate live timeline rows, similar to ChatGPT, Claude, and Codex-style tool activity. Rows should make agent work visible without adding model-token cost.

The chosen design is option A from the reviewed alternatives: live tool-event rows.

## Decisions

- Tool calls appear as separate timeline rows between assistant messages.
- Rows are inserted live when the backend receives a tool call, then updated when the result arrives.
- Collapsed summaries are generated locally from structured tool data, not by asking the model.
- Expanded rows show cleaned details first.
- Raw input/result payloads are available behind a secondary raw toggle.
- Failed calls stay inline as error-colored rows only; assistant message headers do not get warning markers.
- Backend owns summary/detail generation. QML renders prepared fields and handles expansion state.

## User Experience

During a turn, the transcript should look like this:

1. Assistant streams normal text.
2. A row appears: `running shell_exec...`
3. The tool finishes.
4. The same row updates to `ran go test ./...`, `exit 0 · no stdout`
5. If `apply_patch` ran, the row updates to `edited ChatMessage.qml +34 -2`
6. Assistant continues or finishes the response.

Each row is collapsed by default. Clicking the row expands a cleaned detail view.

For `apply_patch`, details include:

- Changed files
- Per-file additions/deletions when available
- Patch excerpt or operation summary
- Raw freeform patch payload behind a raw toggle

For `shell_exec`, details include:

- Command
- Working directory/workspace label
- Exit code
- Stdout and stderr, using `(no output)` when empty
- Timeout/truncation state when relevant
- Raw structured call/result behind a raw toggle

For generic MCP tools, details include:

- Tool name
- Cleaned arguments when recognized
- Cleaned result text/data when recognized
- Raw arguments/result as the fallback

## Data Model

The chat model should support a visible item kind for tool rows, separate from normal user/assistant/info messages.

Suggested fields:

- `kind`: `message` or `tool`
- `messageId`: stable row id
- `sender`: existing message sender for normal messages; tool rows can use `tool`
- `toolCallId`: provider/tool-call id
- `toolName`: canonical tool name, such as `shell_exec` or `apply_patch`
- `toolStatus`: `running`, `success`, or `error`
- `toolSummary`: collapsed primary label
- `toolSubtitle`: collapsed secondary label
- `toolIcon`: semantic icon key or short glyph key
- `toolIsError`: boolean
- `toolDetailSections`: prepared cleaned detail sections
- `toolRawInput`: raw arguments/freeform payload
- `toolRawResult`: raw result payload

QML should not parse provider-specific payloads. It may format already-prepared sections and apply local visual treatment.

## Backend Events

The AI backend should emit explicit tool lifecycle events into the QML bridge:

- `tool_start`: create a row with `running` status.
- `tool_done`: update the existing row to `success`.
- `tool_error`: update the existing row to `error`.

The event should include enough data to render a useful row immediately:

- `toolCallId`
- `toolName`
- status
- locally generated summary/subtitle
- cleaned detail sections
- raw input and raw result when available

The agent history can keep provider/tool messages as it does today. UI events are a presentation stream and should not require extra prompt content.

## Summary Generation

Backend summary generation should be deterministic and local.

`apply_patch`:

- Parse the freeform patch input before or after execution.
- Count additions and deletions per file where possible.
- Prefer summaries like `edited leftpanel/components/ChatMessage.qml +34 -2`.
- If multiple files changed, use `edited 3 files +58 -11` and show the file list expanded.
- If parsing fails, fall back to `ran apply_patch`.

`shell_exec`:

- Use structured call arguments for command/cwd.
- Summaries should be direct: `ran go test ./...`.
- Subtitles should use result state: `exit 0 · no stdout`, `exit 1 · stderr`, `timed out`, or `output truncated`.

Generic MCP:

- Use `called <toolName>` while running.
- On success use `called <toolName>`.
- On failure use `failed <toolName>`.
- Show recognized text/data in cleaned sections and raw data as fallback.

## QML UI

Add a dedicated tool-row component, for example `leftpanel/components/ToolCallRow.qml`, rather than growing `ChatMessage.qml` too much.

The chat delegate can branch by row kind:

- normal message rows continue through `ChatMessage`
- tool rows use `ToolCallRow`

Visual behavior:

- Collapsed by default.
- Click toggles expansion.
- Expanded panel shows cleaned detail sections first.
- Raw toggle appears inside expanded state.
- Error rows use Material error roles.
- Running rows use a subtle progress/loading treatment, gated by visibility.

Use existing Material role tokens from `Config.color.*`. Keep the row visually quieter than assistant content, but strong enough to scan.

## Non-Goals

- No assistant-level warning markers for tool failures.
- No model-generated tool summaries.
- No full trace drawer in the first implementation.
- No hidden debug event tree unless a later debugging feature asks for it.
- No extra provider-specific UI in QML beyond prepared generic fields.

## Acceptance Checks

- A live shell call creates a visible `running shell_exec...` row before completion.
- The same shell row updates to success/error with command and output details.
- An `apply_patch` call shows changed file summary with additions/deletions when parseable.
- Expanding rows shows cleaned details first.
- Raw input/result can be opened from the expanded row.
- Failed tools render inline as error rows without assistant-header markers.
- No additional model request is made to summarize tool calls.
- Existing user/assistant message rendering still works.
