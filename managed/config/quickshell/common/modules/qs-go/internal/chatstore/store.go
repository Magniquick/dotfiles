// Package chatstore persists leftpanel conversations in a local SQLite database.
package chatstore

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

const migrationVersion = 1

type Store struct {
	db *sql.DB
}

type OpenConversationOptions struct {
	ModelID      string
	ProviderID   string
	MoodID       string
	MoodName     string
	SystemPrompt string
}

type Conversation struct {
	ID           string `json:"id"`
	Title        string `json:"title"`
	ModelID      string `json:"model_id"`
	ProviderID   string `json:"provider_id"`
	MoodID       string `json:"mood_id"`
	MoodName     string `json:"mood_name"`
	SystemPrompt string `json:"system_prompt"`
	Status       string `json:"status"`
	CreatedAt    string `json:"created_at"`
	UpdatedAt    string `json:"updated_at"`
}

type Message struct {
	ID             string     `json:"id"`
	ConversationID string     `json:"conversation_id"`
	Ordinal        int        `json:"ordinal"`
	Sender         string     `json:"sender"`
	Kind           string     `json:"kind"`
	Status         string     `json:"status"`
	Body           string     `json:"body"`
	MetricsJSON    string     `json:"metrics_json,omitempty"`
	ExtraJSON      string     `json:"extra_json,omitempty"`
	CreatedAt      string     `json:"created_at,omitempty"`
	UpdatedAt      string     `json:"updated_at,omitempty"`
	CompletedAt    string     `json:"completed_at,omitempty"`
	DeletedAt      string     `json:"deleted_at,omitempty"`
	ToolCalls      []ToolCall `json:"tool_calls,omitempty"`
}

type ToolCall struct {
	ID          string `json:"id"`
	MessageID   string `json:"message_id"`
	ToolCallID  string `json:"tool_call_id"`
	ToolName    string `json:"tool_name"`
	Phase       string `json:"phase"`
	Status      string `json:"status"`
	IsError     bool   `json:"is_error"`
	Summary     string `json:"summary"`
	Subtitle    string `json:"subtitle"`
	PayloadJSON string `json:"payload_json,omitempty"`
	CreatedAt   string `json:"created_at,omitempty"`
	UpdatedAt   string `json:"updated_at,omitempty"`
}

func DefaultPath() string {
	dataHome := strings.TrimSpace(os.Getenv("XDG_DATA_HOME"))
	if dataHome == "" {
		if home, err := os.UserHomeDir(); err == nil && strings.TrimSpace(home) != "" {
			dataHome = filepath.Join(home, ".local", "share")
		}
	}
	if dataHome == "" {
		dataHome = "."
	}
	return filepath.Join(dataHome, "quickshell", "leftpanel", "conversations.sqlite")
}

