package chatstore

import (
	"encoding/json"
	"strings"
)

type apiAction struct {
	Action         string                  `json:"action"`
	Conversation   OpenConversationOptions `json:"-"`
	ConversationID string                  `json:"conversation_id"`
	Ordinal        int                     `json:"ordinal"`
	ModelID        string                  `json:"model_id"`
	ProviderID     string                  `json:"provider_id"`
	MoodID         string                  `json:"mood_id"`
	MoodName       string                  `json:"mood_name"`
	SystemPrompt   string                  `json:"system_prompt"`
	Message        json.RawMessage         `json:"message"`
	ToolCall       json.RawMessage         `json:"tool_call"`
	MessageID      string                  `json:"message_id"`
}

type apiResult struct {
	OK           bool          `json:"ok"`
	Error        string        `json:"error,omitempty"`
	Conversation *Conversation `json:"conversation,omitempty"`
	Messages     []Message     `json:"messages,omitempty"`
}

type apiMessage struct {
	ID             string          `json:"id"`
	ConversationID string          `json:"conversation_id"`
	Ordinal        int             `json:"ordinal"`
	Sender         string          `json:"sender"`
	Kind           string          `json:"kind"`
	Status         string          `json:"status"`
	Body           string          `json:"body"`
	MetricsJSON    json.RawMessage `json:"metrics_json"`
	ExtraJSON      json.RawMessage `json:"extra_json"`
	CreatedAt      string          `json:"created_at"`
	UpdatedAt      string          `json:"updated_at"`
	CompletedAt    string          `json:"completed_at"`
	DeletedAt      string          `json:"deleted_at"`
}

type apiToolCall struct {
	ID          string          `json:"id"`
	MessageID   string          `json:"message_id"`
	ToolCallID  string          `json:"tool_call_id"`
	ToolName    string          `json:"tool_name"`
	Phase       string          `json:"phase"`
	Status      string          `json:"status"`
	IsError     bool            `json:"is_error"`
	Summary     string          `json:"summary"`
	Subtitle    string          `json:"subtitle"`
	PayloadJSON json.RawMessage `json:"payload_json"`
	CreatedAt   string          `json:"created_at"`
	UpdatedAt   string          `json:"updated_at"`
}

func ApplyJSON(raw string) string {
	return applyJSON("", raw)
}

func ApplyJSONWithPath(path string, raw string) string {
	return applyJSON(path, raw)
}

func applyJSON(path string, raw string) string {
	var action apiAction
	if err := json.Unmarshal([]byte(raw), &action); err != nil {
		return encodeResult(apiResult{OK: false, Error: err.Error()})
	}
	store, err := Open(path)
	if err != nil {
		return encodeResult(apiResult{OK: false, Error: err.Error()})
	}
	defer store.Close()

	switch strings.TrimSpace(action.Action) {
	case "open_conversation":
		conv, err := store.OpenConversation(action.openOptions())
		if err != nil {
			return encodeResult(apiResult{OK: false, Error: err.Error()})
		}
		messages, err := store.ListMessages(conv.ID)
		if err != nil {
			return encodeResult(apiResult{OK: false, Error: err.Error()})
		}
		return encodeResult(apiResult{OK: true, Conversation: &conv, Messages: messages})
	case "create_conversation":
		conv, err := store.CreateConversation(action.openOptions())
		if err != nil {
			return encodeResult(apiResult{OK: false, Error: err.Error()})
		}
		return encodeResult(apiResult{OK: true, Conversation: &conv})
	case "close_conversation":
		if err := store.CloseConversation(action.ConversationID); err != nil {
			return encodeResult(apiResult{OK: false, Error: err.Error()})
		}
		return encodeResult(apiResult{OK: true})
	case "upsert_message":
		msg, err := decodeAPIMessage(action.Message)
		if err != nil {
			return encodeResult(apiResult{OK: false, Error: err.Error()})
		}
		if err := store.UpsertMessage(msg); err != nil {
			return encodeResult(apiResult{OK: false, Error: err.Error()})
		}
		return encodeResult(apiResult{OK: true})
	case "mark_message_deleted":
		if err := store.MarkMessageDeleted(action.MessageID); err != nil {
			return encodeResult(apiResult{OK: false, Error: err.Error()})
		}
		return encodeResult(apiResult{OK: true})
	case "delete_from_ordinal":
		if err := store.DeleteFromOrdinal(action.ConversationID, action.Ordinal); err != nil {
			return encodeResult(apiResult{OK: false, Error: err.Error()})
		}
		return encodeResult(apiResult{OK: true})
	case "upsert_tool_call":
		call, err := decodeAPIToolCall(action.ToolCall)
		if err != nil {
			return encodeResult(apiResult{OK: false, Error: err.Error()})
		}
		if err := store.UpsertToolCall(call); err != nil {
			return encodeResult(apiResult{OK: false, Error: err.Error()})
		}
		return encodeResult(apiResult{OK: true})
	case "list_messages":
		messages, err := store.ListMessages(action.ConversationID)
		if err != nil {
			return encodeResult(apiResult{OK: false, Error: err.Error()})
		}
		return encodeResult(apiResult{OK: true, Messages: messages})
	default:
		return encodeResult(apiResult{OK: false, Error: "unknown chatstore action: " + action.Action})
	}
}

