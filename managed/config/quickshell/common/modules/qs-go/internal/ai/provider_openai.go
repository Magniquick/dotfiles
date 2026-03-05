package ai

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
	"time"
)

type openAIProvider struct{}

func (p openAIProvider) Name() string { return "openai" }

func (p openAIProvider) Stream(ctx context.Context, req providerRequest, onToken func(string)) (providerResult, error) {
	baseURL := strings.TrimSpace(req.BaseURL)
	if baseURL == "" {
		baseURL = "https://api.openai.com/v1"
	}
	baseURL = strings.TrimSuffix(baseURL, "/")

	messages, err := buildOpenAIMessages(req.SystemPrompt, req.History, req.Message, req.Attachments)
	if err != nil {
		return providerResult{}, err
	}

	payload := map[string]any{
		"model":    req.ModelID,
		"messages": messages,
		"stream":   true,
		"stream_options": map[string]any{
			"include_usage": true,
		},
	}
	body, _ := json.Marshal(payload)

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, baseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return providerResult{}, err
	}
	httpReq.Header.Set("Authorization", "Bearer "+strings.TrimSpace(req.OpenAIKey))
	httpReq.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 0}
	resp, err := client.Do(httpReq)
	if err != nil {
		return providerResult{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(resp.Body)
		return providerResult{}, fmt.Errorf("HTTP %d: %s", resp.StatusCode, extractErrorMessage(raw))
	}

	reader := bufio.NewReader(resp.Body)
	var out providerResult
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			if err == io.EOF {
				break
			}
			return providerResult{}, err
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
					Content string `json:"content"`
				} `json:"delta"`
			} `json:"choices"`
			Usage struct {
				PromptTokens     int `json:"prompt_tokens"`
				CompletionTokens int `json:"completion_tokens"`
			} `json:"usage"`
		}
		if err := json.Unmarshal([]byte(data), &chunk); err != nil {
			continue
		}
		for _, c := range chunk.Choices {
			if c.Delta.Content != "" {
				onToken(c.Delta.Content)
			}
		}
		if chunk.Usage.PromptTokens > 0 {
			out.PromptTokens = chunk.Usage.PromptTokens
		}
		if chunk.Usage.CompletionTokens > 0 {
			out.OutputTokens = chunk.Usage.CompletionTokens
		}
	}
	return out, nil
}

func (p openAIProvider) ListModels(ctx context.Context, req providerRequest) ([]ModelOption, error) {
	baseURL := strings.TrimSpace(req.BaseURL)
	if baseURL == "" {
		baseURL = "https://api.openai.com/v1"
	}
	baseURL = strings.TrimSuffix(baseURL, "/")
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, baseURL+"/models", nil)
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Authorization", "Bearer "+strings.TrimSpace(req.OpenAIKey))
	resp, err := (&http.Client{Timeout: 20 * time.Second}).Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, extractErrorMessage(raw))
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

	out := make([]ModelOption, 0, len(payload.Data))
	for _, m := range payload.Data {
		id := strings.TrimSpace(m.ID)
		if id == "" || !openAIModelAllowed(id) {
			continue
		}
		out = append(out, ModelOption{
			Value:    id,
			Label:    id,
			Provider: "openai",
		})
	}
	return out, nil
}

func buildOpenAIMessages(systemPrompt string, history []HistoryMessage, message string, attachments []Attachment) ([]map[string]any, error) {
	var out []map[string]any
	if strings.TrimSpace(systemPrompt) != "" {
		out = append(out, map[string]any{
			"role":    "system",
			"content": systemPrompt,
		})
	}
	for _, h := range history {
		role := "user"
		if h.Sender == "assistant" {
			role = "assistant"
		}
		parts, err := buildOpenAIContentParts(h.Body, h.Attachments)
		if err != nil {
			return nil, err
		}
		out = append(out, map[string]any{"role": role, "content": parts})
	}
	parts, err := buildOpenAIContentParts(message, attachments)
	if err != nil {
		return nil, err
	}
	out = append(out, map[string]any{"role": "user", "content": parts})
	return out, nil
}

func buildOpenAIContentParts(text string, attachments []Attachment) ([]map[string]any, error) {
	parts := make([]map[string]any, 0, len(attachments)+1)
	for _, a := range attachments {
		u := strings.TrimSpace(a.URL)
		if u != "" {
			parts = append(parts, map[string]any{
				"type":      "image_url",
				"image_url": map[string]any{"url": u},
			})
			continue
		}

		bin, ok := decodeAttachmentBinary(a)
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