func Open(path string) (*Store, error) {
	path = strings.TrimSpace(path)
	if path == "" {
		path = DefaultPath()
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	store := &Store{db: db}
	if err := store.configure(); err != nil {
		_ = db.Close()
		return nil, err
	}
	if err := store.migrate(); err != nil {
		_ = db.Close()
		return nil, err
	}
	if err := secureFiles(path); err != nil {
		_ = db.Close()
		return nil, err
	}
	return store, nil
}

func (s *Store) Close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

func (s *Store) OpenConversation(opts OpenConversationOptions) (Conversation, error) {
	if s == nil || s.db == nil {
		return Conversation{}, errors.New("chat store is not open")
	}
	if conv, ok, err := s.activeConversation(opts); err != nil {
		return Conversation{}, err
	} else if ok {
		return conv, nil
	}
	return s.CreateConversation(opts)
}

func (s *Store) CreateConversation(opts OpenConversationOptions) (Conversation, error) {
	now := timestamp()
	conv := Conversation{
		ID:           newID(),
		ModelID:      strings.TrimSpace(opts.ModelID),
		ProviderID:   strings.TrimSpace(opts.ProviderID),
		MoodID:       strings.TrimSpace(opts.MoodID),
		MoodName:     strings.TrimSpace(opts.MoodName),
		SystemPrompt: strings.TrimSpace(opts.SystemPrompt),
		Status:       "active",
		CreatedAt:    now,
		UpdatedAt:    now,
	}
	if conv.ModelID == "" {
		conv.ModelID = "local/gpt-5.4-mini"
	}
	if _, err := s.db.Exec(`
		INSERT INTO conversations (
			id, model_id, provider_id, mood_id, mood_name, system_prompt, status, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		conv.ID, conv.ModelID, conv.ProviderID, conv.MoodID, conv.MoodName, conv.SystemPrompt,
		conv.Status, conv.CreatedAt, conv.UpdatedAt); err != nil {
		return Conversation{}, err
	}
	return conv, nil
}

func (s *Store) CloseConversation(id string) error {
	id = strings.TrimSpace(id)
	if id == "" {
		return nil
	}
	now := timestamp()
	_, err := s.db.Exec(`
		UPDATE conversations
		SET status = 'closed', closed_at = ?, updated_at = ?
		WHERE id = ? AND status = 'active'`, now, now, id)
	return err
}

func (s *Store) UpsertMessage(msg Message) error {
	if strings.TrimSpace(msg.ID) == "" {
		return errors.New("message id is required")
	}
	if strings.TrimSpace(msg.ConversationID) == "" {
		return errors.New("conversation id is required")
	}
	if msg.Status == "" {
		msg.Status = "complete"
	}
	if msg.CreatedAt == "" {
		msg.CreatedAt = timestamp()
	}
	metrics := jsonText(msg.MetricsJSON)
	extra := jsonText(msg.ExtraJSON)
	_, err := s.db.Exec(`
		INSERT INTO messages (
			id, conversation_id, ordinal, sender, kind, status, body,
			metrics, extra, created_at, updated_at, completed_at, deleted_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, jsonb(?), jsonb(?), ?, nullif(?, ''), nullif(?, ''), nullif(?, ''))
		ON CONFLICT(id) DO UPDATE SET
			conversation_id = excluded.conversation_id,
			ordinal = excluded.ordinal,
			sender = excluded.sender,
			kind = excluded.kind,
			status = excluded.status,
			body = excluded.body,
			metrics = excluded.metrics,
			extra = excluded.extra,
			updated_at = excluded.updated_at,
			completed_at = excluded.completed_at,
			deleted_at = excluded.deleted_at`,
		msg.ID, msg.ConversationID, msg.Ordinal, msg.Sender, msg.Kind, msg.Status, msg.Body,
		metrics, extra, msg.CreatedAt, msg.UpdatedAt, msg.CompletedAt, msg.DeletedAt)
	if err != nil {
		return err
	}
	return s.touchConversation(msg.ConversationID)
}

func (s *Store) MarkMessageDeleted(id string) error {
	id = strings.TrimSpace(id)
	if id == "" {
		return nil
	}
	now := timestamp()
	var convID string
	err := s.db.QueryRow(`SELECT conversation_id FROM messages WHERE id = ?`, id).Scan(&convID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	if _, err := s.db.Exec(`
		UPDATE messages
		SET status = 'deleted', updated_at = ?, deleted_at = ?
		WHERE id = ?`, now, now, id); err != nil {
		return err
	}
	return s.touchConversation(convID)
}

func (s *Store) DeleteFromOrdinal(conversationID string, ordinal int) error {
	conversationID = strings.TrimSpace(conversationID)
	if conversationID == "" {
		return nil
	}
	now := timestamp()
	if _, err := s.db.Exec(`
		UPDATE messages
		SET status = 'deleted', updated_at = ?, deleted_at = ?
		WHERE conversation_id = ? AND ordinal >= ? AND status != 'deleted'`,
		now, now, conversationID, ordinal); err != nil {
		return err
	}
	return s.touchConversation(conversationID)
}

func (s *Store) UpsertToolCall(call ToolCall) error {
	if strings.TrimSpace(call.ID) == "" {
		return errors.New("tool call row id is required")
	}
	if strings.TrimSpace(call.MessageID) == "" {
		return errors.New("tool call message id is required")
	}
	if strings.TrimSpace(call.ToolCallID) == "" {
		return errors.New("tool call id is required")
	}
	if call.CreatedAt == "" {
		call.CreatedAt = timestamp()
	}
	payload := jsonText(call.PayloadJSON)
	_, err := s.db.Exec(`
		INSERT INTO tool_calls (
			id, message_id, tool_call_id, tool_name, phase, status, is_error,
			summary, subtitle, payload, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, jsonb(?), ?, nullif(?, ''))
		ON CONFLICT(message_id, tool_call_id) DO UPDATE SET
			tool_name = excluded.tool_name,
			phase = excluded.phase,
			status = excluded.status,
			is_error = excluded.is_error,
			summary = excluded.summary,
			subtitle = excluded.subtitle,
			payload = excluded.payload,
			updated_at = excluded.updated_at`,
		call.ID, call.MessageID, call.ToolCallID, call.ToolName, call.Phase, call.Status,
		boolInt(call.IsError), call.Summary, call.Subtitle, payload, call.CreatedAt, call.UpdatedAt)
	return err
}

func (s *Store) SearchMessages(query string) ([]Message, error) {
	rows, err := s.db.Query(`
		SELECT m.id, m.conversation_id, m.ordinal, m.sender, m.kind, m.status, m.body
		FROM message_fts f
		JOIN messages m ON m.id = f.message_id
		WHERE message_fts MATCH ?
		ORDER BY m.created_at DESC`, strings.TrimSpace(query))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Message
	for rows.Next() {
		var msg Message
		if err := rows.Scan(&msg.ID, &msg.ConversationID, &msg.Ordinal, &msg.Sender, &msg.Kind, &msg.Status, &msg.Body); err != nil {
			return nil, err
		}
		out = append(out, msg)
	}
	return out, rows.Err()
}

func (s *Store) ListMessages(conversationID string) ([]Message, error) {
	rows, err := s.db.Query(`
		SELECT
			id, conversation_id, ordinal, sender, kind, status, body,
			json(metrics), json(extra), created_at, coalesce(updated_at, ''),
			coalesce(completed_at, ''), coalesce(deleted_at, '')
		FROM messages
		WHERE conversation_id = ? AND status != 'deleted'
		ORDER BY ordinal ASC`, strings.TrimSpace(conversationID))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Message
	for rows.Next() {
		var msg Message
		if err := rows.Scan(
			&msg.ID, &msg.ConversationID, &msg.Ordinal, &msg.Sender, &msg.Kind, &msg.Status, &msg.Body,
			&msg.MetricsJSON, &msg.ExtraJSON, &msg.CreatedAt, &msg.UpdatedAt, &msg.CompletedAt, &msg.DeletedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, msg)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for i := range out {
		calls, err := s.listToolCalls(out[i].ID)
		if err != nil {
			return nil, err
		}
		out[i].ToolCalls = calls
	}
	return out, nil
}

func (s *Store) configure() error {
	if _, err := s.db.Exec(`PRAGMA foreign_keys = ON`); err != nil {
		return err
	}
	if _, err := s.db.Exec(`PRAGMA journal_mode = WAL`); err != nil {
		return err
	}
	return nil
}

func (s *Store) migrate() error {
	if _, err := s.db.Exec(schemaSQL); err != nil {
		return err
	}
	_, err := s.db.Exec(`INSERT OR IGNORE INTO schema_migrations(version, name) VALUES (?, ?)`, migrationVersion, "initial_conversation_store")
	return err
}

func (s *Store) activeConversation(opts OpenConversationOptions) (Conversation, bool, error) {
	var conv Conversation
	modelID := strings.TrimSpace(opts.ModelID)
	if modelID == "" {
		modelID = "local/gpt-5.4-mini"
	}
	err := s.db.QueryRow(`
		SELECT id, title, model_id, provider_id, mood_id, mood_name, system_prompt, status, created_at, updated_at
		FROM conversations
		WHERE status = 'active' AND model_id = ?
		ORDER BY updated_at DESC
		LIMIT 1`, modelID).Scan(&conv.ID, &conv.Title, &conv.ModelID, &conv.ProviderID, &conv.MoodID, &conv.MoodName, &conv.SystemPrompt, &conv.Status, &conv.CreatedAt, &conv.UpdatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return Conversation{}, false, nil
	}
	if err != nil {
		return Conversation{}, false, err
	}
	return conv, true, nil
}

func (s *Store) listToolCalls(messageID string) ([]ToolCall, error) {
	rows, err := s.db.Query(`
		SELECT
			id, message_id, tool_call_id, tool_name, phase, status, is_error,
			summary, subtitle, json(payload), created_at, coalesce(updated_at, '')
		FROM tool_calls
		WHERE message_id = ?
		ORDER BY created_at ASC`, strings.TrimSpace(messageID))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ToolCall
	for rows.Next() {
		var call ToolCall
		var isError int
		if err := rows.Scan(
			&call.ID, &call.MessageID, &call.ToolCallID, &call.ToolName, &call.Phase, &call.Status,
			&isError, &call.Summary, &call.Subtitle, &call.PayloadJSON, &call.CreatedAt, &call.UpdatedAt,
		); err != nil {
			return nil, err
		}
		call.IsError = isError != 0
		out = append(out, call)
	}
	return out, rows.Err()
}

func (s *Store) touchConversation(id string) error {
	if strings.TrimSpace(id) == "" {
		return nil
	}
	_, err := s.db.Exec(`UPDATE conversations SET updated_at = ? WHERE id = ?`, timestamp(), id)
	return err
}

func jsonText(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" || !json.Valid([]byte(raw)) {
		return "{}"
	}
	return raw
}

func timestamp() string {
	return time.Now().UTC().Format("2006-01-02T15:04:05.000Z")
}

func newID() string {
	return fmt.Sprintf("%d", time.Now().UnixNano())
}

func boolInt(value bool) int {
	if value {
		return 1
	}
	return 0
}

func secureFiles(path string) error {
	for _, candidate := range []string{path, path + "-wal", path + "-shm"} {
		if err := os.Chmod(candidate, 0o600); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	return nil
}
