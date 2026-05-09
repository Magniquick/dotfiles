package main

import (
	"encoding/json"
	"os"
	"testing"

	"qs-go/internal/ai/shared"
	"qs-go/internal/chatstore"
)

func TestHistoryFromMessagesUsesResponseItemsBeforeUIRows(t *testing.T) {
	history, err := historyFromMessagesAndResponseItems([]chatstore.Message{
		{
			ID:             "user_1",
			ConversationID: "conv",
			Ordinal:        0,
			Sender:         "user",
			Kind:           "chat",
			Status:         "complete",
			Body:           "list tasks",
		},
		{
			ID:             "msg_tool",
			ConversationID: "conv",
			Ordinal:        1,
			Sender:         "tool",
			Kind:           "tool",
			Status:         "complete",
			ToolCalls: []chatstore.ToolCall{{
				ID:          "call_todoist",
				MessageID:   "msg_tool",
				ToolCallID:  "call_todoist",
				ToolName:    "find-tasks-by-date",
				PayloadJSON: mustJSON(map[string]any{}),
			}},
		},
		{
			ID:             "asst_1",
			ConversationID: "conv",
			Ordinal:        2,
			Sender:         "assistant",
			Kind:           "chat",
			Status:         "complete",
			Body:           "UI assistant text should not replay when ledger exists",
		},
	}, []chatstore.ResponseItem{
		{
			ConversationID: "conv",
			TurnID:         "user_1",
			TurnOrdinal:    0,
			ItemOrdinal:    0,
			Source:         "model_output",
			ItemType:       "function_call",
			CallID:         "call_todoist",
			RawJSON:        `{"type":"function_call","call_id":"call_todoist","namespace":"mcp__todoist__","name":"find-tasks-by-date","arguments":"{\"startDate\":\"today\"}"}`,
		},
		{
			ConversationID: "conv",
			TurnID:         "user_1",
			TurnOrdinal:    0,
			ItemOrdinal:    1,
			Source:         "tool_output",
			ItemType:       "function_call_output",
			CallID:         "call_todoist",
			RawJSON:        `{"type":"function_call_output","call_id":"call_todoist","output":"Task summary"}`,
		},
		{
			ConversationID: "conv",
			TurnID:         "user_1",
			TurnOrdinal:    0,
			ItemOrdinal:    2,
			Source:         "model_output",
			ItemType:       "message",
			RawJSON:        `{"type":"message","content":[{"type":"output_text","text":"UI assistant text should not replay when ledger exists"}]}`,
		},
	})
	if err != nil {
		t.Fatalf("historyFromMessagesAndResponseItems: %v", err)
	}
	if len(history) != 2 {
		t.Fatalf("expected user message plus ledger raw replay, got %#v", history)
	}
	if history[0].Sender != "user" || history[0].Body != "list tasks" {
		t.Fatalf("expected first item to be user turn, got %#v", history[0])
	}
	if len(history[1].RawItems) != 3 || history[1].RawItems[0]["type"] != "function_call" || history[1].RawItems[1]["type"] != "function_call_output" || history[1].RawItems[2]["type"] != "message" {
		t.Fatalf("expected exact ledger raw Responses items, got %#v", history[1])
	}
	for _, item := range history {
		if item.Body == "UI assistant text should not replay when ledger exists" {
			t.Fatalf("assistant UI row was replayed despite ledger: %#v", history)
		}
	}
}

func TestParseOptionsAllowsDumpToolsWithoutMessage(t *testing.T) {
	opts, err := parseOptions([]string{"--dump-tools"})
	if err != nil {
		t.Fatalf("parseOptions: %v", err)
	}
	if !opts.dumpTools || opts.message != "" {
		t.Fatalf("expected dump-tools mode without message, got %#v", opts)
	}
}

