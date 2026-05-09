package ai

import (
	"strings"
	"testing"

	"qs-go/internal/ai/shared"
)

func TestBuildToolStartEventForShellExec(t *testing.T) {
	event := buildToolStartEvent(shared.ToolCall{
		ID:   "call_shell",
		Name: "shell_command",
		Arguments: map[string]any{
			"command": "go test ./...",
			"cwd":     "/workspace",
		},
	})

	if event.Phase != "tool_start" || event.ToolCallID != "call_shell" || event.ToolName != "shell_command" {
		t.Fatalf("unexpected event identity: %#v", event)
	}
	if event.Status != "running" || event.Summary != "running shell_command..." {
		t.Fatalf("unexpected running summary: %#v", event)
	}
	if event.Subtitle != "go test ./..." {
		t.Fatalf("expected command subtitle, got %q", event.Subtitle)
	}
	if raw := mustJSON(event); strings.Contains(raw, "agent_payload") || len(event.ReplayItems) != 0 {
		t.Fatalf("tool start events should not carry stored replay/payload data, got %q", raw)
	}
}

func TestBuildToolDoneEventForShellExecNoOutput(t *testing.T) {
	event := buildToolDoneEvent(
		shared.ToolCall{
			ID:        "call_shell",
			Name:      "shell_command",
			Arguments: map[string]any{"command": "go test ./..."},
		},
		shared.ToolResult{
			ToolCallID: "call_shell",
			Name:       "shell_command",
			Data: map[string]any{
				"exit_code": 0,
				"stdout":    "",
				"stderr":    "",
				"cwd":       "/workspace",
			},
		},
	)

	if event.Phase != "tool_done" || event.Status != "success" || event.IsError {
		t.Fatalf("unexpected success event: %#v", event)
	}
	if event.Summary != "ran go test ./..." {
		t.Fatalf("unexpected summary: %q", event.Summary)
	}
	if event.Subtitle != "exit 0 · no stdout" {
		t.Fatalf("unexpected subtitle: %q", event.Subtitle)
	}
	if len(event.DetailSections) != 1 || event.DetailSections[0].Title != "Stdout" {
		t.Fatalf("expected stdout-only section, got %#v", event.DetailSections)
	}
	if event.DetailSections[0].Content != "(no output)" {
		t.Fatalf("expected no-output stdout marker, got %#v", event.DetailSections)
	}
	if len(event.ReplayItems) != 1 || event.ReplayItems[0]["type"] != "function_call_output" {
		t.Fatalf("expected only local tool output replay item, got %#v", event.ReplayItems)
	}
	if raw := mustJSON(event); strings.Contains(raw, "agent_payload") {
		t.Fatalf("tool events should not store agent payloads, got %q", raw)
	}
}

func TestBuildToolDoneEventForShellExecShowsOnlyStdoutDetails(t *testing.T) {
	event := buildToolDoneEvent(
		shared.ToolCall{
			ID:        "call_shell",
			Name:      "shell_command",
			Arguments: map[string]any{"command": "printf hello"},
		},
		shared.ToolResult{
			ToolCallID: "call_shell",
			Name:       "shell_command",
			Data: map[string]any{
				"exit_code": 0,
				"stdout":    "hello\n",
				"stderr":    "warning\n",
				"cwd":       "/workspace",
			},
		},
	)

	if len(event.DetailSections) != 1 {
		t.Fatalf("expected one stdout detail section, got %#v", event.DetailSections)
	}
	if event.DetailSections[0].Content != "hello" {
		t.Fatalf("expected stdout only, got %q", event.DetailSections[0].Content)
	}
	if strings.Contains(event.DetailSections[0].Content, "stderr") || strings.Contains(event.DetailSections[0].Content, "exit code") {
		t.Fatalf("stdout dropdown should not include command metadata: %q", event.DetailSections[0].Content)
	}
}

