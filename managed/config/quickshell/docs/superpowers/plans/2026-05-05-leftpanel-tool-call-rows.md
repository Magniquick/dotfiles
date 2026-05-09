# Leftpanel Tool Call Rows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Render AI tool calls as separate live rows in the leftpanel chat timeline.

**Architecture:** The Go AI loop emits presentation-only tool lifecycle events over the existing stream callback using `done=2`. The C++ QML model stores tool rows with a `kind: "tool"` role and updates rows by `toolCallId`. QML branches the chat delegate between existing `ChatMessage` and a new `ToolCallRow`.

**Tech Stack:** Go AI backend, CGO C ABI, Qt/C++ `QAbstractListModel`, Quickshell QML.

---

### Task 1: Backend Tool Event Summaries

**Files:**
- Create: `common/modules/qs-go/internal/ai/tool_events_test.go`
- Modify: `common/modules/qs-go/internal/ai/chat.go`

- [x] Write failing tests for `buildToolStartEvent` and `buildToolDoneEvent`.
- [x] Run `go test ./internal/ai -run 'TestBuildTool.*Event' -count=1` from `common/modules/qs-go` and confirm the helpers are undefined.
- [x] Implement deterministic local summaries/details for `apply_patch`, `shell_exec`, and generic MCP tools.
- [x] Re-run the same tests and confirm they pass.

### Task 2: Stream Tool Lifecycle Events

**Files:**
- Modify: `common/modules/qs-go/internal/ai/chat.go`
- Modify: `common/modules/qs-go/cpp/qsgo_go_api.h`

- [x] Extend `streamWithTools` to emit `tool_start` before `CallTool`.
- [x] Emit `tool_done` or `tool_error` after `CallTool`.
- [x] Keep tool events presentation-only; do not add summaries to model history.
- [x] Use callback `done=2` for event JSON.

### Task 3: QML Model Tool Rows

**Files:**
- Modify: `common/modules/qs-go/cpp/QsGoAiSession.h`
- Modify: `common/modules/qs-go/cpp/QsGoAiSession.cpp`

- [x] Add a `tool` model role.
- [x] Parse `done=2` JSON events in `tokenCallback`.
- [x] Insert running tool rows on `tool_start`.
- [x] Update existing rows on `tool_done` and `tool_error`.
- [x] Exclude tool rows from chat history and copy-all text.

### Task 4: Tool Row UI

**Files:**
- Create: `leftpanel/components/ToolCallRow.qml`
- Modify: `leftpanel/components/ChatView.qml`

- [x] Add a dedicated expandable tool-call row component.
- [x] Render cleaned detail sections first.
- [x] Add a secondary raw payload toggle.
- [x] Branch the chat delegate by `kind`.
- [x] Keep existing user/assistant rendering unchanged.

### Task 5: Verification

**Files:**
- Modify as needed only for compilation fixes.

- [x] Run `go test ./... -count=1` in `common/modules/qs-go`.
- [x] Run `env GOFLAGS=-buildvcs=false ./tools/build-qs-go.sh`.
- [x] Run `bash tools/reload-quickshell.sh`.
- [x] Confirm no relevant warnings/errors from the reload tail.
