package openai

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"qs-go/internal/ai/shared"
)

func TestStreamUsesResponsesEndpoint(t *testing.T) {
	img := []byte{0x89, 0x50, 0x4e, 0x47}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/responses" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode payload: %v", err)
		}
		if payload["model"] != "gpt-5.4-mini" || payload["instructions"] != "be brief" || payload["stream"] != true {
			t.Fatalf("unexpected payload header: %#v", payload)
		}
		input := payload["input"].([]any)
		last := input[len(input)-1].(map[string]any)
		content := last["content"].([]any)
		if content[0].(map[string]any)["type"] != "input_image" {
			t.Fatalf("expected Responses image part, got %#v", content)
		}
		tools := payload["tools"].([]any)
		if tools[0].(map[string]any)["type"] != "web_search_preview" {
			t.Fatalf("expected web search preview tool, got %#v", tools[0])
		}
		if tools[1].(map[string]any)["type"] != "function" {
			t.Fatalf("expected Responses function tool, got %#v", tools[1])
		}

		w.Header().Set("Content-Type", "text/event-stream")
		mustFprint(t, w, "event: response.output_text.delta\n")
		mustFprint(t, w, "data: {\"delta\":\"ok\"}\n\n")
		mustFprint(t, w, "event: response.completed\n")
		mustFprint(t, w, "data: {\"response\":{\"usage\":{\"input_tokens\":5,\"output_tokens\":1},\"output\":[]}}\n\n")
	}))
	defer server.Close()

	var got strings.Builder
	result, err := Provider{}.Stream(t.Context(), shared.StreamRequest{
		RawModelID:   "gpt-5.4-mini",
		SystemPrompt: "be brief",
		Config:       shared.ProviderConfig{APIKey: "test-key", BaseURL: server.URL},
		Message:      "describe",
		Attachments: []shared.Attachment{{
			MIME: "image/png",
			B64:  base64.StdEncoding.EncodeToString(img),
		}},
		Tools: []shared.ToolDescriptor{{
			Name:        "shell_command",
			Description: "Run a shell command",
			InputSchema: map[string]any{"type": "object", "properties": map[string]any{}},
		}},
	}, func(token string) {
		got.WriteString(token)
	})
	if err != nil {
		t.Fatalf("stream: %v", err)
	}
	if got.String() != "ok" {
		t.Fatalf("unexpected text: %q", got.String())
	}
	if result.PromptTokens != 5 || result.OutputTokens != 1 {
		t.Fatalf("unexpected usage: %#v", result)
	}
}

func mustFprint(t *testing.T, w http.ResponseWriter, text string) {
	t.Helper()
	if _, err := fmt.Fprint(w, text); err != nil {
		t.Fatalf("write response: %v", err)
	}
}

func TestStreamRejectsNonImageAttachment(t *testing.T) {
	_, err := Provider{}.Stream(t.Context(), shared.StreamRequest{
		RawModelID: "gpt-5.4-mini",
		Config:     shared.ProviderConfig{APIKey: "test-key", BaseURL: "http://127.0.0.1:1"},
		Message:    "read",
		Attachments: []shared.Attachment{{
			MIME: "text/plain",
			B64:  base64.StdEncoding.EncodeToString([]byte("hello")),
		}},
	}, func(string) {})
	if err == nil || !strings.Contains(err.Error(), "image attachments only") {
		t.Fatalf("expected image-only error, got %v", err)
	}
}
