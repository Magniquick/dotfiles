package chatstore

import (
	"encoding/json"
	"path/filepath"
	"testing"
)

func TestApplyJSONConversationMessageLifecycle(t *testing.T) {
	path := filepath.Join(t.TempDir(), "conversations.sqlite")

	openRaw := ApplyJSONWithPath(path, `{
		"action": "open_conversation",
		"model_id": "local/gpt-5.4-mini",
		"provider_id": "local"
	}`)
	openResult := decodeAPIResult(t, openRaw)
	if !openResult.OK || openResult.Conversation.ID == "" {
		t.Fatalf("open failed: %s", openRaw)
	}

	upsertRaw := ApplyJSONWithPath(path, `{
		"action": "upsert_message",
		"message": {
			"id": "msg-1",
			"conversation_id": "`+openResult.Conversation.ID+`",
			"ordinal": 0,
			"sender": "assistant",
			"kind": "chat",
			"status": "complete",
			"body": "stored response",
			"metrics_json": {"model":"local/gpt-5.4-mini","total_ms":42}
		}
	}`)
	if result := decodeAPIResult(t, upsertRaw); !result.OK {
		t.Fatalf("upsert failed: %s", upsertRaw)
	}

	listRaw := ApplyJSONWithPath(path, `{
		"action": "list_messages",
		"conversation_id": "`+openResult.Conversation.ID+`"
	}`)
	listResult := decodeAPIResult(t, listRaw)
	if !listResult.OK || len(listResult.Messages) != 1 {
		t.Fatalf("list failed: %s", listRaw)
	}
	if listResult.Messages[0].Body != "stored response" || listResult.Messages[0].MetricsJSON == "" {
		t.Fatalf("unexpected listed message: %#v", listResult.Messages[0])
	}

	deleteRaw := ApplyJSONWithPath(path, `{
		"action": "delete_from_ordinal",
		"conversation_id": "`+openResult.Conversation.ID+`",
		"ordinal": 0
	}`)
	if result := decodeAPIResult(t, deleteRaw); !result.OK {
		t.Fatalf("delete suffix failed: %s", deleteRaw)
	}

	listRaw = ApplyJSONWithPath(path, `{
		"action": "list_messages",
		"conversation_id": "`+openResult.Conversation.ID+`"
	}`)
	listResult = decodeAPIResult(t, listRaw)
	if !listResult.OK || len(listResult.Messages) != 0 {
		t.Fatalf("deleted messages should not be listed: %s", listRaw)
	}
}

type apiTestResult struct {
	OK           bool         `json:"ok"`
	Error        string       `json:"error"`
	Conversation Conversation `json:"conversation"`
	Messages     []Message    `json:"messages"`
}

func decodeAPIResult(t *testing.T, raw string) apiTestResult {
	t.Helper()
	var result apiTestResult
	if err := json.Unmarshal([]byte(raw), &result); err != nil {
		t.Fatalf("decode %q: %v", raw, err)
	}
	if result.Error != "" {
		t.Logf("api error: %s", result.Error)
	}
	return result
}