func (a apiAction) openOptions() OpenConversationOptions {
	return OpenConversationOptions{
		ModelID:      a.ModelID,
		ProviderID:   a.ProviderID,
		MoodID:       a.MoodID,
		MoodName:     a.MoodName,
		SystemPrompt: a.SystemPrompt,
	}
}

func decodeAPIMessage(raw json.RawMessage) (Message, error) {
	var msg apiMessage
	if err := json.Unmarshal(raw, &msg); err != nil {
		return Message{}, err
	}
	return Message{
		ID:             msg.ID,
		ConversationID: msg.ConversationID,
		Ordinal:        msg.Ordinal,
		Sender:         msg.Sender,
		Kind:           msg.Kind,
		Status:         msg.Status,
		Body:           msg.Body,
		MetricsJSON:    flexibleJSON(msg.MetricsJSON),
		ExtraJSON:      flexibleJSON(msg.ExtraJSON),
		CreatedAt:      msg.CreatedAt,
		UpdatedAt:      msg.UpdatedAt,
		CompletedAt:    msg.CompletedAt,
		DeletedAt:      msg.DeletedAt,
	}, nil
}

func decodeAPIToolCall(raw json.RawMessage) (ToolCall, error) {
	var call apiToolCall
	if err := json.Unmarshal(raw, &call); err != nil {
		return ToolCall{}, err
	}
	return ToolCall{
		ID:          call.ID,
		MessageID:   call.MessageID,
		ToolCallID:  call.ToolCallID,
		ToolName:    call.ToolName,
		Phase:       call.Phase,
		Status:      call.Status,
		IsError:     call.IsError,
		Summary:     call.Summary,
		Subtitle:    call.Subtitle,
		PayloadJSON: flexibleJSON(call.PayloadJSON),
		CreatedAt:   call.CreatedAt,
		UpdatedAt:   call.UpdatedAt,
	}, nil
}

func flexibleJSON(raw json.RawMessage) string {
	raw = json.RawMessage(strings.TrimSpace(string(raw)))
	if len(raw) == 0 || string(raw) == "null" {
		return "{}"
	}
	var asString string
	if err := json.Unmarshal(raw, &asString); err == nil {
		return jsonText(asString)
	}
	return jsonText(string(raw))
}

func encodeResult(result apiResult) string {
	data, err := json.Marshal(result)
	if err != nil {
		return `{"ok":false,"error":"failed to encode chatstore result"}`
	}
	return string(data)
}
