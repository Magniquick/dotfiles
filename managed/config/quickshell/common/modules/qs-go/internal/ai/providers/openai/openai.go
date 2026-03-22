package openai

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"time"

	"qs-go/internal/ai/providers"
	"qs-go/internal/ai/shared"
)

type Provider struct{}

func init() {
	providers.Register(Provider{})
}

func (Provider) Metadata() shared.ProviderMetadata {
	return shared.ProviderMetadata{
		ID:          "openai",
		Label:       "OpenAI",
		Description: "OpenAI chat and multimodal inference",
		RecommendedRawID: []string{
			"gpt-4o",
			"gpt-4o-mini",
		},
		FallbackModels: []shared.ModelDescriptor{
			{RawID: "gpt-4o", Label: "GPT-4o", Description: "OpenAI flagship multimodal model"},
			{RawID: "gpt-4o-mini", Label: "GPT-4o Mini", Description: "Fast, affordable GPT-4o variant"},
		},
	}
}

func (Provider) Stream(ctx context.Context, req shared.StreamRequest, onToken func(string)) (shared.StreamResult, error) {
	baseURL := strings.TrimSpace(req.Config.BaseURL)
	if baseURL == "" {
		baseURL = "https://api.openai.com/v1"
	}
	baseURL = strings.TrimSuffix(baseURL, "/")

	messages, err := buildMessages(req.SystemPrompt, req.History, req.Message, req.Attachments)
	if err != nil {
		return shared.StreamResult{}, err
	}

	payload := map[string]any{
		"model":    req.RawModelID,
		"messages": messages,
		"stream":   true,
		"stream_options": map[string]any{
			"include_usage": true,
		},
	}
	if len(req.Tools) > 0 {
		payload["tools"] = buildTools(req.Tools)
		payload["tool_choice"] = "auto"
	}
	body, _ := json.Marshal(payload)

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, baseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return shared.StreamResult{}, err
	}
	httpReq.Header.Set("Authorization", "Bearer "+strings.TrimSpace(req.Config.APIKey))
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

	reader := bufio.NewReader(resp.Body)
	var out shared.StreamResult
	toolBuilders := map[int]*toolCallBuilder{}
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			if err == io.EOF {
				break
			}
			return shared.StreamResult{}, err
		}
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "data:") {
			continue
		}
		data := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
		if data == "" {
			continue
		}
		if data == "[DONE]" {
			break
		}

		var chunk struct {
			Choices []struct {
				Delta struct {
					Content   string `json:"content"`
					ToolCalls []struct {
						Index    int    `json:"index"`
						ID       string `json:"id"`
						Function struct {
							Name      string `json:"name"`
							Arguments string `json:"arguments"`
						} `json:"function"`
					} `json:"tool_calls"`
				} `json:"delta"`
				FinishReason string `json:"finish_reason"`
			} `json:"choices"`
			Usage struct {
				PromptTokens     int `json:"prompt_tokens"`
				CompletionTokens int `json:"completion_tokens"`
			} `json:"usage"`
		}
		if err := json.Unmarshal([]byte(data), &chunk); err != nil {
			continue
		}
		for _, choice := range chunk.Choices {
			if choice.Delta.Content != "" {
				onToken(choice.Delta.Content)
			}
			for _, toolCall := range choice.Delta.ToolCalls {
				builder := toolBuilders[toolCall.Index]
				if builder == nil {
					builder = &toolCallBuilder{}
					toolBuilders[toolCall.Index] = builder
				}
				if toolCall.ID != "" {
					builder.ID = toolCall.ID
				}
				if toolCall.Function.Name != "" {
					builder.Name = toolCall.Function.Name
				}
				if toolCall.Function.Arguments != "" {
					builder.Arguments.WriteString(toolCall.Function.Arguments)
				}
			}
			if choice.FinishReason != "" {
				out.StopReason = choice.FinishReason
			}
		}
		if chunk.Usage.PromptTokens > 0 {
			out.PromptTokens = chunk.Usage.PromptTokens
		}
		if chunk.Usage.CompletionTokens > 0 {
			out.OutputTokens = chunk.Usage.CompletionTokens
		}
	}
	out.ToolCalls = finalizeToolCalls(toolBuilders)
	return out, nil
}

func (Provider) ListModels(ctx context.Context, cfg shared.ProviderConfig) ([]shared.ModelDescriptor, error) {
	baseURL := strings.TrimSpace(cfg.BaseURL)
	if baseURL == "" {
		baseURL = "https://api.openai.com/v1"
	}
	baseURL = strings.TrimSuffix(baseURL, "/")

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, baseURL+"/models", nil)
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Authorization", "Bearer "+strings.TrimSpace(cfg.APIKey))

	resp, err := (&http.Client{Timeout: 20 * time.Second}).Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, shared.ExtractErrorMessage(raw))
	}

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	var payload struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil, err
	}

	out := make([]shared.ModelDescriptor, 0, len(payload.Data))
	for _, model := range payload.Data {
		id := strings.TrimSpace(model.ID)
		if id == "" || !modelAllowed(id) {
			continue
		}
		out = append(out, shared.ModelDescriptor{
			RawID:        id,
			Label:        id,
			Provider:     "openai",
			Capabilities: shared.ModelCapabilities{},
		})
	}
	return out, nil
}