func TestBuildToolDoneEventForApplyPatchStats(t *testing.T) {
	const patch = `*** Begin Patch
*** Add File: docs/smoke-note.md
+# Smoke note
+Tool-call rows can summarize edits.
*** Update File: leftpanel/components/ChatMessage.qml
@@
-old
+new
+extra
*** End Patch
`
	event := buildToolDoneEvent(
		shared.ToolCall{
			ID:        "call_patch",
			Name:      "apply_patch",
			Arguments: map[string]any{"input": patch},
			Input:     patch,
		},
		shared.ToolResult{
			ToolCallID: "call_patch",
			Name:       "apply_patch",
			Data: map[string]any{
				"changed_files": []string{"docs/smoke-note.md", "leftpanel/components/ChatMessage.qml"},
			},
		},
	)

	if event.Summary != "edited 2 files +4 -1" {
		t.Fatalf("unexpected patch summary: %q", event.Summary)
	}
	if event.Subtitle != "apply_patch completed" {
		t.Fatalf("unexpected subtitle: %q", event.Subtitle)
	}
	if len(event.DetailSections) == 0 || !strings.Contains(event.DetailSections[0].Content, "docs/smoke-note.md   +2 -0") {
		t.Fatalf("expected per-file stats, got %#v", event.DetailSections)
	}
	if len(event.DetailSections) < 2 || event.DetailSections[1].Title != "Diff" || event.DetailSections[1].Kind != "diff" {
		t.Fatalf("expected rendered diff section, got %#v", event.DetailSections)
	}
	if !strings.Contains(event.DetailSections[1].Content, "diff --git a/docs/smoke-note.md b/docs/smoke-note.md") ||
		!strings.Contains(event.DetailSections[1].Content, "--- /dev/null") ||
		!strings.Contains(event.DetailSections[1].Content, "+++ b/docs/smoke-note.md") ||
		!strings.Contains(event.DetailSections[1].Content, "-old") ||
		!strings.Contains(event.DetailSections[1].Content, "+extra") {
		t.Fatalf("expected unified diff content, got %q", event.DetailSections[1].Content)
	}
	if len(event.ReplayItems) != 1 || event.ReplayItems[0]["type"] != "custom_tool_call_output" {
		t.Fatalf("expected only apply_patch output replay item, got %#v", event.ReplayItems)
	}
	if raw := mustJSON(event); strings.Contains(raw, "agent_payload") || strings.Contains(raw, "custom_tool_call\"") {
		t.Fatalf("event should not store full custom-tool call payload, got %q", raw)
	}
}

func TestBuildToolDoneEventReplayItemsEscapeShellNewlines(t *testing.T) {
	event := buildToolDoneEvent(
		shared.ToolCall{
			ID:        "call_shell",
			Name:      "shell_command",
			Arguments: map[string]any{"command": "cat smoke-note.txt"},
		},
		shared.ToolResult{
			ToolCallID: "call_shell",
			Name:       "shell_command",
			Text:       "hello\nsecond line",
			Data:       map[string]any{"stdout": "hello\nsecond line\n", "stderr": "", "exit_code": 0},
		},
	)
	replay := mustJSON(event.ReplayItems)

	if !strings.Contains(replay, `\"content\":[{\"text\":\"hello\\nsecond line\",\"type\":\"text\"}]`) {
		t.Fatalf("expected replay output to include MCP content text, got %q", replay)
	}
	if !strings.Contains(replay, `\"structuredContent\":{\"exit_code\":0`) || !strings.Contains(replay, `\"stdout\":\"hello\\nsecond line\\n\"`) {
		t.Fatalf("expected replay output to include structured shell data, got %q", replay)
	}
	if strings.Contains(replay, "hello\nsecond line") {
		t.Fatalf("replay output should contain escaped JSON newlines, not literal newlines: %q", replay)
	}
}

func TestBuildToolDoneEventForGenericToolOnlyShowsModelVisibleOutput(t *testing.T) {
	event := buildToolDoneEvent(
		shared.ToolCall{
			ID:   "call_email",
			Name: "email__email_read",
			Arguments: map[string]any{
				"account": "navon",
				"uid":     4938,
			},
		},
		shared.ToolResult{
			ToolCallID: "call_email",
			Name:       "email__email_read",
			Text:       "Short body summary",
			Data: map[string]any{
				"message": map[string]any{
					"subject": "Status",
					"uid":     4938,
				},
			},
		},
	)

	if len(event.DetailSections) != 2 {
		t.Fatalf("expected arguments and result sections, got %#v", event.DetailSections)
	}
	if event.DetailSections[1].Title != "Result" || event.DetailSections[1].Content != "Short body summary" {
		t.Fatalf("expected model-visible result section, got %#v", event.DetailSections)
	}
	for _, section := range event.DetailSections {
		if section.Title == "Data" {
			t.Fatalf("generic tool UI should not duplicate structured payload as a Data section: %#v", event.DetailSections)
		}
	}
	replay := mustJSON(event.ReplayItems)
	if !strings.Contains(replay, `\"structuredContent\":{\"message\"`) {
		t.Fatalf("replay output should include MCP-shaped structured content, got %q", replay)
	}
	if !strings.Contains(replay, `\"content\":[{\"text\":\"Short body summary\",\"type\":\"text\"}]`) {
		t.Fatalf("expected replay output to send MCP content text, got %q", replay)
	}
}

func TestBuildToolDoneEventKeepsMetaOutOfReplayItems(t *testing.T) {
	event := buildToolDoneEvent(
		shared.ToolCall{
			ID:        "call_todoist",
			Namespace: "mcp__todoist__",
			Name:      "find-tasks",
		},
		shared.ToolResult{
			ToolCallID:        "call_todoist",
			Name:              "find-tasks",
			Content:           []map[string]any{{"type": "text", "text": "1 task"}},
			StructuredContent: map[string]any{"count": 1},
			Meta:              map[string]any{"internal_cursor": "secret"},
		},
	)
	replay := mustJSON(event.ReplayItems)

	if strings.Contains(replay, "_meta") || strings.Contains(replay, "internal_cursor") {
		t.Fatalf("replay items are sent back to the model and must not include _meta, got %q", replay)
	}
	if !strings.Contains(replay, `\"structuredContent\":{\"count\":1}`) {
		t.Fatalf("expected model-visible structured content to remain, got %q", replay)
	}
	foundMetaSection := false
	for _, section := range event.DetailSections {
		if section.Title == "Metadata" && strings.Contains(section.Content, "internal_cursor") {
			foundMetaSection = true
		}
	}
	if !foundMetaSection {
		t.Fatalf("UI detail sections should keep metadata, got %#v", event.DetailSections)
	}
}

