// Package oai tests Responses payload conversion helpers.
package oai

import (
	"bufio"
	"encoding/json"
	"strings"
	"testing"

	"qs-go/internal/ai/shared"
)

func TestBuildResponsesToolsGroupsMCPToolsIntoNamespace(t *testing.T) {
	tools := BuildResponsesTools([]shared.ToolDescriptor{
		{
			Name:                 "todoist__find-tasks-by-date",
			Description:          "Get tasks by date.",
			InputSchema:          map[string]any{"type": "object", "properties": map[string]any{}},
			ServerID:             "todoist",
			Namespace:            "mcp__todoist__",
			NamespaceDescription: "Todoist Task and Project Management Tools",
		},
		{
			Name:                 "todoist__get-overview",
			Description:          "Get account overview.",
			InputSchema:          map[string]any{"type": "object", "properties": map[string]any{}},
			ServerID:             "todoist",
			Namespace:            "mcp__todoist__",
			NamespaceDescription: "Todoist Task and Project Management Tools",
		},
	}, false)

	if len(tools) != 1 {
		t.Fatalf("expected one namespace tool, got %#v", tools)
	}
	namespace := tools[0]
	if namespace["type"] != "namespace" {
		t.Fatalf("expected namespace tool shape, got %#v", namespace)
	}
	if namespace["name"] != "mcp__todoist__" {
		t.Fatalf("unexpected namespace name: %#v", namespace["name"])
	}
	if namespace["description"] != "Todoist Task and Project Management Tools" {
		t.Fatalf("unexpected namespace description: %#v", namespace["description"])
	}
	children, ok := namespace["tools"].([]map[string]any)
	if !ok || len(children) != 2 {
		t.Fatalf("expected nested function tools, got %#v", namespace["tools"])
	}
	if children[0]["type"] != "function" || children[0]["name"] != "find-tasks-by-date" {
		t.Fatalf("expected unqualified nested function, got %#v", children[0])
	}
	if children[1]["type"] != "function" || children[1]["name"] != "get-overview" {
		t.Fatalf("expected unqualified nested function, got %#v", children[1])
	}
}

func TestBuildResponsesToolsAddsHostedSearchForDeferredNamespaceTools(t *testing.T) {
	tools := BuildResponsesTools([]shared.ToolDescriptor{
		{
			Name:        "shell_command",
			Description: "Run a shell command.",
			InputSchema: map[string]any{"type": "object", "properties": map[string]any{}},
		},
		{
			Name:                 "todoist__find-tasks-by-date",
			Description:          "Get tasks by date.",
			FullInstructions:     "Full Todoist server instructions stay off the namespace heading.",
			SearchText:           "date due today overdue project task",
			InputSchema:          map[string]any{"type": "object", "properties": map[string]any{}},
			ServerID:             "todoist",
			Namespace:            "mcp__todoist__",
			NamespaceDescription: "Todoist tasks and projects.",
			DeferLoading:         true,
		},
		{
			Name:                 "todoist__get-overview",
			Description:          "Get account overview.",
			InputSchema:          map[string]any{"type": "object", "properties": map[string]any{}},
			ServerID:             "todoist",
			Namespace:            "mcp__todoist__",
			NamespaceDescription: "Todoist tasks and projects.",
		},
	}, false)

	if len(tools) != 3 {
		t.Fatalf("expected shell function, tool_search, and namespace, got %#v", tools)
	}
	if tools[1]["type"] != "tool_search" {
		t.Fatalf("expected hosted tool_search before deferred namespace, got %#v", tools)
	}
	namespace := tools[2]
	if namespace["description"] != "Todoist tasks and projects." {
		t.Fatalf("namespace should keep short description, got %#v", namespace["description"])
	}
	if strings.Contains(namespace["description"].(string), "Full Todoist") {
		t.Fatalf("namespace description leaked full server instructions: %#v", namespace)
	}
	children := namespace["tools"].([]map[string]any)
	if children[0]["name"] != "find-tasks-by-date" || children[0]["defer_loading"] != true {
		t.Fatalf("expected deferred child function, got %#v", children[0])
	}
	if desc := children[0]["description"].(string); desc != "Get tasks by date." {
		t.Fatalf("deferred child should keep compact tool description, got %q", desc)
	}
	if desc := children[0]["description"].(string); strings.Contains(desc, "Full Todoist server instructions") || strings.Contains(desc, "date due today") {
		t.Fatalf("deferred child leaked search metadata into Responses description: %q", desc)
	}
	if _, exists := children[1]["defer_loading"]; exists {
		t.Fatalf("non-deferred child should remain directly callable, got %#v", children[1])
	}
}