func TestParseOptionsAllowsDumpResponseItemsWithoutMessage(t *testing.T) {
	opts, err := parseOptions([]string{"--dump-response-items"})
	if err != nil {
		t.Fatalf("parseOptions: %v", err)
	}
	if !opts.dumpResponseItems || opts.message != "" {
		t.Fatalf("expected dump-response-items mode without message, got %#v", opts)
	}
}

func TestBuildResponsesPayloadForDumpIncludesToolsAndHistory(t *testing.T) {
	payload, err := buildResponsesPayload("gpt-5.4-mini", "system", []shared.HistoryMessage{{
		RawItems: []map[string]any{{"type": "tool_search_call", "id": "ts_1"}},
	}}, "list tasks", nil, []shared.ToolDescriptor{{
		Name:                 "todoist__find-tasks",
		Description:          "Find tasks.",
		ServerID:             "todoist",
		Namespace:            "mcp__todoist__",
		NamespaceDescription: "Todoist tasks.",
		DeferLoading:         true,
	}}, true)
	if err != nil {
		t.Fatalf("buildResponsesPayload: %v", err)
	}
	tools := payload["tools"].([]map[string]any)
	if len(tools) != 3 || tools[1]["type"] != "tool_search" {
		t.Fatalf("expected web_search, tool_search, namespace tools, got %#v", tools)
	}
	input := payload["input"].([]map[string]any)
	if input[0]["type"] != "tool_search_call" || input[len(input)-1]["role"] != "user" {
		t.Fatalf("expected raw history item before user message, got %#v", input)
	}
}

func TestDefaultMcpConfigPathUsesShellRoot(t *testing.T) {
	got := defaultMcpConfigPath("/tmp/shell")
	if got != "/tmp/shell/leftpanel/mcp_servers.json" {
		t.Fatalf("unexpected mcp path: %q", got)
	}
}

func TestParseOptionsRejectsNewConversationResumeConflict(t *testing.T) {
	if _, err := parseOptions([]string{"--message", "hi", "--new", "--conversation", "conv_1"}); err == nil {
		t.Fatalf("expected --new/--conversation conflict")
	}
}

func TestParseOptionsRejectsTempWithPersistentDBOptions(t *testing.T) {
	for _, args := range [][]string{
		{"--message", "hi", "--temp", "--db", "chat.sqlite"},
		{"--message", "hi", "--temp", "--conversation", "conv_1"},
	} {
		if _, err := parseOptions(args); err == nil {
			t.Fatalf("expected --temp conflict for args %#v", args)
		}
	}
}

func TestPrepareDatabasePathUsesTemporaryStore(t *testing.T) {
	opts := options{temp: true}

	cleanup, err := prepareDatabasePath(&opts)
	if err != nil {
		t.Fatalf("prepareDatabasePath: %v", err)
	}
	if opts.dbPath == "" || opts.dbPath == chatstore.DefaultPath() {
		t.Fatalf("expected isolated temporary db path, got %q", opts.dbPath)
	}
	if _, err := os.Stat(opts.dbPath); err != nil {
		t.Fatalf("temporary db should exist before cleanup: %v", err)
	}
	cleanup()
	if _, err := os.Stat(opts.dbPath); !os.IsNotExist(err) {
		t.Fatalf("temporary db should be removed after cleanup, got %v", err)
	}
}

func TestCanonicalModelIDMatchesLeftpanelDefaultRules(t *testing.T) {
	for _, tc := range []struct {
		raw  string
		want string
	}{
		{raw: "gpt-5.4-mini", want: "local/gpt-5.4-mini"},
		{raw: "gemini-2.5-flash", want: "gemini/gemini-2.5-flash"},
		{raw: "openai/gpt-5.5", want: "openai/gpt-5.5"},
	} {
		if got := canonicalModelID(tc.raw); got != tc.want {
			t.Fatalf("canonicalModelID(%q) = %q, want %q", tc.raw, got, tc.want)
		}
	}
}

func mustJSON(value any) string {
	data, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}
	return string(data)
}
