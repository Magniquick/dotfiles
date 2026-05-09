// Package chatstore persists leftpanel conversations in a local SQLite database.
package chatstore

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "modernc.org/sqlite" // register SQLite driver
)

const migrationVersion = 2

// Store wraps the SQLite conversation database.
type Store struct {
	db *sql.DB
}

// OpenConversationOptions selects or creates a conversation.
type OpenConversationOptions struct {
	ModelID      string
	ProviderID   string
	MoodID       string
	MoodName     string
	SystemPrompt string
}

// Conversation is a persisted chat conversation.
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

// ConversationSummary is a compact closed-conversation listing row.
type ConversationSummary struct {
	ID           string `json:"id"`
	Title        string `json:"title"`
	ModelID      string `json:"model_id"`
	ProviderID   string `json:"provider_id"`
	Status       string `json:"status"`
	CreatedAt    string `json:"created_at"`
	UpdatedAt    string `json:"updated_at"`
	ClosedAt     string `json:"closed_at,omitempty"`
	MessageCount int    `json:"message_count"`
	Preview      string `json:"preview"`
}

// Message is a persisted chat message.
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

// ToolCall is a persisted tool-call UI row.
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

// ResponseItem is a raw provider replay item stored per turn.
type ResponseItem struct {
	ID             string `json:"id"`
	ConversationID string `json:"conversation_id"`
	TurnID         string `json:"turn_id"`
	TurnOrdinal    int    `json:"turn_ordinal"`
	ItemOrdinal    int    `json:"item_ordinal"`
	Source         string `json:"source"`
	ItemType       string `json:"item_type"`
	CallID         string `json:"call_id,omitempty"`
	RawJSON        string `json:"raw_json"`
	CreatedAt      string `json:"created_at,omitempty"`
}

// DefaultPath returns the default SQLite database path.
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

// Open opens and migrates a chat store database.
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

// Close closes the underlying database.
func (s *Store) Close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

func closeRows(rows *sql.Rows) {
	if rows != nil {
		_ = rows.Close()
	}
}

// OpenConversation restores an active conversation or creates one.
func (s *Store) OpenConversation(opts OpenConversationOptions) (Conversation, error) {
	if s == nil || s.db == nil {
		return Conversation{}, errors.New("chat store is not open")
	}
	if conv, ok, err := s.RestoreConversation(opts); err != nil {
		return Conversation{}, err
	} else if ok {
		return conv, nil
	}
	return s.CreateConversation(opts)
}

// RestoreConversation returns the active conversation matching the options.
func (s *Store) RestoreConversation(opts OpenConversationOptions) (Conversation, bool, error) {
	if s == nil || s.db == nil {
		return Conversation{}, false, errors.New("chat store is not open")
	}
	return s.activeConversation(opts)
}

