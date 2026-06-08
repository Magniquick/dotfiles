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

func TestApplyJSONResponseItemsLifecycle(t *testing.T) {
	path := filepath.Join(t.TempDir(), "conversations.sqlite")

	openResult := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "open_conversation",
		"model_id": "local/gpt-5.4-mini",
		"provider_id": "local"
	}`))
	if !openResult.OK || openResult.Conversation.ID == "" {
		t.Fatalf("open failed: %#v", openResult)
	}
	if result := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "upsert_message",
		"message": {
			"id": "turn-api-1",
			"conversation_id": "`+openResult.Conversation.ID+`",
			"ordinal": 0,
			"sender": "user",
			"kind": "chat",
			"status": "complete",
			"body": "search"
		}
	}`)); !result.OK {
		t.Fatalf("upsert user failed: %#v", result)
	}

	upsertRaw := ApplyJSONWithPath(path, `{
		"action": "upsert_response_items",
		"conversation_id": "`+openResult.Conversation.ID+`",
		"turn_id": "turn-api-1",
		"turn_ordinal": 0,
		"response_items": [
			{
				"source": "model_output",
				"raw": {"type":"web_search_call","id":"ws_1","status":"completed"}
			},
			{
				"source": "model_output",
				"raw": {"type":"message","content":[{"type":"output_text","text":"done"}]}
			}
		]
	}`)
	if result := decodeAPIResult(t, upsertRaw); !result.OK {
		t.Fatalf("upsert response items failed: %s", upsertRaw)
	}

	listRaw := ApplyJSONWithPath(path, `{
		"action": "list_response_items",
		"conversation_id": "`+openResult.Conversation.ID+`"
	}`)
	listResult := decodeAPIResult(t, listRaw)
	if !listResult.OK || len(listResult.ResponseItems) != 2 {
		t.Fatalf("list response items failed: %s", listRaw)
	}
	if listResult.ResponseItems[0].ItemType != "web_search_call" || listResult.ResponseItems[1].ItemType != "message" {
		t.Fatalf("unexpected response item metadata: %#v", listResult.ResponseItems)
	}
}

func TestApplyJSONRestoreDoesNotCreateBlankConversation(t *testing.T) {
	path := filepath.Join(t.TempDir(), "conversations.sqlite")

	restoreRaw := ApplyJSONWithPath(path, `{
		"action": "restore_conversation",
		"model_id": "local/gpt-5.4-mini",
		"provider_id": "local"
	}`)
	restore := decodeAPIResult(t, restoreRaw)
	if !restore.OK || restore.Conversation.ID != "" {
		t.Fatalf("restore should succeed without creating a conversation: %s", restoreRaw)
	}

	store, err := Open(path)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	defer func() {
		_ = store.Close()
	}()
	var count int
	if err := store.db.QueryRowContext(t.Context(), `SELECT count(*) FROM conversations`).Scan(&count); err != nil {
		t.Fatalf("count conversations: %v", err)
	}
	if count != 0 {
		t.Fatalf("restore created %d conversations, want 0", count)
	}
}

func TestCreateConversationClosesPreviousActiveConversation(t *testing.T) {
	path := filepath.Join(t.TempDir(), "conversations.sqlite")

	first := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "create_conversation",
		"model_id": "local/gpt-5.4-mini",
		"provider_id": "local"
	}`))
	if !first.OK || first.Conversation.ID == "" {
		t.Fatalf("create first conversation failed: %#v", first)
	}

	second := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "create_conversation",
		"model_id": "local/gpt-5.4-mini",
		"provider_id": "local"
	}`))
	if !second.OK || second.Conversation.ID == "" || second.Conversation.ID == first.Conversation.ID {
		t.Fatalf("create second conversation failed: %#v", second)
	}

	store, err := Open(path)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	defer func() {
		_ = store.Close()
	}()
	var firstStatus, secondStatus string
	if err := store.db.QueryRowContext(t.Context(), `SELECT status FROM conversations WHERE id = ?`, first.Conversation.ID).Scan(&firstStatus); err != nil {
		t.Fatalf("query first status: %v", err)
	}
	if err := store.db.QueryRowContext(t.Context(), `SELECT status FROM conversations WHERE id = ?`, second.Conversation.ID).Scan(&secondStatus); err != nil {
		t.Fatalf("query second status: %v", err)
	}
	if firstStatus != "closed" || secondStatus != "active" {
		t.Fatalf("statuses = first:%q second:%q, want closed/active", firstStatus, secondStatus)
	}
}

