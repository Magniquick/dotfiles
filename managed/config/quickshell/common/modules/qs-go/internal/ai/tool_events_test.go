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
	if event.AgentPayload == "" || !strings.Contains(event.AgentPayload, `"type":"function_call"`) || !strings.Contains(event.AgentPayload, `\"command\":\"go test ./...\"`) {
		t.Fatalf("expected Codex function_call payload with command, got %q", event.AgentPayload)
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
	if !strings.Contains(event.AgentPayload, `"type":"function_call_output"`) {
		t.Fatalf("expected Codex function_call_output payload, got %q", event.AgentPayload)
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
	if !strings.Contains(event.AgentPayload, `"type":"custom_tool_call"`) || !strings.Contains(event.AgentPayload, `"type":"custom_tool_call_output"`) {
		t.Fatalf("expected Codex custom tool payload, got %#v", event)
	}
	if !strings.Contains(event.AgentPayload, `\n`) {
		t.Fatalf("expected JSON-escaped newlines in Codex payload, got %q", event.AgentPayload)
	}
}

func TestBuildToolDoneEventCodexPayloadEscapesShellNewlines(t *testing.T) {
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

	if !strings.Contains(event.AgentPayload, `"output":"hello\nsecond line"`) {
		t.Fatalf("expected exact JSON string newline escaping in Codex output payload, got %q", event.AgentPayload)
	}
	if strings.Contains(event.AgentPayload, "hello\nsecond line") {
		t.Fatalf("Codex payload should contain escaped JSON newlines, not literal newlines: %q", event.AgentPayload)
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
	if event.Summary != "failed server__lookup" || event.Subtitle != "boom" {
		t.Fatalf("unexpected generic failure copy: %#v", event)
	}
}
