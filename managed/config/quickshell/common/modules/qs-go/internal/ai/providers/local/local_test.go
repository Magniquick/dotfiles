package local

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"qs-go/internal/ai/providers/oai"
	"qs-go/internal/ai/shared"
)

func TestStreamResponsesTextDeltaAndUsage(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/responses" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode payload: %v", err)
		}
		if payload["model"] != "gpt-5.4-mini" {
			t.Fatalf("unexpected model: %#v", payload["model"])
		}
		if _, ok := payload["store"]; ok {
			t.Fatal("local provider should omit store; proxy forces store:false")
		}

		w.Header().Set("Content-Type", "text/event-stream")
		mustFprint(t, w, "event: response.output_text.delta\n")
		mustFprint(t, w, "data: {\"delta\":\"hel\"}\n\n")
		mustFprint(t, w, "event: response.output_text.delta\n")
		mustFprint(t, w, "data: {\"delta\":\"lo\"}\n\n")
		mustFprint(t, w, "event: response.completed\n")
		mustFprint(t, w, "data: {\"response\":{\"usage\":{\"input_tokens\":3,\"output_tokens\":2},\"output\":[]}}\n\n")
	}))
	defer server.Close()

	var got strings.Builder
	result, err := Provider{}.Stream(t.Context(), shared.StreamRequest{
		RawModelID: "gpt-5.4-mini",
		Config: shared.ProviderConfig{
			APIKey:  "test-key",
			BaseURL: server.URL,
		},
		Message: "say hello",
	}, func(token string) {
		got.WriteString(token)
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.String() != "hello" {
		t.Fatalf("unexpected streamed text: %q", got.String())
	}
	if result.PromptTokens != 3 || result.OutputTokens != 2 {
		t.Fatalf("unexpected usage: %#v", result)
	}
}

func TestStreamResponsesFunctionCall(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		mustFprint(t, w, "event: response.output_item.done\n")
		mustFprint(t, w, "data: {\"item\":{\"type\":\"function_call\",\"call_id\":\"call_1\",\"name\":\"builtin__shell_command\",\"arguments\":\"{\\\"command\\\":\\\"date\\\"}\"}}\n\n")
		mustFprint(t, w, "event: response.completed\n")
		mustFprint(t, w, "data: {\"response\":{\"output\":[]}}\n\n")
	}))
	defer server.Close()

	result, err := Provider{}.Stream(t.Context(), shared.StreamRequest{
		RawModelID: "gpt-5.4-mini",
		Config:     shared.ProviderConfig{APIKey: "test-key", BaseURL: server.URL},
		Message:    "run date",
		Tools: []shared.ToolDescriptor{{
			Name:        "builtin__shell_command",
			Description: "Run a shell command",
			InputSchema: map[string]any{
				"type":       "object",
				"properties": map[string]any{"command": map[string]any{"type": "string"}},
			},
		}},
	}, func(string) {})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.ToolCalls) != 1 {
		t.Fatalf("expected one tool call, got %#v", result.ToolCalls)
	}
	call := result.ToolCalls[0]
	if call.ID != "call_1" || call.Name != "builtin__shell_command" || call.Arguments["command"] != "date" {
		t.Fatalf("unexpected tool call: %#v", call)
	}
}

func TestStreamResponsesCustomApplyPatchTool(t *testing.T) {
	const patch = "*** Begin Patch\n*** Add File: hello.txt\n+hi\n*** End Patch\n"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode payload: %v", err)
		}
		tools := payload["tools"].([]any)
		var found map[string]any
		for _, tool := range tools {
			mapped := tool.(map[string]any)
			if mapped["name"] == "apply_patch" {
				found = mapped
			}
		}
		if found == nil {
			t.Fatalf("apply_patch tool missing from payload: %#v", tools)
		}
		if found["type"] != "custom" {
			t.Fatalf("apply_patch should be sent as custom freeform tool, got %#v", found)
		}
		format := found["format"].(map[string]any)
		if format["type"] != "grammar" || format["syntax"] != "lark" {
			t.Fatalf("unexpected freeform format: %#v", format)
		}

		w.Header().Set("Content-Type", "text/event-stream")
		mustFprintf(t, w, "event: response.output_item.done\n")
		mustFprintf(t, w, "data: {\"item\":{\"type\":\"custom_tool_call\",\"call_id\":\"call_patch\",\"name\":\"apply_patch\",\"input\":%q}}\n\n", patch)
		mustFprint(t, w, "event: response.completed\n")
		mustFprint(t, w, "data: {\"response\":{\"output\":[]}}\n\n")
	}))
	defer server.Close()

	result, err := Provider{}.Stream(t.Context(), shared.StreamRequest{
		RawModelID: "gpt-5.4-mini",
		Config:     shared.ProviderConfig{APIKey: "test-key", BaseURL: server.URL},
		Message:    "patch",
		Tools: []shared.ToolDescriptor{{
			Name:        "apply_patch",
			Description: "Patch files",
			Kind:        "freeform",
			Format: map[string]any{
				"type":       "grammar",
				"syntax":     "lark",
				"definition": "start: /.+/",
			},
		}},
	}, func(string) {})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.ToolCalls) != 1 {
		t.Fatalf("expected one tool call, got %#v", result.ToolCalls)
	}
	call := result.ToolCalls[0]
	if call.ID != "call_patch" || call.Name != "apply_patch" || call.Input != patch || call.Arguments["input"] != patch {
		t.Fatalf("unexpected custom tool call: %#v", call)
	}
}