func TestBuildResponsesInputPreservesFunctionCallNamespace(t *testing.T) {
	input, err := BuildResponsesInput([]shared.HistoryMessage{{
		Sender: "assistant",
		ToolCall: &shared.ToolCall{
			ID:        "call_todoist",
			Namespace: "mcp__todoist__",
			Name:      "find-tasks-by-date",
			Arguments: map[string]any{"startDate": "today"},
		},
	}}, "next", nil, "OpenAI")
	if err != nil {
		t.Fatalf("BuildResponsesInput: %v", err)
	}

	call := input[0]
	if call["type"] != "function_call" || call["name"] != "find-tasks-by-date" {
		t.Fatalf("unexpected function call item: %#v", call)
	}
	if call["namespace"] != "mcp__todoist__" {
		t.Fatalf("expected namespace on replayed function call, got %#v", call)
	}
}

func TestBuildResponsesInputOmitsToolResultMetaFromTranscript(t *testing.T) {
	input, err := BuildResponsesInput([]shared.HistoryMessage{
		{
			Sender:   "assistant",
			ToolCall: &shared.ToolCall{ID: "call_todoist", Namespace: "mcp__todoist__", Name: "find-tasks"},
		},
		{
			Sender: "user",
			ToolResult: &shared.ToolResult{
				ToolCallID:        "call_todoist",
				Name:              "find-tasks",
				Content:           []map[string]any{{"type": "text", "text": "1 task"}},
				StructuredContent: map[string]any{"count": float64(1)},
				Meta:              map[string]any{"internal_cursor": "secret"},
			},
		},
	}, "next", nil, "OpenAI")
	if err != nil {
		t.Fatalf("BuildResponsesInput: %v", err)
	}

	var payload map[string]any
	if err := json.Unmarshal([]byte(input[1]["output"].(string)), &payload); err != nil {
		t.Fatalf("expected JSON output, got %#v: %v", input[1], err)
	}
	if _, ok := payload["_meta"]; ok {
		t.Fatalf("function_call_output must not expose _meta to the model, got %#v", payload)
	}
	if payload["structuredContent"].(map[string]any)["count"] != float64(1) {
		t.Fatalf("expected structured content to remain model-visible, got %#v", payload)
	}
}

func TestParseResponsesStreamCapturesFunctionCallNamespace(t *testing.T) {
	stream := strings.NewReader(strings.Join([]string{
		"event: response.output_item.done",
		`data: {"item":{"type":"function_call","call_id":"call_todoist","namespace":"mcp__todoist__","name":"find-tasks-by-date","arguments":"{\"startDate\":\"today\"}"}}`,
		"",
	}, "\n"))

	result, err := ParseResponsesStream(bufio.NewReader(stream), func(string) {})
	if err != nil {
		t.Fatalf("ParseResponsesStream: %v", err)
	}
	if len(result.ToolCalls) != 1 {
		t.Fatalf("expected one tool call, got %#v", result.ToolCalls)
	}
	call := result.ToolCalls[0]
	if call.Namespace != "mcp__todoist__" || call.Name != "find-tasks-by-date" {
		t.Fatalf("expected namespaced tool call, got %#v", call)
	}
}

