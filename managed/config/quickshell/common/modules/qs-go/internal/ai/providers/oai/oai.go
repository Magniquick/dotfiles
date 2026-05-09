package oai

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	"qs-go/internal/ai/shared"
)

func BaseURL(configured, fallback string) string {
	baseURL := strings.TrimSpace(configured)
	if baseURL == "" {
		baseURL = fallback
	}
	return strings.TrimSuffix(baseURL, "/")
}

func StreamResponses(ctx context.Context, baseURL, apiKey string, payload map[string]any, onToken func(string)) (shared.StreamResult, error) {
	body, _ := json.Marshal(payload)
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimSuffix(baseURL, "/")+"/responses", bytes.NewReader(body))
	if err != nil {
		return shared.StreamResult{}, err
	}
	httpReq.Header.Set("Authorization", "Bearer "+strings.TrimSpace(apiKey))
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := (&http.Client{Timeout: 0}).Do(httpReq)
	if err != nil {
		return shared.StreamResult{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(resp.Body)
		return shared.StreamResult{}, fmt.Errorf("HTTP %d: %s", resp.StatusCode, shared.ExtractErrorMessage(raw))
	}
	return ParseResponsesStream(resp.Body, onToken)
}

func BuildResponsesTools(tools []shared.ToolDescriptor, includeWebSearch bool) []map[string]any {
	out := make([]map[string]any, 0, len(tools)+1)
	if includeWebSearch {
		out = append(out, map[string]any{"type": "web_search_preview"})
	}
	for _, tool := range tools {
		if strings.TrimSpace(tool.Kind) == "freeform" {
			out = append(out, map[string]any{
				"type":        "custom",
				"name":        tool.Name,
				"description": tool.Description,
				"format":      tool.Format,
			})
			continue
		}
		out = append(out, map[string]any{
			"type":        "function",
			"name":        tool.Name,
			"description": tool.Description,
			"parameters":  DefaultSchema(tool.InputSchema),
		})
	}
	return out
}

func BuildResponsesInput(history []shared.HistoryMessage, message string, attachments []shared.Attachment, backendLabel string) ([]map[string]any, error) {
	out := make([]map[string]any, 0, len(history)+1)
	for _, item := range history {
		if item.ToolCall != nil {
			if strings.TrimSpace(item.ToolCall.Input) != "" {
				out = append(out, map[string]any{
					"type":    "custom_tool_call",
					"call_id": item.ToolCall.ID,
					"name":    item.ToolCall.Name,
					"input":   item.ToolCall.Input,
				})
				continue
			}
			out = append(out, map[string]any{
				"type":      "function_call",
				"call_id":   item.ToolCall.ID,
				"name":      item.ToolCall.Name,
				"arguments": MustJSON(item.ToolCall.Arguments),
			})
			continue
		}
		if item.ToolResult != nil {
			output := strings.TrimSpace(item.ToolResult.Text)
			if output == "" && len(item.ToolResult.Data) > 0 {
				output = MustJSON(item.ToolResult.Data)
			}
			if item.ToolResult.Name == "apply_patch" {
				out = append(out, map[string]any{
					"type":    "custom_tool_call_output",
					"call_id": item.ToolResult.ToolCallID,
					"name":    item.ToolResult.Name,
					"output":  output,
				})
				continue
			}
			out = append(out, map[string]any{
				"type":    "function_call_output",
				"call_id": item.ToolResult.ToolCallID,
				"output":  output,
			})
			continue
		}
		role := "user"
		contentType := "input_text"
		if item.Sender == "assistant" {
			role = "assistant"
			contentType = "output_text"
		}
		parts, err := BuildResponsesContentParts(contentType, item.Body, item.Attachments, backendLabel)
		if err != nil {
			return nil, err
		}
		out = append(out, map[string]any{"role": role, "content": parts})
	}
	parts, err := BuildResponsesContentParts("input_text", message, attachments, backendLabel)
	if err != nil {
		return nil, err
	}
	out = append(out, map[string]any{"role": "user", "content": parts})
	return out, nil
}

func BuildResponsesContentParts(textType string, text string, attachments []shared.Attachment, backendLabel string) ([]map[string]any, error) {
	parts := make([]map[string]any, 0, len(attachments)+1)
	for _, attachment := range attachments {
		if u := strings.TrimSpace(attachment.URL); u != "" {
			parts = append(parts, map[string]any{"type": "input_image", "image_url": u})
			continue
		}
		dataURI, ok, err := ImageDataURI(attachment, backendLabel)
		if err != nil {
			return nil, err
		}
		if ok {
			parts = append(parts, map[string]any{"type": "input_image", "image_url": dataURI})
		}
	}
	if strings.TrimSpace(text) != "" || len(parts) == 0 {
		parts = append(parts, map[string]any{"type": textType, "text": text})
	}
	return parts, nil
}