func TestBuildToolDoneEventUsesStructuredMetadataForRows(t *testing.T) {
	event := buildToolDoneEvent(
		shared.ToolCall{
			ID:          "call_todoist",
			Namespace:   "mcp__todoist__",
			Name:        "find-tasks-by-date",
			ServerID:    "todoist",
			ServerLabel: "Todoist",
			ToolTitle:   "Find tasks by date",
			ReadOnly:    true,
			Risk:        "read",
			Arguments:   map[string]any{"startDate": "today"},
		},
		shared.ToolResult{
			ToolCallID: "call_todoist",
			Name:       "find-tasks-by-date",
			Text:       "No results.",
			DurationMS: 42,
		},
	)

	if event.ServerID != "todoist" || event.ServerLabel != "Todoist" || event.Namespace != "mcp__todoist__" {
		t.Fatalf("expected server metadata on event, got %#v", event)
	}
	if event.ToolTitle != "Find tasks by date" || !event.ReadOnly || event.Risk != "read" || event.DurationMS != 42 {
		t.Fatalf("expected tool metadata on event, got %#v", event)
	}
}

func TestBuildToolDoneEventOnlyStoresToolOutputReplayPayload(t *testing.T) {
	call := shared.ToolCall{
		ID:        "call_todoist",
		Namespace: "mcp__todoist__",
		Name:      "find-tasks-by-date",
		Arguments: map[string]any{"startDate": "today"},
		RawItems: []map[string]any{
			{"type": "tool_search_call", "id": "ts_1", "execution": "server"},
			{"type": "tool_search_output", "id": "tso_1", "tools": []any{}},
			{"type": "function_call", "call_id": "call_todoist", "namespace": "mcp__todoist__", "name": "find-tasks-by-date", "arguments": `{"startDate":"today"}`},
		},
	}
	event := buildToolDoneEvent(call, shared.ToolResult{ToolCallID: "call_todoist", Name: "find-tasks-by-date", Text: "ok"})
	replay := mustJSON(event.ReplayItems)

	if len(event.ReplayItems) != 1 || event.ReplayItems[0]["type"] != "function_call_output" {
		t.Fatalf("expected only tool output replay item, got %#v", event.ReplayItems)
	}
	if strings.Contains(replay, "tool_search_call") || strings.Contains(replay, "tool_search_output") || strings.Contains(replay, `"function_call"`) {
		t.Fatalf("raw search/model-output items should live in response_items, not tool payloads: %q", replay)
	}
}

func TestBuildToolDoneEventUsesDisplayNameForQualifiedMCPTool(t *testing.T) {
	event := buildToolDoneEvent(
		shared.ToolCall{
			ID:        "call_todoist",
			Name:      "todoist__find-tasks-by-date",
			Arguments: map[string]any{"startDate": "today"},
		},
		shared.ToolResult{
			ToolCallID: "call_todoist",
			Name:       "todoist__find-tasks-by-date",
			Text:       "No results.",
		},
	)

	if event.Summary != "called Todoist / find-tasks-by-date" {
		t.Fatalf("qualified tool name should be display-only cleaned up, got %q", event.Summary)
	}
	if event.ToolName != "todoist__find-tasks-by-date" {
		t.Fatalf("raw tool name should remain persisted for replay, got %q", event.ToolName)
	}
	if raw := mustJSON(event); strings.Contains(raw, "agent_payload") {
		t.Fatalf("tool UI event should not store agent payload, got %q", raw)
	}
}

func TestBuildToolDoneEventOmitsPresentationIcon(t *testing.T) {
	event := buildToolDoneEvent(
		shared.ToolCall{ID: "call_todoist", Namespace: "mcp__todoist__", Name: "find-tasks"},
		shared.ToolResult{ToolCallID: "call_todoist", Name: "find-tasks", Text: "ok"},
	)
	if raw := mustJSON(event); strings.Contains(raw, `"icon"`) {
		t.Fatalf("tool events should not persist presentation icons, got %q", raw)
	}
}

func TestBuildToolDoneEventForGenericFailure(t *testing.T) {
	event := buildToolDoneEvent(
		shared.ToolCall{ID: "call_mcp", Name: "server__lookup", Arguments: map[string]any{"q": "x"}},
		shared.ToolResult{ToolCallID: "call_mcp", Name: "server__lookup", Text: "boom", IsError: true},
	)

	if event.Phase != "tool_error" || event.Status != "error" || !event.IsError {
		t.Fatalf("unexpected error event: %#v", event)
	}
	if event.Summary != "failed server / lookup" || event.Subtitle != "boom" {
		t.Fatalf("unexpected generic failure copy: %#v", event)
	}
}
