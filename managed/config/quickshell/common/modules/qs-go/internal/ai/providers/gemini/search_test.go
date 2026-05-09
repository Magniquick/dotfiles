package gemini

import (
	"testing"

	"qs-go/internal/ai/shared"
)

func TestBuildPayloadCombinesGemini3SearchAndFunctions(t *testing.T) {
	payload, err := buildPayloadForModel(
		"gemini-3.1-flash-lite-preview",
		"system",
		nil,
		"search and call tools",
		nil,
		[]shared.ToolDescriptor{{Name: "builtin__shell_exec", Description: "Run shell"}},
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	tools := payload["tools"].([]map[string]any)
	if len(tools) != 2 {
		t.Fatalf("expected googleSearch and functionDeclarations, got %#v", tools)
	}
	if _, ok := tools[0]["googleSearch"]; !ok {
		t.Fatalf("expected first tool googleSearch, got %#v", tools[0])
	}
	if _, ok := tools[1]["functionDeclarations"]; !ok {
		t.Fatalf("expected second tool functionDeclarations, got %#v", tools[1])
	}
	toolConfig := payload["toolConfig"].(map[string]any)
	if toolConfig["includeServerSideToolInvocations"] != true {
		t.Fatalf("expected server-side tool invocations, got %#v", toolConfig)
	}
}

func TestBuildPayloadDoesNotCombineGemini2SearchAndFunctions(t *testing.T) {
	payload, err := buildPayloadForModel(
		"gemini-2.5-flash",
		"system",
		nil,
		"call tools",
		nil,
		[]shared.ToolDescriptor{{Name: "builtin__shell_exec", Description: "Run shell"}},
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	tools := payload["tools"].([]map[string]any)
	if len(tools) != 1 {
		t.Fatalf("expected only functionDeclarations, got %#v", tools)
	}
	if _, ok := tools[0]["functionDeclarations"]; !ok {
		t.Fatalf("expected functionDeclarations, got %#v", tools[0])
	}
	if _, ok := tools[0]["googleSearch"]; ok {
		t.Fatalf("gemini 2.x must not combine googleSearch with functions: %#v", tools[0])
	}
}

func TestBuildPayloadUsesSharedToolResultResponse(t *testing.T) {
	payload, err := buildPayloadForModel(
		"gemini-3.1-flash-lite-preview",
		"system",
		[]shared.HistoryMessage{
			{
				Sender: "assistant",
				ToolCall: &shared.ToolCall{
					ID:        "email__email_read",
					Name:      "email__email_read",
					Arguments: map[string]any{"uid": 4938},
				},
			},
			{
				Sender: "user",
				ToolResult: &shared.ToolResult{
					ToolCallID: "email__email_read",
					Name:       "email__email_read",
					Text:       "Short body summary",
					Data: map[string]any{
						"message": map[string]any{"subject": "Status"},
					},
				},
			},
		},
		"",
		nil,
		nil,
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	contents := payload["contents"].([]map[string]any)
	parts := contents[1]["parts"].([]map[string]any)
	response := parts[0]["functionResponse"].(map[string]any)["response"].(map[string]any)
	content := response["content"].([]map[string]any)
	if content[0]["text"] != "Short body summary" {
		t.Fatalf("expected MCP content text, got %#v", response)
	}
	structured := response["structuredContent"].(map[string]any)
	if structured["message"].(map[string]any)["subject"] != "Status" {
		t.Fatalf("expected structuredContent, got %#v", response)
	}
}
