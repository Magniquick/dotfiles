package chatstore

const schemaSQL = `
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS conversations (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL DEFAULT '',
  model_id TEXT NOT NULL,
  provider_id TEXT NOT NULL DEFAULT '',
  mood_id TEXT NOT NULL DEFAULT '',
  mood_name TEXT NOT NULL DEFAULT '',
  system_prompt TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'closed', 'archived', 'deleted')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  closed_at TEXT,
  deleted_at TEXT
);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  ordinal INTEGER NOT NULL,
  sender TEXT NOT NULL CHECK (sender IN ('user', 'assistant', 'tool')),
  kind TEXT NOT NULL CHECK (kind IN ('chat', 'info', 'tool')),
  status TEXT NOT NULL DEFAULT 'complete'
    CHECK (status IN ('streaming', 'complete', 'error', 'deleted')),
  body TEXT NOT NULL DEFAULT '',
  metrics BLOB NOT NULL DEFAULT (jsonb('{}')) CHECK (json_valid(metrics, 8)),
  extra BLOB NOT NULL DEFAULT (jsonb('{}')) CHECK (json_valid(extra, 8)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT,
  completed_at TEXT,
  deleted_at TEXT,
  UNIQUE(conversation_id, ordinal),
  CHECK ((kind = 'tool') = (sender = 'tool'))
);

CREATE TABLE IF NOT EXISTS tool_calls (
  id TEXT PRIMARY KEY,
  message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  tool_call_id TEXT NOT NULL,
  tool_name TEXT NOT NULL,
  phase TEXT NOT NULL CHECK (phase IN ('tool_start', 'tool_done', 'tool_error')),
  status TEXT NOT NULL CHECK (status IN ('running', 'success', 'error')),
  is_error INTEGER NOT NULL DEFAULT 0 CHECK (is_error IN (0, 1)),
  summary TEXT NOT NULL DEFAULT '',
  subtitle TEXT NOT NULL DEFAULT '',
  payload BLOB NOT NULL DEFAULT (jsonb('{}')) CHECK (json_valid(payload, 8)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT,
  UNIQUE(message_id, tool_call_id)
);

CREATE TABLE IF NOT EXISTS attachments (
  id TEXT PRIMARY KEY,
  message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  ordinal INTEGER NOT NULL,
  mime TEXT NOT NULL DEFAULT '',
  path TEXT NOT NULL DEFAULT '',
  sha256 TEXT NOT NULL DEFAULT '',
  size_bytes INTEGER NOT NULL DEFAULT 0 CHECK (size_bytes >= 0),
  metadata BLOB NOT NULL DEFAULT (jsonb('{}')) CHECK (json_valid(metadata, 8)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  UNIQUE(message_id, ordinal)
);

CREATE TABLE IF NOT EXISTS message_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  message_id TEXT REFERENCES messages(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL CHECK (event_type IN (
    'create', 'token', 'complete', 'edit', 'delete',
    'regenerate', 'tool_start', 'tool_done', 'tool_error', 'error'
  )),
  payload BLOB NOT NULL DEFAULT (jsonb('{}')) CHECK (json_valid(payload, 8)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_conversations_status_updated
ON conversations(status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_conversation_ordinal
ON messages(conversation_id, ordinal);

CREATE INDEX IF NOT EXISTS idx_messages_status
ON messages(status);

CREATE INDEX IF NOT EXISTS idx_tool_calls_message
ON tool_calls(message_id);

CREATE INDEX IF NOT EXISTS idx_tool_calls_name_status
ON tool_calls(tool_name, status);

CREATE INDEX IF NOT EXISTS idx_attachments_message
ON attachments(message_id);

CREATE INDEX IF NOT EXISTS idx_events_conversation_created
ON message_events(conversation_id, created_at);

CREATE VIRTUAL TABLE IF NOT EXISTS message_fts USING fts5(
  body,
  sender UNINDEXED,
  kind UNINDEXED,
  conversation_id UNINDEXED,
  message_id UNINDEXED,
  tokenize = 'unicode61'
);

CREATE TRIGGER IF NOT EXISTS messages_ai_fts AFTER INSERT ON messages
WHEN NEW.status != 'deleted'
BEGIN
  INSERT INTO message_fts(rowid, body, sender, kind, conversation_id, message_id)
  VALUES (NEW.rowid, NEW.body, NEW.sender, NEW.kind, NEW.conversation_id, NEW.id);
END;

CREATE TRIGGER IF NOT EXISTS messages_ad_fts AFTER DELETE ON messages
BEGIN
  DELETE FROM message_fts WHERE rowid = OLD.rowid;
END;

CREATE TRIGGER IF NOT EXISTS messages_au_fts AFTER UPDATE OF body, status ON messages
BEGIN
  DELETE FROM message_fts WHERE rowid = OLD.rowid;

  INSERT INTO message_fts(rowid, body, sender, kind, conversation_id, message_id)
  SELECT NEW.rowid, NEW.body, NEW.sender, NEW.kind, NEW.conversation_id, NEW.id
  WHERE NEW.status != 'deleted';
END;
`
