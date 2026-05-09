package shared

import (
	"encoding/json"
	"testing"
)

func TestToolResultTranscriptOutputTextOnlyUsesMCPContentShape(t *testing.T) {
	output := ToolResultTranscriptOutput(ToolResult{Text: "hello"})

	var payload map[string]any
	if err := json.Unmarshal([]byte(output), &payload); err != nil {
		t.Fatalf("expected JSON MCP-shaped output, got %q: %v", output, err)
	}
	content := payload["content"].([]any)
	if content[0].(map[string]any)["text"] != "hello" {
		t.Fatalf("expected text content, got %#v", payload)
	}
}

func TestToolResultTranscriptOutputIncludesTextAndStructuredContent(t *testing.T) {
	output := ToolResultTranscriptOutput(ToolResult{
		Text: "message body",
		Data: map[string]any{
			"subject": "Status",
			"uid":     float64(4938),
		},
	})

	var payload map[string]any
	if err := json.Unmarshal([]byte(output), &payload); err != nil {
		t.Fatalf("expected JSON output, got %q: %v", output, err)
	}
	content := payload["content"].([]any)
	if content[0].(map[string]any)["text"] != "message body" {
		t.Fatalf("expected text content, got %#v", payload)
	}
	structured := payload["structuredContent"].(map[string]any)
	if structured["subject"] != "Status" || structured["uid"] != float64(4938) {
		t.Fatalf("expected structuredContent to preserve data, got %#v", payload)
	}
}

func TestToolResultTranscriptOutputOmitsUIMeta(t *testing.T) {
	output := ToolResultTranscriptOutput(ToolResult{
		Content: []map[string]any{{
			"type": "text",
			"text": "created",
		}},
		StructuredContent: map[string]any{"id": "task_1"},
		Meta:              map[string]any{"source": "todoist"},
		IsError:           true,
	})

	var payload map[string]any
	if err := json.Unmarshal([]byte(output), &payload); err != nil {
		t.Fatalf("expected JSON output, got %q: %v", output, err)
	}
	if payload["isError"] != true {
		t.Fatalf("expected MCP isError flag, got %#v", payload)
	}
	if _, ok := payload["_meta"]; ok {
		t.Fatalf("_meta must stay out of the model transcript payload, got %#v", payload)
	}
	if payload["structuredContent"].(map[string]any)["id"] != "task_1" {
		t.Fatalf("expected structured content, got %#v", payload)
	}
}

func TestToolResultTranscriptPayloadIncludesErrorFlag(t *testing.T) {
	payload := ToolResultTranscriptPayload(ToolResult{
		Text:    "boom",
		IsError: true,
	})

	if payload["isError"] != true {
		t.Fatalf("expected error payload, got %#v", payload)
	}
	content := payload["content"].([]map[string]any)
	if content[0]["text"] != "boom" {
		t.Fatalf("expected text content, got %#v", payload)
	}
}

func TestToolResultUIPayloadKeepsMetaAndTranscriptFields(t *testing.T) {
	payload := ToolResultUIPayload(ToolResult{
		Text:              "visible",
		Data:              map[string]any{"id": "task_1"},
		Meta:              map[string]any{"source": "todoist"},
		DurationMS:        12,
		StructuredContent: map[string]any{"id": "task_1"},
	})

	if payload["_meta"].(map[string]any)["source"] != "todoist" {
		t.Fatalf("expected UI payload to keep _meta, got %#v", payload)
	}
	if payload["duration_ms"] != int64(12) {
		t.Fatalf("expected duration in UI payload, got %#v", payload)
	}
	if payload["text"] != "visible" || payload["data"].(map[string]any)["id"] != "task_1" {
		t.Fatalf("expected local convenience fields in UI payload, got %#v", payload)
	}
	if payload["structuredContent"].(map[string]any)["id"] != "task_1" {
		t.Fatalf("expected transcript fields in UI payload, got %#v", payload)
	}
}