func mustFprint(t *testing.T, w http.ResponseWriter, text string) {
	t.Helper()
	if _, err := fmt.Fprint(w, text); err != nil {
		t.Fatalf("write response: %v", err)
	}
}

func mustFprintf(t *testing.T, w http.ResponseWriter, format string, args ...any) {
	t.Helper()
	if _, err := fmt.Fprintf(w, format, args...); err != nil {
		t.Fatalf("write response: %v", err)
	}
}

func TestBuildInputUsesCustomToolCallOutputForApplyPatch(t *testing.T) {
	input, err := oai.BuildResponsesInput([]shared.HistoryMessage{
		{
			Sender: "assistant",
			ToolCall: &shared.ToolCall{
				ID:    "call_patch",
				Name:  "apply_patch",
				Input: "*** Begin Patch\n*** End Patch\n",
			},
		},
		{
			Sender: "user",
			ToolResult: &shared.ToolResult{
				ToolCallID: "call_patch",
				Name:       "apply_patch",
				Text:       "Done!",
			},
		},
	}, "", nil, "Local")
	if err != nil {
		t.Fatalf("build input: %v", err)
	}
	if input[0]["type"] != "custom_tool_call" || input[0]["input"] == nil {
		t.Fatalf("expected custom tool call item, got %#v", input[0])
	}
	if input[1]["type"] != "custom_tool_call_output" {
		t.Fatalf("expected custom tool call output, got %#v", input[1])
	}
	var patchPayload map[string]any
	if err := json.Unmarshal([]byte(input[1]["output"].(string)), &patchPayload); err != nil {
		t.Fatalf("expected MCP-shaped output JSON, got %#v", input[1])
	}
	if patchPayload["content"].([]any)[0].(map[string]any)["text"] != "Done!" {
		t.Fatalf("expected text content, got %#v", patchPayload)
	}
}

func TestBuildInputUsesSharedToolResultOutput(t *testing.T) {
	input, err := oai.BuildResponsesInput([]shared.HistoryMessage{
		{
			Sender: "assistant",
			ToolCall: &shared.ToolCall{
				ID:        "call_email",
				Name:      "email__email_read",
				Arguments: map[string]any{"uid": 4938},
			},
		},
		{
			Sender: "user",
			ToolResult: &shared.ToolResult{
				ToolCallID: "call_email",
				Name:       "email__email_read",
				Text:       "Short body summary",
				Data: map[string]any{
					"message": map[string]any{"subject": "Status"},
				},
			},
		},
	}, "", nil, "Local")
	if err != nil {
		t.Fatalf("build input: %v", err)
	}

	output, ok := input[1]["output"].(string)
	if !ok {
		t.Fatalf("expected string output, got %#v", input[1])
	}
	var payload map[string]any
	if err := json.Unmarshal([]byte(output), &payload); err != nil {
		t.Fatalf("expected MCP-shaped output JSON, got %q", output)
	}
	if payload["content"].([]any)[0].(map[string]any)["text"] != "Short body summary" {
		t.Fatalf("expected result content text, got %#v", payload)
	}
	if payload["structuredContent"].(map[string]any)["message"].(map[string]any)["subject"] != "Status" {
		t.Fatalf("expected structured content, got %#v", payload)
	}
}

func TestStreamCompactsLargeInputBeforeResponsesRequest(t *testing.T) {
	var compactCalled bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/responses/compact":
			compactCalled = true
			w.Header().Set("Content-Type", "application/json")
			mustFprint(t, w, `{"object":"response.compaction","output":[{"type":"message","role":"assistant","content":[{"type":"input_text","text":"summary"}]}]}`)
		case "/responses":
			var payload map[string]any
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				t.Fatalf("decode responses payload: %v", err)
			}
			input := payload["input"].([]any)
			if len(input) >= 20 {
				t.Fatalf("expected compacted input, got %d items", len(input))
			}
			w.Header().Set("Content-Type", "text/event-stream")
			mustFprint(t, w, "event: response.completed\n")
			mustFprint(t, w, "data: {\"response\":{\"output\":[]}}\n\n")
		default:
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
	}))
	defer server.Close()

	history := make([]shared.HistoryMessage, 0, 20)
	for i := range 20 {
		history = append(history, shared.HistoryMessage{Sender: "user", Body: fmt.Sprintf("message %d", i)})
	}
	_, err := Provider{}.Stream(t.Context(), shared.StreamRequest{
		RawModelID: "gpt-5.4-mini",
		Config:     shared.ProviderConfig{APIKey: "test-key", BaseURL: server.URL},
		History:    history,
		Message:    "continue",
	}, func(string) {})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !compactCalled {
		t.Fatal("expected compact endpoint to be called")
	}
}

func TestNormalizeCompactOutputFixesAssistantContent(t *testing.T) {
	input := []map[string]any{
		{
			"type": "message",
			"role": "assistant",
			"content": []any{
				map[string]any{"type": "input_text", "text": "noted"},
			},
		},
		{"type": "compaction_summary", "encrypted_content": "abc"},
	}
	normalized := oai.NormalizeCompactOutput(input)
	content := normalized[0]["content"].([]any)
	first := content[0].(map[string]any)
	if first["type"] != "output_text" {
		t.Fatalf("assistant content should be output_text, got %#v", first["type"])
	}
}