func ImageDataURI(attachment shared.Attachment, backendLabel string) (string, bool, error) {
	bin, ok := shared.DecodeAttachmentBinary(attachment)
	if !ok {
		return "", false, nil
	}
	if !strings.HasPrefix(strings.ToLower(bin.MIME), "image/") {
		return "", false, fmt.Errorf("%s backend currently supports image attachments only", backendLabel)
	}
	return "data:" + bin.MIME + ";base64," + base64.StdEncoding.EncodeToString(bin.Data), true, nil
}

func DefaultSchema(schema map[string]any) map[string]any {
	if len(schema) > 0 {
		return schema
	}
	return map[string]any{"type": "object", "properties": map[string]any{}}
}

func MustJSON(value any) string {
	raw, _ := json.Marshal(value)
	return string(raw)
}

func ParseResponsesStream(r io.Reader, onToken func(string)) (shared.StreamResult, error) {
	reader := bufio.NewReader(r)
	var out shared.StreamResult
	var currentEvent string
	seenCalls := map[string]bool{}
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			if err == io.EOF {
				break
			}
			return out, err
		}
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "event:") {
			currentEvent = strings.TrimSpace(strings.TrimPrefix(line, "event:"))
			continue
		}
		if !strings.HasPrefix(line, "data:") {
			continue
		}
		data := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
		if data == "" || data == "[DONE]" {
			continue
		}
		switch currentEvent {
		case "response.output_text.delta":
			var chunk struct {
				Delta string `json:"delta"`
			}
			if json.Unmarshal([]byte(data), &chunk) == nil && chunk.Delta != "" {
				onToken(chunk.Delta)
			}
		case "response.output_item.done":
			var chunk struct {
				Item responseOutputItem `json:"item"`
			}
			if json.Unmarshal([]byte(data), &chunk) == nil {
				appendToolCall(&out, seenCalls, chunk.Item)
			}
		case "response.completed":
			var chunk struct {
				Response struct {
					Output []responseOutputItem `json:"output"`
					Usage  struct {
						InputTokens  int `json:"input_tokens"`
						OutputTokens int `json:"output_tokens"`
					} `json:"usage"`
				} `json:"response"`
			}
			if json.Unmarshal([]byte(data), &chunk) == nil {
				out.PromptTokens = chunk.Response.Usage.InputTokens
				out.OutputTokens = chunk.Response.Usage.OutputTokens
				for _, item := range chunk.Response.Output {
					appendToolCall(&out, seenCalls, item)
				}
			}
		}
	}
	return out, nil
}

func NormalizeCompactOutput(input []map[string]any) []map[string]any {
	out := make([]map[string]any, len(input))
	for i, item := range input {
		next := map[string]any{}
		for key, value := range item {
			next[key] = value
		}
		if next["type"] == "message" && next["role"] == "assistant" {
			if content, ok := next["content"].([]any); ok {
				for _, part := range content {
					if mapped, ok := part.(map[string]any); ok && mapped["type"] == "input_text" {
						mapped["type"] = "output_text"
					}
				}
			}
		}
		out[i] = next
	}
	return out
}

type responseOutputItem struct {
	Type      string `json:"type"`
	CallID    string `json:"call_id"`
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
	Input     string `json:"input"`
}

func appendToolCall(out *shared.StreamResult, seen map[string]bool, item responseOutputItem) {
	if item.Type == "custom_tool_call" && strings.TrimSpace(item.Name) != "" {
		key := firstNonEmpty(item.CallID, item.Name)
		if seen[key] {
			return
		}
		seen[key] = true
		out.ToolCalls = append(out.ToolCalls, shared.ToolCall{
			ID:        item.CallID,
			Name:      item.Name,
			Arguments: map[string]any{"input": item.Input},
			Input:     item.Input,
		})
		return
	}
	if item.Type != "function_call" || strings.TrimSpace(item.Name) == "" {
		return
	}
	key := firstNonEmpty(item.CallID, item.Name)
	if seen[key] {
		return
	}
	seen[key] = true
	args := map[string]any{}
	if strings.TrimSpace(item.Arguments) != "" {
		_ = json.Unmarshal([]byte(item.Arguments), &args)
	}
	out.ToolCalls = append(out.ToolCalls, shared.ToolCall{ID: item.CallID, Name: item.Name, Arguments: args})
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}
