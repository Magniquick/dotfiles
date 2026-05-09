package chatstore

import (
	"database/sql"
	"os"
	"path/filepath"
	"testing"
)

func TestStoreMigratesAndPersistsSearchableMessages(t *testing.T) {
	store, err := Open(filepath.Join(t.TempDir(), "conversations.sqlite"))
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	defer store.Close()

	assertNoColumn(t, store.db, "messages", "show_header")

	conv, err := store.OpenConversation(OpenConversationOptions{
		ModelID:      "local/gpt-5.4-mini",
		ProviderID:   "local",
		MoodID:       "default",
		MoodName:     "Default",
		SystemPrompt: "be useful",
	})
	if err != nil {
		t.Fatalf("open conversation: %v", err)
	}

	msg := Message{
		ID:             "msg-user-1",
		ConversationID: conv.ID,
		Ordinal:        0,
		Sender:         "user",
		Kind:           "chat",
		Status:         "complete",
		Body:           "remember sqlite conversations",
	}
	if err := store.UpsertMessage(msg); err != nil {
		t.Fatalf("upsert message: %v", err)
	}

	var metricType string
	var metricValid int
	if err := store.db.QueryRow(`SELECT typeof(metrics), json_valid(metrics, 8) FROM messages WHERE id = ?`, msg.ID).Scan(&metricType, &metricValid); err != nil {
		t.Fatalf("query metrics jsonb: %v", err)
	}
	if metricType != "blob" || metricValid != 1 {
		t.Fatalf("metrics should be valid JSONB blob, got type=%q valid=%d", metricType, metricValid)
	}

	found, err := store.SearchMessages("sqlite")
	if err != nil {
		t.Fatalf("search messages: %v", err)
	}
	if len(found) != 1 || found[0].ID != msg.ID {
		t.Fatalf("expected searchable message %#v, got %#v", msg, found)
	}

	if err := store.MarkMessageDeleted(msg.ID); err != nil {
		t.Fatalf("mark deleted: %v", err)
	}
	found, err = store.SearchMessages("sqlite")
	if err != nil {
		t.Fatalf("search after delete: %v", err)
	}
	if len(found) != 0 {
		t.Fatalf("deleted message should be removed from FTS, got %#v", found)
	}
}

func TestToolCallsStoreStructuredJSONB(t *testing.T) {
	store, err := Open(filepath.Join(t.TempDir(), "conversations.sqlite"))
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	defer store.Close()

	conv, err := store.OpenConversation(OpenConversationOptions{ModelID: "local/gpt-5.4-mini"})
	if err != nil {
		t.Fatalf("open conversation: %v", err)
	}
	msg := Message{
		ID:             "tool-row-1",
		ConversationID: conv.ID,
		Ordinal:        0,
		Sender:         "tool",
		Kind:           "tool",
		Status:         "complete",
	}
	if err := store.UpsertMessage(msg); err != nil {
		t.Fatalf("upsert tool message: %v", err)
	}

	call := ToolCall{
		ID:          "tool-row-1",
		MessageID:   msg.ID,
		ToolCallID:  "call-1",
		ToolName:    "email_search",
		Phase:       "tool_done",
		Status:      "success",
		Summary:     "searched mail",
		Subtitle:    "2 matches",
		PayloadJSON: `{"detail_sections":[{"title":"Result","content":"ok"}]}`,
	}
	if err := store.UpsertToolCall(call); err != nil {
		t.Fatalf("upsert tool call: %v", err)
	}

	var toolName string
	var firstDetail string
	var valid int
	if err := store.db.QueryRow(`
		SELECT tool_name, json_extract(payload, '$.detail_sections[0].content'), json_valid(payload, 8)
		FROM tool_calls
		WHERE tool_call_id = ?`, call.ToolCallID).Scan(&toolName, &firstDetail, &valid); err != nil {
		t.Fatalf("query tool call: %v", err)
	}
	if toolName != "email_search" || firstDetail != "ok" || valid != 1 {
		t.Fatalf("unexpected tool call projection: tool=%q detail=%q valid=%d", toolName, firstDetail, valid)
	}
}

func TestStoreFileIsPrivate(t *testing.T) {
	path := filepath.Join(t.TempDir(), "conversations.sqlite")
	store, err := Open(path)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	if err := store.Close(); err != nil {
		t.Fatalf("close store: %v", err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat store: %v", err)
	}
	if got := info.Mode().Perm(); got != 0o600 {
		t.Fatalf("store permissions = %o, want 600", got)
	}
}

func assertNoColumn(t *testing.T, db *sql.DB, table string, column string) {
	t.Helper()
	rows, err := db.Query(`SELECT name FROM pragma_table_info(?)`, table)
	if err != nil {
		t.Fatalf("pragma table info: %v", err)
	}
	defer rows.Close()
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			t.Fatalf("scan column: %v", err)
		}
		if name == column {
			t.Fatalf("table %s unexpectedly has column %s", table, column)
		}
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("columns rows: %v", err)
	}
}