func TestParseResponsesStreamAttachesToolSearchRawItemsToFunctionCall(t *testing.T) {
	stream := strings.NewReader(strings.Join([]string{
		"event: response.output_item.done",
		`data: {"item":{"id":"ts_1","type":"tool_search_call","status":"completed","queries":["todoist"],"execution":"server","call_id":null}}`,
		"",
		"event: response.output_item.done",
		`data: {"item":{"id":"tso_1","type":"tool_search_output","tools":[{"type":"namespace","name":"mcp__todoist__","tools":[{"type":"function","name":"find-tasks-by-date"}]}]}}`,
		"",
		"event: response.output_item.done",
		`data: {"item":{"id":"fc_1","type":"function_call","call_id":"call_todoist","namespace":"mcp__todoist__","name":"find-tasks-by-date","arguments":"{\"startDate\":\"today\"}","status":"completed"}}`,
		"",
	}, "\n"))

	result, err := ParseResponsesStream(bufio.NewReader(stream), func(string) {})
	if err != nil {
		t.Fatalf("ParseResponsesStream: %v", err)
	}
	if len(result.ToolCalls) != 1 {
		t.Fatalf("expected one tool call, got %#v", result.ToolCalls)
	}
	if len(result.RawItems) != 3 {
		t.Fatalf("expected canonical raw response items, got %#v", result.RawItems)
	}
	raw := result.ToolCalls[0].RawItems
	if len(raw) != 3 {
		t.Fatalf("expected tool_search_call, tool_search_output, and function_call raw items, got %#v", raw)
	}
	if raw[0]["type"] != "tool_search_call" || raw[1]["type"] != "tool_search_output" || raw[2]["type"] != "function_call" {
		t.Fatalf("unexpected raw replay order: %#v", raw)
	}

	input, err := BuildResponsesInput([]shared.HistoryMessage{{
		Sender:   "assistant",
		ToolCall: &result.ToolCalls[0],
	}}, "next", nil, "OpenAI")
	if err != nil {
		t.Fatalf("BuildResponsesInput: %v", err)
	}
	if len(input) < 4 || input[0]["type"] != "tool_search_call" || input[1]["type"] != "tool_search_output" || input[2]["type"] != "function_call" {
		t.Fatalf("expected raw output items to replay before next message, got %#v", input)
	}
}

func TestParseResponsesStreamPreservesReplayableRawItemsWithoutToolCall(t *testing.T) {
	stream := strings.NewReader(strings.Join([]string{
		"event: response.output_item.done",
		`data: {"item":{"id":"ws_1","type":"web_search_call","status":"completed"}}`,
		"",
		"event: response.output_item.done",
		`data: {"item":{"id":"mcp_1","type":"mcp_call","server_label":"Docs","name":"search","arguments":"{\"q\":\"x\"}","status":"completed"}}`,
		"",
		"event: response.output_item.done",
		`data: {"item":{"id":"msg_1","type":"message","content":[{"type":"output_text","text":"answer"}]}}`,
		"",
		"event: response.output_item.done",
		`data: {"item":{"id":"future_1","type":"future_tool_observation","payload":{"ok":true}}}`,
		"",
	}, "\n"))

	result, err := ParseResponsesStream(bufio.NewReader(stream), func(string) {})
	if err != nil {
		t.Fatalf("ParseResponsesStream: %v", err)
	}
	if len(result.ToolCalls) != 0 {
		t.Fatalf("expected no local executable tool calls, got %#v", result.ToolCalls)
	}
	if len(result.RawItems) != 4 || result.RawItems[0]["type"] != "web_search_call" || result.RawItems[1]["type"] != "mcp_call" || result.RawItems[2]["type"] != "message" || result.RawItems[3]["type"] != "future_tool_observation" {
		t.Fatalf("expected replayable raw web/mcp/message/future items, got %#v", result.RawItems)
	}
}
