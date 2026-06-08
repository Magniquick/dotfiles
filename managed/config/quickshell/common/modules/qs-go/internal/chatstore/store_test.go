package chatstore

import (
	"database/sql"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestStoreMigratesAndPersistsSearchableMessages(t *testing.T) {
	store, err := Open(filepath.Join(t.TempDir(), "conversations.sqlite"))
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	defer func() {
		_ = store.Close()
	}()

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
	if err := store.db.QueryRowContext(t.Context(), `SELECT typeof(metrics), json_valid(metrics, 8) FROM messages WHERE id = ?`, msg.ID).Scan(&metricType, &metricValid); err != nil {
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
	defer func() {
		_ = store.Close()
	}()

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
	if err := store.db.QueryRowContext(t.Context(), `
		SELECT tool_name, json_extract(payload, '$.detail_sections[0].content'), json_valid(payload, 8)
		FROM tool_calls
		WHERE tool_call_id = ?`, call.ToolCallID).Scan(&toolName, &firstDetail, &valid); err != nil {
		t.Fatalf("query tool call: %v", err)
	}
	if toolName != "email_search" || firstDetail != "ok" || valid != 1 {
		t.Fatalf("unexpected tool call projection: tool=%q detail=%q valid=%d", toolName, firstDetail, valid)
	}
}

func TestResponseItemsStoreRawLedgerAndDeleteWithTurn(t *testing.T) {
	store, err := Open(filepath.Join(t.TempDir(), "conversations.sqlite"))
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	defer func() {
		_ = store.Close()
	}()

	var versionSeen int
	if err := store.db.QueryRowContext(t.Context(), `SELECT count(*) FROM schema_migrations WHERE version = 2`).Scan(&versionSeen); err != nil {
		t.Fatalf("query migration version: %v", err)
	}
	if versionSeen != 1 {
		t.Fatalf("migration version 2 not recorded")
	}

	conv, err := store.OpenConversation(OpenConversationOptions{ModelID: "local/gpt-5.4-mini"})
	if err != nil {
		t.Fatalf("open conversation: %v", err)
	}
	user := Message{
		ID:             "turn-user-1",
		ConversationID: conv.ID,
		Ordinal:        0,
		Sender:         "user",
		Kind:           "chat",
		Status:         "complete",
		Body:           "use tools",
	}
	if err := store.UpsertMessage(user); err != nil {
		t.Fatalf("upsert user: %v", err)
	}

	items := []ResponseItem{
		{Source: "model_output", RawJSON: `{"type":"function_call","call_id":"call_1","name":"email_search","arguments":"{}"}`},
		{Source: "tool_output", RawJSON: `{"type":"function_call_output","call_id":"call_1","output":"{\"result\":\"ok\"}"}`},
		{Source: "model_output", RawJSON: `{"type":"message","content":[{"type":"output_text","text":"done"}]}`},
	}
	if err := store.UpsertResponseItems(conv.ID, user.ID, user.Ordinal, items); err != nil {
		t.Fatalf("upsert response items: %v", err)
	}

	listed, err := store.ListResponseItems(conv.ID)
	if err != nil {
		t.Fatalf("list response items: %v", err)
	}
	if len(listed) != 3 {
		t.Fatalf("listed response item count = %d, want 3: %#v", len(listed), listed)
	}
	if listed[0].TurnID != user.ID || listed[0].TurnOrdinal != user.Ordinal || listed[0].ItemOrdinal != 0 {
		t.Fatalf("unexpected first ledger coordinates: %#v", listed[0])
	}
	if listed[0].ItemType != "function_call" || listed[0].CallID != "call_1" || listed[0].Source != "model_output" {
		t.Fatalf("first ledger metadata not derived from raw item: %#v", listed[0])
	}
	if listed[1].ItemType != "function_call_output" || listed[1].Source != "tool_output" {
		t.Fatalf("tool output ledger metadata wrong: %#v", listed[1])
	}
	var raw map[string]any
	if err := json.Unmarshal([]byte(listed[2].RawJSON), &raw); err != nil {
		t.Fatalf("raw message item should remain JSON: %v", err)
	}
	if raw["type"] != "message" {
		t.Fatalf("expected raw message item, got %#v", raw)
	}

	if err := store.DeleteFromOrdinal(conv.ID, user.Ordinal); err != nil {
		t.Fatalf("delete from ordinal: %v", err)
	}
	listed, err = store.ListResponseItems(conv.ID)
	if err != nil {
		t.Fatalf("list after delete: %v", err)
	}
	if len(listed) != 0 {
		t.Fatalf("ledger rows should be deleted with turn, got %#v", listed)
	}
}

func TestMigrationBackfillsResponseItemsFromAgentPayload(t *testing.T) {
	path := filepath.Join(t.TempDir(), "conversations.sqlite")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatalf("open raw db: %v", err)
	}
	if _, err := db.ExecContext(t.Context(), `
		CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, name TEXT NOT NULL, applied_at TEXT NOT NULL DEFAULT '');
		CREATE TABLE conversations (
			id TEXT PRIMARY KEY,
			title TEXT NOT NULL DEFAULT '',
			model_id TEXT NOT NULL,
			provider_id TEXT NOT NULL DEFAULT '',
			mood_id TEXT NOT NULL DEFAULT '',
			mood_name TEXT NOT NULL DEFAULT '',
			system_prompt TEXT NOT NULL DEFAULT '',
			status TEXT NOT NULL DEFAULT 'active',
			created_at TEXT NOT NULL DEFAULT '',
			updated_at TEXT NOT NULL DEFAULT '',
			closed_at TEXT,
			deleted_at TEXT
		);
		CREATE TABLE messages (
			id TEXT PRIMARY KEY,
			conversation_id TEXT NOT NULL,
			ordinal INTEGER NOT NULL,
			sender TEXT NOT NULL,
			kind TEXT NOT NULL,
			status TEXT NOT NULL DEFAULT 'complete',
			body TEXT NOT NULL DEFAULT '',
			metrics BLOB NOT NULL DEFAULT (jsonb('{}')) CHECK (json_valid(metrics, 8)),
			extra BLOB NOT NULL DEFAULT (jsonb('{}')) CHECK (json_valid(extra, 8)),
			created_at TEXT NOT NULL DEFAULT '',
			updated_at TEXT,
			completed_at TEXT,
			deleted_at TEXT
		);
		CREATE TABLE tool_calls (
			id TEXT PRIMARY KEY,
			message_id TEXT NOT NULL,
			tool_call_id TEXT NOT NULL,
			tool_name TEXT NOT NULL,
			phase TEXT NOT NULL,
			status TEXT NOT NULL,
			is_error INTEGER NOT NULL DEFAULT 0,
			summary TEXT NOT NULL DEFAULT '',
			subtitle TEXT NOT NULL DEFAULT '',
			payload BLOB NOT NULL DEFAULT (jsonb('{}')) CHECK (json_valid(payload, 8)),
			created_at TEXT NOT NULL DEFAULT '',
			updated_at TEXT
		);
		INSERT INTO schema_migrations(version, name) VALUES (1, 'initial_conversation_store');
		INSERT INTO conversations(id, model_id, status, created_at, updated_at) VALUES ('conv_1', 'local/gpt-5.4-mini', 'active', 't0', 't0');
		INSERT INTO messages(id, conversation_id, ordinal, sender, kind, status, body, metrics, extra, created_at)
		VALUES ('user_1', 'conv_1', 0, 'user', 'chat', 'complete', 'find mail', jsonb('{}'), jsonb('{}'), 't0');
		INSERT INTO messages(id, conversation_id, ordinal, sender, kind, status, body, metrics, extra, created_at)
		VALUES ('tool_msg_1', 'conv_1', 1, 'tool', 'tool', 'complete', '', jsonb('{}'), jsonb('{}'), 't1');
	`); err != nil {
		_ = db.Close()
		t.Fatalf("seed old schema: %v", err)
	}
	payload := map[string]any{
		"agent_payload": mustJSON([]map[string]any{
			{"type": "function_call", "call_id": "call_email", "name": "email_search", "arguments": "{}"},
			{"type": "function_call_output", "call_id": "call_email", "output": "1 result"},
		}),
	}
	if _, err := db.ExecContext(t.Context(), `
		INSERT INTO tool_calls(id, message_id, tool_call_id, tool_name, phase, status, payload, created_at)
		VALUES ('call_email', 'tool_msg_1', 'call_email', 'email_search', 'tool_done', 'success', jsonb(?), 't1')`,
		mustJSON(payload)); err != nil {
		_ = db.Close()
		t.Fatalf("insert old tool call: %v", err)
	}
	if err := db.Close(); err != nil {
		t.Fatalf("close raw db: %v", err)
	}

	store, err := Open(path)
	if err != nil {
		t.Fatalf("migrate store: %v", err)
	}
	defer func() {
		_ = store.Close()
	}()

	listed, err := store.ListResponseItems("conv_1")
	if err != nil {
		t.Fatalf("list response items: %v", err)
	}
	if len(listed) != 2 {
		t.Fatalf("backfilled response item count = %d, want 2: %#v", len(listed), listed)
	}
	if listed[0].TurnID != "user_1" || listed[0].TurnOrdinal != 0 {
		t.Fatalf("backfill should attach to preceding user turn, got %#v", listed[0])
	}
	if listed[0].Source != "model_output" || listed[1].Source != "tool_output" {
		t.Fatalf("backfill sources wrong: %#v", listed)
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
	rows, err := db.QueryContext(t.Context(), `SELECT name FROM pragma_table_info(?)`, table)
	if err != nil {
		t.Fatalf("pragma table info: %v", err)
	}
	defer closeRows(rows)
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

func mustJSON(value any) string {
	data, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}
	return string(data)
}