// CreateConversation creates a new active conversation.
func (s *Store) CreateConversation(opts OpenConversationOptions) (Conversation, error) {
	ctx := context.Background()
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
	if err := s.closeActiveConversations(conv.ModelID); err != nil {
		return Conversation{}, err
	}
	if _, err := s.db.ExecContext(ctx, `
		INSERT INTO conversations (
			id, model_id, provider_id, mood_id, mood_name, system_prompt, status, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		conv.ID, conv.ModelID, conv.ProviderID, conv.MoodID, conv.MoodName, conv.SystemPrompt,
		conv.Status, conv.CreatedAt, conv.UpdatedAt); err != nil {
		return Conversation{}, err
	}
	return conv, nil
}

// CloseConversation marks an active conversation closed.
func (s *Store) CloseConversation(id string) error {
	id = strings.TrimSpace(id)
	if id == "" {
		return nil
	}
	ctx := context.Background()
	now := timestamp()
	_, err := s.db.ExecContext(ctx, `
		UPDATE conversations
		SET status = 'closed', closed_at = ?, updated_at = ?
		WHERE id = ? AND status = 'active'`, now, now, id)
	return err
}

// ResumeConversation reopens a closed conversation and returns its messages.
func (s *Store) ResumeConversation(opts OpenConversationOptions, currentID string, targetID string) (Conversation, []Message, error) {
	ctx := context.Background()
	modelID := strings.TrimSpace(opts.ModelID)
	if modelID == "" {
		modelID = "local/gpt-5.4-mini"
	}
	currentID = strings.TrimSpace(currentID)
	targetID = strings.TrimSpace(targetID)

	var conv Conversation
	var err error
	if targetID == "" {
		err = s.db.QueryRowContext(ctx, `
			SELECT id, title, model_id, provider_id, mood_id, mood_name, system_prompt, status, created_at, updated_at
			FROM conversations
			WHERE model_id = ?
				AND id != ?
				AND status = 'closed'
				AND EXISTS (
					SELECT 1
					FROM messages
					WHERE messages.conversation_id = conversations.id
						AND messages.status != 'deleted'
				)
			ORDER BY coalesce(closed_at, updated_at) DESC, updated_at DESC
			LIMIT 1`, modelID, currentID).Scan(&conv.ID, &conv.Title, &conv.ModelID, &conv.ProviderID, &conv.MoodID, &conv.MoodName, &conv.SystemPrompt, &conv.Status, &conv.CreatedAt, &conv.UpdatedAt)
	} else {
		err = s.db.QueryRowContext(ctx, `
			SELECT id, title, model_id, provider_id, mood_id, mood_name, system_prompt, status, created_at, updated_at
			FROM conversations
			WHERE id = ? AND model_id = ? AND status = 'closed'`,
			targetID, modelID).Scan(&conv.ID, &conv.Title, &conv.ModelID, &conv.ProviderID, &conv.MoodID, &conv.MoodName, &conv.SystemPrompt, &conv.Status, &conv.CreatedAt, &conv.UpdatedAt)
	}
	if errors.Is(err, sql.ErrNoRows) {
		return Conversation{}, nil, errors.New("no closed conversation to resume")
	}
	if err != nil {
		return Conversation{}, nil, err
	}

	if currentID != "" {
		if err := s.CloseConversation(currentID); err != nil {
			return Conversation{}, nil, err
		}
	}
	now := timestamp()
	if _, err := s.db.ExecContext(ctx, `
		UPDATE conversations
		SET status = 'active', closed_at = NULL, updated_at = ?
		WHERE id = ?`, now, conv.ID); err != nil {
		return Conversation{}, nil, err
	}
	conv.Status = "active"
	conv.UpdatedAt = now
	messages, err := s.ListMessages(conv.ID)
	if err != nil {
		return Conversation{}, nil, err
	}
	return conv, messages, nil
}

// ListClosedConversations returns closed conversations available for resume.
func (s *Store) ListClosedConversations(opts OpenConversationOptions, currentID string, query string, limit int) ([]ConversationSummary, error) {
	ctx := context.Background()
	modelID := strings.TrimSpace(opts.ModelID)
	if modelID == "" {
		modelID = "local/gpt-5.4-mini"
	}
	currentID = strings.TrimSpace(currentID)
	query = strings.TrimSpace(query)
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	like := "%" + query + "%"
	rows, err := s.db.QueryContext(ctx, `
		SELECT
			c.id,
			c.title,
			c.model_id,
			c.provider_id,
			c.status,
			c.created_at,
			c.updated_at,
			coalesce(c.closed_at, ''),
			(
				SELECT count(*)
				FROM messages m
				WHERE m.conversation_id = c.id AND m.status != 'deleted'
			) AS message_count,
			coalesce((
				SELECT m.body
				FROM messages m
				WHERE m.conversation_id = c.id
					AND m.status != 'deleted'
					AND trim(m.body) != ''
				ORDER BY m.ordinal DESC
				LIMIT 1
			), '') AS preview
		FROM conversations c
		WHERE c.model_id = ?
			AND c.id != ?
			AND c.status = 'closed'
			AND EXISTS (
				SELECT 1
				FROM messages m
				WHERE m.conversation_id = c.id AND m.status != 'deleted'
			)
			AND (
				? = ''
				OR c.title LIKE ?
				OR c.model_id LIKE ?
				OR EXISTS (
					SELECT 1
					FROM messages m
					WHERE m.conversation_id = c.id
						AND m.status != 'deleted'
						AND m.body LIKE ?
				)
			)
		ORDER BY coalesce(c.closed_at, c.updated_at) DESC, c.updated_at DESC
		LIMIT ?`, modelID, currentID, query, like, like, like, limit)
	if err != nil {
		return nil, err
	}
	defer closeRows(rows)

	var out []ConversationSummary
	for rows.Next() {
		var conv ConversationSummary
		if err := rows.Scan(
			&conv.ID,
			&conv.Title,
			&conv.ModelID,
			&conv.ProviderID,
			&conv.Status,
			&conv.CreatedAt,
			&conv.UpdatedAt,
			&conv.ClosedAt,
			&conv.MessageCount,
			&conv.Preview,
		); err != nil {
			return nil, err
		}
		out = append(out, conv)
	}
	return out, rows.Err()
}

// UpsertMessage inserts or updates a message.
func (s *Store) UpsertMessage(msg Message) error {
	ctx := context.Background()
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
	_, err := s.db.ExecContext(ctx, `
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

// MarkMessageDeleted soft-deletes one message.
func (s *Store) MarkMessageDeleted(id string) error {
	id = strings.TrimSpace(id)
	if id == "" {
		return nil
	}
	ctx := context.Background()
	now := timestamp()
	var convID string
	err := s.db.QueryRowContext(ctx, `SELECT conversation_id FROM messages WHERE id = ?`, id).Scan(&convID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	if _, err := s.db.ExecContext(ctx, `
		UPDATE messages
		SET status = 'deleted', updated_at = ?, deleted_at = ?
		WHERE id = ?`, now, now, id); err != nil {
		return err
	}
	return s.touchConversation(convID)
}

// DeleteFromOrdinal soft-deletes messages and response items from an ordinal onward.
func (s *Store) DeleteFromOrdinal(conversationID string, ordinal int) error {
	conversationID = strings.TrimSpace(conversationID)
	if conversationID == "" {
		return nil
	}
	ctx := context.Background()
	now := timestamp()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `
		UPDATE messages
		SET status = 'deleted', updated_at = ?, deleted_at = ?
		WHERE conversation_id = ? AND ordinal >= ? AND status != 'deleted'`,
		now, now, conversationID, ordinal); err != nil {
		_ = tx.Rollback()
		return err
	}
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM response_items
		WHERE conversation_id = ? AND turn_ordinal >= ?`,
		conversationID, ordinal); err != nil {
		_ = tx.Rollback()
		return err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE conversations SET updated_at = ? WHERE id = ?`, now, conversationID); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}

// UpsertToolCall inserts or updates a tool-call row.
func (s *Store) UpsertToolCall(call ToolCall) error {
	ctx := context.Background()
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
	_, err := s.db.ExecContext(ctx, `
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

// UpsertResponseItems stores raw provider replay items for a turn.
func (s *Store) UpsertResponseItems(conversationID, turnID string, turnOrdinal int, items []ResponseItem) error {
	conversationID = strings.TrimSpace(conversationID)
	turnID = strings.TrimSpace(turnID)
	if conversationID == "" {
		return errors.New("conversation id is required")
	}
	if turnID == "" {
		return errors.New("turn id is required")
	}
	if len(items) == 0 {
		return nil
	}
	ctx := context.Background()
	explicitOrdinal := false
	for _, item := range items {
		if item.ItemOrdinal != 0 {
			explicitOrdinal = true
			break
		}
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	for i, item := range items {
		item.ConversationID = conversationID
		item.TurnID = turnID
		item.TurnOrdinal = turnOrdinal
		if !explicitOrdinal {
			item.ItemOrdinal = i
		}
		if err := upsertResponseItem(ctx, tx, item); err != nil {
			_ = tx.Rollback()
			return err
		}
	}
	if _, err := tx.ExecContext(ctx, `UPDATE conversations SET updated_at = ? WHERE id = ?`, timestamp(), conversationID); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}

// ListResponseItems returns raw replay items for a conversation.
func (s *Store) ListResponseItems(conversationID string) ([]ResponseItem, error) {
	ctx := context.Background()
	rows, err := s.db.QueryContext(ctx, `
		SELECT
			id, conversation_id, turn_id, turn_ordinal, item_ordinal, source,
			item_type, call_id, json(raw), created_at
		FROM response_items
		WHERE conversation_id = ?
		ORDER BY turn_ordinal ASC, item_ordinal ASC`, strings.TrimSpace(conversationID))
	if err != nil {
		return nil, err
	}
	defer closeRows(rows)
	var out []ResponseItem
	for rows.Next() {
		var item ResponseItem
		if err := rows.Scan(
			&item.ID, &item.ConversationID, &item.TurnID, &item.TurnOrdinal, &item.ItemOrdinal,
			&item.Source, &item.ItemType, &item.CallID, &item.RawJSON, &item.CreatedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

// DeleteResponseItemsFromOrdinal deletes raw replay items from an ordinal onward.
func (s *Store) DeleteResponseItemsFromOrdinal(conversationID string, ordinal int) error {
	conversationID = strings.TrimSpace(conversationID)
	if conversationID == "" {
		return nil
	}
	ctx := context.Background()
	_, err := s.db.ExecContext(ctx, `
		DELETE FROM response_items
		WHERE conversation_id = ? AND turn_ordinal >= ?`, conversationID, ordinal)
	if err != nil {
		return err
	}
	return s.touchConversation(conversationID)
}

// SearchMessages searches persisted messages with SQLite FTS.
func (s *Store) SearchMessages(query string) ([]Message, error) {
	ctx := context.Background()
	rows, err := s.db.QueryContext(ctx, `
		SELECT m.id, m.conversation_id, m.ordinal, m.sender, m.kind, m.status, m.body
		FROM message_fts f
		JOIN messages m ON m.id = f.message_id
		WHERE message_fts MATCH ?
		ORDER BY m.created_at DESC`, strings.TrimSpace(query))
	if err != nil {
		return nil, err
	}
	defer closeRows(rows)
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

// ListMessages returns non-deleted messages for a conversation.
func (s *Store) ListMessages(conversationID string) ([]Message, error) {
	ctx := context.Background()
	rows, err := s.db.QueryContext(ctx, `
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
	defer closeRows(rows)
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
	ctx := context.Background()
	if _, err := s.db.ExecContext(ctx, `PRAGMA foreign_keys = ON`); err != nil {
		return err
	}
	if _, err := s.db.ExecContext(ctx, `PRAGMA journal_mode = WAL`); err != nil {
		return err
	}
	return nil
}

func (s *Store) migrate() error {
	ctx := context.Background()
	if _, err := s.db.ExecContext(ctx, schemaSQL); err != nil {
		return err
	}
	if _, err := s.db.ExecContext(ctx, `INSERT OR IGNORE INTO schema_migrations(version, name) VALUES (?, ?)`, 1, "initial_conversation_store"); err != nil {
		return err
	}
	return s.migrateResponseItems()
}

func (s *Store) migrateResponseItems() error {
	ctx := context.Background()
	var seen int
	if err := s.db.QueryRowContext(ctx, `SELECT count(*) FROM schema_migrations WHERE version = ?`, migrationVersion).Scan(&seen); err != nil {
		return err
	}
	if seen > 0 {
		return nil
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := backfillResponseItems(ctx, tx); err != nil {
		_ = tx.Rollback()
		return err
	}
	if _, err := tx.ExecContext(ctx, `INSERT OR IGNORE INTO schema_migrations(version, name) VALUES (?, ?)`, migrationVersion, "response_items_ledger"); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}

type responseItemExec interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

func upsertResponseItem(ctx context.Context, exec responseItemExec, item ResponseItem) error {
	item.ConversationID = strings.TrimSpace(item.ConversationID)
	item.TurnID = strings.TrimSpace(item.TurnID)
	item.Source = strings.TrimSpace(item.Source)
	if item.ConversationID == "" {
		return errors.New("conversation id is required")
	}
	if item.TurnID == "" {
		return errors.New("turn id is required")
	}
	if item.Source == "" {
		item.Source = "model_output"
	}
	if item.Source != "model_output" && item.Source != "tool_output" {
		return fmt.Errorf("invalid response item source: %s", item.Source)
	}
	raw, err := compactJSON(item.RawJSON)
	if err != nil {
		return err
	}
	item.RawJSON = raw
	itemType, callID := responseItemMetadata(raw)
	if strings.TrimSpace(item.ItemType) == "" {
		item.ItemType = itemType
	}
	if strings.TrimSpace(item.CallID) == "" {
		item.CallID = callID
	}
	if strings.TrimSpace(item.ID) == "" {
		item.ID = fmt.Sprintf("%s:%s:%d", item.ConversationID, item.TurnID, item.ItemOrdinal)
	}
	if item.CreatedAt == "" {
		item.CreatedAt = timestamp()
	}
	_, err = exec.ExecContext(ctx, `
		INSERT INTO response_items (
			id, conversation_id, turn_id, turn_ordinal, item_ordinal, source,
			item_type, call_id, raw, created_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, jsonb(?), ?)
		ON CONFLICT(conversation_id, turn_id, item_ordinal) DO UPDATE SET
			id = excluded.id,
			source = excluded.source,
			item_type = excluded.item_type,
			call_id = excluded.call_id,
			raw = excluded.raw`,
		item.ID, item.ConversationID, item.TurnID, item.TurnOrdinal, item.ItemOrdinal,
		item.Source, strings.TrimSpace(item.ItemType), strings.TrimSpace(item.CallID),
		item.RawJSON, item.CreatedAt)
	return err
}

func backfillResponseItems(ctx context.Context, tx *sql.Tx) error {
	rows, err := tx.QueryContext(ctx, `
		SELECT
			tc.id,
			m.conversation_id,
			m.id,
			m.ordinal,
			json(tc.payload)
		FROM tool_calls tc
		JOIN messages m ON m.id = tc.message_id
		ORDER BY m.conversation_id ASC, m.ordinal ASC, tc.created_at ASC, tc.id ASC`)
	if err != nil {
		return err
	}
	defer closeRows(rows)

	itemCounts := map[string]int{}
	for rows.Next() {
		var callID, conversationID, messageID, payloadJSON string
		var messageOrdinal int
		if err := rows.Scan(&callID, &conversationID, &messageID, &messageOrdinal, &payloadJSON); err != nil {
			return err
		}
		var payload struct {
			AgentPayload string `json:"agent_payload"`
		}
		if err := json.Unmarshal([]byte(payloadJSON), &payload); err != nil {
			continue
		}
		var rawItems []json.RawMessage
		if err := json.Unmarshal([]byte(strings.TrimSpace(payload.AgentPayload)), &rawItems); err != nil {
			continue
		}
		if len(rawItems) == 0 {
			continue
		}
		turnID, turnOrdinal, err := nearestUserTurn(ctx, tx, conversationID, messageID, messageOrdinal)
		if err != nil {
			return err
		}
		key := conversationID + "\x00" + turnID
		for _, raw := range rawItems {
			if !json.Valid(raw) {
				continue
			}
			rawJSON, err := compactJSON(string(raw))
			if err != nil {
				continue
			}
			itemType, itemCallID := responseItemMetadata(rawJSON)
			source := "model_output"
			if responseItemIsToolOutput(itemType) {
				source = "tool_output"
			}
			itemOrdinal := itemCounts[key]
			itemCounts[key] = itemOrdinal + 1
			if err := upsertResponseItem(ctx, tx, ResponseItem{
				ID:             fmt.Sprintf("backfill:%s:%d", callID, itemOrdinal),
				ConversationID: conversationID,
				TurnID:         turnID,
				TurnOrdinal:    turnOrdinal,
				ItemOrdinal:    itemOrdinal,
				Source:         source,
				ItemType:       itemType,
				CallID:         itemCallID,
				RawJSON:        rawJSON,
			}); err != nil {
				return err
			}
		}
	}
	return rows.Err()
}

func nearestUserTurn(ctx context.Context, tx *sql.Tx, conversationID, fallbackID string, fallbackOrdinal int) (string, int, error) {
	var turnID string
	var turnOrdinal int
	err := tx.QueryRowContext(ctx, `
		SELECT id, ordinal
		FROM messages
		WHERE conversation_id = ?
			AND sender = 'user'
			AND kind = 'chat'
			AND status != 'deleted'
			AND ordinal < ?
		ORDER BY ordinal DESC
		LIMIT 1`, conversationID, fallbackOrdinal).Scan(&turnID, &turnOrdinal)
	if errors.Is(err, sql.ErrNoRows) {
		return fallbackID, fallbackOrdinal, nil
	}
	if err != nil {
		return "", 0, err
	}
	return turnID, turnOrdinal, nil
}

func compactJSON(raw string) (string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", errors.New("response item raw JSON is required")
	}
	var buf bytes.Buffer
	if err := json.Compact(&buf, []byte(raw)); err != nil {
		return "", err
	}
	return buf.String(), nil
}

func responseItemMetadata(raw string) (string, string) {
	var item map[string]any
	if err := json.Unmarshal([]byte(raw), &item); err != nil {
		return "", ""
	}
	itemType := strings.TrimSpace(stringFromAny(item["type"]))
	callID := strings.TrimSpace(stringFromAny(item["call_id"]))
	return itemType, callID
}

func responseItemIsToolOutput(itemType string) bool {
	switch strings.TrimSpace(itemType) {
	case "function_call_output", "custom_tool_call_output":
		return true
	default:
		return false
	}
}

func stringFromAny(value any) string {
	if value == nil {
		return ""
	}
	if text, ok := value.(string); ok {
		return text
	}
	return fmt.Sprint(value)
}

func (s *Store) activeConversation(opts OpenConversationOptions) (Conversation, bool, error) {
	ctx := context.Background()
	var conv Conversation
	modelID := strings.TrimSpace(opts.ModelID)
	if modelID == "" {
		modelID = "local/gpt-5.4-mini"
	}
	err := s.db.QueryRowContext(ctx, `
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

func (s *Store) closeActiveConversations(modelID string) error {
	ctx := context.Background()
	modelID = strings.TrimSpace(modelID)
	if modelID == "" {
		modelID = "local/gpt-5.4-mini"
	}
	now := timestamp()
	_, err := s.db.ExecContext(ctx, `
		UPDATE conversations
		SET status = 'closed', closed_at = ?, updated_at = ?
		WHERE status = 'active' AND model_id = ?`, now, now, modelID)
	return err
}

func (s *Store) listToolCalls(messageID string) ([]ToolCall, error) {
	ctx := context.Background()
	rows, err := s.db.QueryContext(ctx, `
		SELECT
			id, message_id, tool_call_id, tool_name, phase, status, is_error,
			summary, subtitle, json(payload), created_at, coalesce(updated_at, '')
		FROM tool_calls
		WHERE message_id = ?
		ORDER BY created_at ASC`, strings.TrimSpace(messageID))
	if err != nil {
		return nil, err
	}
	defer closeRows(rows)
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
	ctx := context.Background()
	_, err := s.db.ExecContext(ctx, `UPDATE conversations SET updated_at = ? WHERE id = ?`, timestamp(), id)
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
