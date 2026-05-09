package shared

import (
	"encoding/json"
	"strings"
)

// ToolResultTranscriptPayload returns the payload sent back to model providers.
func ToolResultTranscriptPayload(result ToolResult) map[string]any {
	payload := map[string]any{}
	content := result.Content
	if len(content) == 0 {
		if text := strings.TrimSpace(result.Text); text != "" {
			content = []map[string]any{{
				"type": "text",
				"text": text,
			}}
		}
	}
	if len(content) > 0 {
		payload["content"] = content
	}
	structured := result.StructuredContent
	if len(structured) == 0 && len(result.Data) > 0 {
		structured = result.Data
	}
	if len(structured) > 0 {
		payload["structuredContent"] = structured
	}
	if result.IsError {
		payload["isError"] = true
	}
	return payload
}

// ToolResultTranscriptOutput serializes a tool result for provider replay.
func ToolResultTranscriptOutput(result ToolResult) string {
	payload := ToolResultTranscriptPayload(result)
	if len(payload) == 0 {
		return ""
	}
	data, err := json.Marshal(payload)
	if err != nil {
		if text := strings.TrimSpace(result.Text); text != "" {
			return text
		}
		return "{}"
	}
	return string(data)
}

// ToolResultUIPayload returns the richer tool result payload shown by the UI.
func ToolResultUIPayload(result ToolResult) map[string]any {
	payload := ToolResultTranscriptPayload(result)
	if text := strings.TrimSpace(result.Text); text != "" {
		payload["text"] = text
	}
	if len(result.Data) > 0 {
		payload["data"] = result.Data
	}
	if len(result.Meta) > 0 {
		payload["_meta"] = result.Meta
	}
	if result.DurationMS > 0 {
		payload["duration_ms"] = result.DurationMS
	}
	if result.IsError {
		payload["is_error"] = true
	}
	return payload
}