func TestApplyJSONResumesLatestClosedConversation(t *testing.T) {
	path := filepath.Join(t.TempDir(), "conversations.sqlite")

	first := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "create_conversation",
		"model_id": "local/gpt-5.4-mini",
		"provider_id": "local"
	}`))
	if !first.OK || first.Conversation.ID == "" {
		t.Fatalf("create first conversation failed: %#v", first)
	}
	if result := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "upsert_message",
		"message": {
			"id": "old-msg",
			"conversation_id": "`+first.Conversation.ID+`",
			"ordinal": 0,
			"sender": "user",
			"kind": "chat",
			"status": "complete",
			"body": "resume this"
		}
	}`)); !result.OK {
		t.Fatalf("upsert first message failed: %#v", result)
	}
	if result := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "close_conversation",
		"conversation_id": "`+first.Conversation.ID+`"
	}`)); !result.OK {
		t.Fatalf("close first conversation failed: %#v", result)
	}

	second := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "create_conversation",
		"model_id": "local/gpt-5.4-mini",
		"provider_id": "local"
	}`))
	if !second.OK || second.Conversation.ID == "" || second.Conversation.ID == first.Conversation.ID {
		t.Fatalf("create second conversation failed: %#v", second)
	}

	resumed := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "resume_conversation",
		"model_id": "local/gpt-5.4-mini",
		"current_conversation_id": "`+second.Conversation.ID+`"
	}`))
	if !resumed.OK {
		t.Fatalf("resume failed: %#v", resumed)
	}
	if resumed.Conversation.ID != first.Conversation.ID {
		t.Fatalf("resumed conversation = %q, want %q", resumed.Conversation.ID, first.Conversation.ID)
	}
	if len(resumed.Messages) != 1 || resumed.Messages[0].Body != "resume this" {
		t.Fatalf("resumed messages = %#v", resumed.Messages)
	}
}

func TestApplyJSONListsResumeConversationsByClosedTimeAndSearch(t *testing.T) {
	path := filepath.Join(t.TempDir(), "conversations.sqlite")

	first := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "create_conversation",
		"model_id": "local/gpt-5.4-mini",
		"provider_id": "local"
	}`))
	if !first.OK || first.Conversation.ID == "" {
		t.Fatalf("create first conversation failed: %#v", first)
	}
	if result := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "upsert_message",
		"message": {
			"id": "legacy-msg",
			"conversation_id": "`+first.Conversation.ID+`",
			"ordinal": 0,
			"sender": "user",
			"kind": "chat",
			"status": "complete",
			"body": "older sqlite chat"
		}
	}`)); !result.OK {
		t.Fatalf("upsert first message failed: %#v", result)
	}
	if result := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "close_conversation",
		"conversation_id": "`+first.Conversation.ID+`"
	}`)); !result.OK {
		t.Fatalf("close first conversation failed: %#v", result)
	}

	second := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "create_conversation",
		"model_id": "local/gpt-5.4-mini",
		"provider_id": "local"
	}`))
	if !second.OK || second.Conversation.ID == "" || second.Conversation.ID == first.Conversation.ID {
		t.Fatalf("create second conversation failed: %#v", second)
	}
	if result := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "upsert_message",
		"message": {
			"id": "newer-msg",
			"conversation_id": "`+second.Conversation.ID+`",
			"ordinal": 0,
			"sender": "user",
			"kind": "chat",
			"status": "complete",
			"body": "newer resume needle"
		}
	}`)); !result.OK {
		t.Fatalf("upsert second message failed: %#v", result)
	}
	if result := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "close_conversation",
		"conversation_id": "`+second.Conversation.ID+`"
	}`)); !result.OK {
		t.Fatalf("close second conversation failed: %#v", result)
	}

	store, err := Open(path)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	if _, err := store.db.ExecContext(t.Context(), `UPDATE conversations SET closed_at = ?, updated_at = ? WHERE id = ?`, "2026-05-01T00:00:00.000Z", "2026-05-01T00:00:00.000Z", first.Conversation.ID); err != nil {
		_ = store.Close()
		t.Fatalf("set first time: %v", err)
	}
	if _, err := store.db.ExecContext(t.Context(), `UPDATE conversations SET closed_at = ?, updated_at = ? WHERE id = ?`, "2026-05-02T00:00:00.000Z", "2026-05-02T00:00:00.000Z", second.Conversation.ID); err != nil {
		_ = store.Close()
		t.Fatalf("set second time: %v", err)
	}
	if err := store.Close(); err != nil {
		t.Fatalf("close store: %v", err)
	}

	listed := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "list_resume_conversations",
		"model_id": "local/gpt-5.4-mini"
	}`))
	if !listed.OK {
		t.Fatalf("list failed: %#v", listed)
	}
	if len(listed.Conversations) != 2 {
		t.Fatalf("listed conversations = %#v", listed.Conversations)
	}
	if listed.Conversations[0].ID != second.Conversation.ID || listed.Conversations[1].ID != first.Conversation.ID {
		t.Fatalf("conversation order = %#v, want newest closed first", listed.Conversations)
	}

	filtered := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "list_resume_conversations",
		"model_id": "local/gpt-5.4-mini",
		"query": "older"
	}`))
	if !filtered.OK || len(filtered.Conversations) != 1 || filtered.Conversations[0].ID != first.Conversation.ID {
		t.Fatalf("filtered conversations = %#v", filtered.Conversations)
	}

	current := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "create_conversation",
		"model_id": "local/gpt-5.4-mini",
		"provider_id": "local"
	}`))
	if !current.OK || current.Conversation.ID == "" {
		t.Fatalf("create current conversation failed: %#v", current)
	}

	selected := decodeAPIResult(t, ApplyJSONWithPath(path, `{
		"action": "resume_conversation",
		"model_id": "local/gpt-5.4-mini",
		"current_conversation_id": "`+current.Conversation.ID+`",
		"conversation_id": "`+first.Conversation.ID+`"
	}`))
	if !selected.OK {
		t.Fatalf("selected resume failed: %#v", selected)
	}
	if selected.Conversation.ID != first.Conversation.ID {
		t.Fatalf("selected conversation = %q, want %q", selected.Conversation.ID, first.Conversation.ID)
	}
	if len(selected.Messages) != 1 || selected.Messages[0].Body != "older sqlite chat" {
		t.Fatalf("selected messages = %#v", selected.Messages)
	}
}

type apiTestResult struct {
	OK            bool                  `json:"ok"`
	Error         string                `json:"error"`
	Conversation  Conversation          `json:"conversation"`
	Conversations []ConversationSummary `json:"conversations"`
	Messages      []Message             `json:"messages"`
	ResponseItems []ResponseItem        `json:"response_items"`
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