var allowlist = []string{"gpt-", "o1", "o3", "o4", "chatgpt-", "claude-"}

func modelAllowed(id string) bool {
	for _, prefix := range allowlist {
		if strings.HasPrefix(id, prefix) {
			return true
		}
	}
	return false
}

func buildMessages(systemPrompt string, history []shared.HistoryMessage, message string, attachments []shared.Attachment) ([]map[string]any, error) {
	var out []map[string]any
	if strings.TrimSpace(systemPrompt) != "" {
		out = append(out, map[string]any{
			"role":    "system",
			"content": systemPrompt,
		})
	}
	for _, item := range history {
		if item.ToolCall != nil {
			out = append(out, map[string]any{
				"role": "assistant",
				"tool_calls": []map[string]any{
					{
						"id":   item.ToolCall.ID,
						"type": "function",
						"function": map[string]any{
							"name":      item.ToolCall.Name,
							"arguments": mustJSON(item.ToolCall.Arguments),
						},
					},
				},
			})
			continue
		}
		if item.ToolResult != nil {
			content := strings.TrimSpace(item.ToolResult.Text)
			if content == "" && len(item.ToolResult.Data) > 0 {
				content = mustJSON(item.ToolResult.Data)
			}
			out = append(out, map[string]any{
				"role":         "tool",
				"tool_call_id": item.ToolResult.ToolCallID,
				"content":      content,
			})
			continue
		}
		role := "user"
		if item.Sender == "assistant" {
			role = "assistant"
		}
		if role == "assistant" {
			out = append(out, map[string]any{"role": role, "content": item.Body})
			continue
		}
		parts, err := buildContentParts(item.Body, item.Attachments)
		if err != nil {
			return nil, err
		}
		out = append(out, map[string]any{"role": role, "content": parts})
	}
	parts, err := buildContentParts(message, attachments)
	if err != nil {
		return nil, err
	}
	out = append(out, map[string]any{"role": "user", "content": parts})
	return out, nil
}

type toolCallBuilder struct {
	ID        string
	Name      string
	Arguments strings.Builder
}

func buildTools(tools []shared.ToolDescriptor) []map[string]any {
	out := make([]map[string]any, 0, len(tools))
	for _, tool := range tools {
		out = append(out, map[string]any{
			"type": "function",
			"function": map[string]any{
				"name":        tool.Name,
				"description": tool.Description,
				"parameters":  defaultSchema(tool.InputSchema),
			},
		})
	}
	return out
}

func finalizeToolCalls(builders map[int]*toolCallBuilder) []shared.ToolCall {
	indexes := make([]int, 0, len(builders))
	for idx := range builders {
		indexes = append(indexes, idx)
	}
	sort.Ints(indexes)

	out := make([]shared.ToolCall, 0, len(indexes))
	for _, idx := range indexes {
		builder := builders[idx]
		if builder == nil || strings.TrimSpace(builder.Name) == "" {
			continue
		}
		args := map[string]any{}
		rawArgs := strings.TrimSpace(builder.Arguments.String())
		if rawArgs != "" {
			_ = json.Unmarshal([]byte(rawArgs), &args)
		}
		out = append(out, shared.ToolCall{
			ID:        builder.ID,
			Name:      builder.Name,
			Arguments: args,
		})
	}
	return out
}

func defaultSchema(schema map[string]any) map[string]any {
	if len(schema) > 0 {
		return schema
	}
	return map[string]any{
		"type":       "object",
		"properties": map[string]any{},
	}
}

func mustJSON(value any) string {
	raw, _ := json.Marshal(value)
	return string(raw)
}

func buildContentParts(text string, attachments []shared.Attachment) ([]map[string]any, error) {
	parts := make([]map[string]any, 0, len(attachments)+1)
	for _, attachment := range attachments {
		if u := strings.TrimSpace(attachment.URL); u != "" {
			parts = append(parts, map[string]any{
				"type":      "image_url",
				"image_url": map[string]any{"url": u},
			})
			continue
		}

		bin, ok := shared.DecodeAttachmentBinary(attachment)
		if !ok {
			continue
		}
		if !strings.HasPrefix(strings.ToLower(bin.MIME), "image/") {
			return nil, fmt.Errorf("OpenAI backend currently supports image attachments only")
		}
		dataURI := "data:" + bin.MIME + ";base64," + base64.StdEncoding.EncodeToString(bin.Data)
		parts = append(parts, map[string]any{
			"type":      "image_url",
			"image_url": map[string]any{"url": dataURI},
		})
	}
	if strings.TrimSpace(text) != "" || len(parts) == 0 {
		parts = append(parts, map[string]any{"type": "text", "text": text})
	}
	return parts, nil
}
