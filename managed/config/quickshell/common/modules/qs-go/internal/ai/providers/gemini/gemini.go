package gemini

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

	"qs-go/internal/ai/providers"
	"qs-go/internal/ai/shared"
)

type Provider struct{}

func init() {
	providers.Register(Provider{})
}

func (Provider) Metadata() shared.ProviderMetadata {
	return shared.ProviderMetadata{
		ID:          "gemini",
		Label:       "Gemini",
		Description: "Google Gemini multimodal inference",
		RecommendedRawID: []string{
			"gemini-2.5-flash",
			"gemini-2.0-flash",
		},
		FallbackModels: []shared.ModelDescriptor{
			{RawID: "gemini-2.5-flash", Label: "Gemini 2.5 Flash", Description: "Google's latest flash model"},
			{RawID: "gemini-2.0-flash", Label: "Gemini 2.0 Flash", Description: "Google's fast multimodal model"},
		},
	}
}

func (Provider) Stream(ctx context.Context, req shared.StreamRequest, onToken func(string)) (shared.StreamResult, error) {
	url := "https://generativelanguage.googleapis.com/v1beta/models/" + req.RawModelID + ":streamGenerateContent?alt=sse&key=" + strings.TrimSpace(req.Config.APIKey)
	payload, err := buildPayload(req.SystemPrompt, req.History, req.Message, req.Attachments)
	if err != nil {
		return shared.StreamResult{}, err
	}
	if len(req.Tools) > 0 {
		payload["tools"] = []map[string]any{
			{
				"functionDeclarations": buildToolDeclarations(req.Tools),
			},
		}
	}
	body, _ := json.Marshal(payload)

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return shared.StreamResult{}, err
	}
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

		var chunk struct {
			Candidates []struct {
				Content struct {
					Parts []struct {
						Text         string `json:"text"`
						FunctionCall struct {
							Name string         `json:"name"`
							Args map[string]any `json:"args"`
						} `json:"functionCall"`
					} `json:"parts"`
				} `json:"content"`
				FinishReason string `json:"finishReason"`
			} `json:"candidates"`
			UsageMetadata struct {
				PromptTokenCount     int `json:"promptTokenCount"`
				CandidatesTokenCount int `json:"candidatesTokenCount"`
			} `json:"usageMetadata"`
		}
		if err := json.Unmarshal([]byte(data), &chunk); err != nil {
			continue
		}
		for _, candidate := range chunk.Candidates {
			for _, part := range candidate.Content.Parts {
				if part.Text != "" {
					onToken(part.Text)
				}
				if strings.TrimSpace(part.FunctionCall.Name) != "" {
					out.ToolCalls = append(out.ToolCalls, shared.ToolCall{
						ID:        part.FunctionCall.Name,
						Name:      part.FunctionCall.Name,
						Arguments: part.FunctionCall.Args,
					})
				}
			}
			if candidate.FinishReason != "" {
				out.StopReason = candidate.FinishReason
			}
		}
		if chunk.UsageMetadata.PromptTokenCount > 0 {
			out.PromptTokens = chunk.UsageMetadata.PromptTokenCount
		}
		if chunk.UsageMetadata.CandidatesTokenCount > 0 {
			out.OutputTokens = chunk.UsageMetadata.CandidatesTokenCount
		}
	}

	return out, nil
}

func (Provider) ListModels(ctx context.Context, cfg shared.ProviderConfig) ([]shared.ModelDescriptor, error) {
	url := "https://generativelanguage.googleapis.com/v1beta/models?key=" + strings.TrimSpace(cfg.APIKey)
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
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
		Models []struct {
			Name                       string   `json:"name"`
			DisplayName                string   `json:"displayName"`
			Description                string   `json:"description"`
			SupportedGenerationMethods []string `json:"supportedGenerationMethods"`
		} `json:"models"`
	}
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil, err
	}

	models := make([]shared.ModelDescriptor, 0, len(payload.Models))
	for _, model := range payload.Models {
		id := strings.TrimPrefix(strings.TrimSpace(model.Name), "models/")
		if !strings.HasPrefix(id, "gemini-") {
			continue
		}
		supportsChat := false
		for _, method := range model.SupportedGenerationMethods {
			if method == "generateContent" {
				supportsChat = true
				break
			}
		}
		if !supportsChat {
			continue
		}
		label := strings.TrimSpace(model.DisplayName)
		if label == "" {
			label = id
		}
		models = append(models, shared.ModelDescriptor{
			RawID:        id,
			Label:        label,
			Description:  strings.TrimSpace(model.Description),
			Provider:     "gemini",
			Capabilities: shared.ModelCapabilities{},
		})
	}
	return models, nil
}

func buildPayload(systemPrompt string, history []shared.HistoryMessage, message string, attachments []shared.Attachment) (map[string]any, error) {
	contents := make([]map[string]any, 0, len(history)+1)
	for _, item := range history {
		if item.ToolCall != nil {
			contents = append(contents, map[string]any{
				"role": "model",
				"parts": []map[string]any{
					{
						"functionCall": map[string]any{
							"name": item.ToolCall.Name,
							"args": normalizeSchemaMap(item.ToolCall.Arguments),
						},
					},
				},
			})
			continue
		}
		if item.ToolResult != nil {
			response := map[string]any{}
			if len(item.ToolResult.Data) > 0 {
				for key, value := range item.ToolResult.Data {
					response[key] = value
				}
			}
			if strings.TrimSpace(item.ToolResult.Text) != "" {
				response["text"] = item.ToolResult.Text
			}
			contents = append(contents, map[string]any{
				"role": "user",
				"parts": []map[string]any{
					{
						"functionResponse": map[string]any{
							"name":     firstNonEmpty(item.ToolResult.Name, item.ToolResult.ToolCallID),
							"response": response,
						},
					},
				},
			})
			continue
		}
		role := "user"
		if item.Sender == "assistant" {
			role = "model"
		}
		parts, err := buildParts(item.Body, item.Attachments)
		if err != nil {
			return nil, err
		}
		contents = append(contents, map[string]any{"role": role, "parts": parts})
	}
	parts, err := buildParts(message, attachments)
	if err != nil {
		return nil, err
	}
	contents = append(contents, map[string]any{"role": "user", "parts": parts})

	payload := map[string]any{
		"contents": contents,
	}
	if strings.TrimSpace(systemPrompt) != "" {
		payload["systemInstruction"] = map[string]any{
			"parts": []map[string]any{{"text": systemPrompt}},
		}
	}
	return payload, nil
}

func buildToolDeclarations(tools []shared.ToolDescriptor) []map[string]any {
	out := make([]map[string]any, 0, len(tools))
	for _, tool := range tools {
		out = append(out, map[string]any{
			"name":        tool.Name,
			"description": tool.Description,
			"parameters":  defaultSchema(tool.InputSchema),
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

func normalizeSchemaMap(in map[string]any) map[string]any {
	if in != nil {
		return in
	}
	return map[string]any{}
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func buildParts(text string, attachments []shared.Attachment) ([]map[string]any, error) {
	parts := make([]map[string]any, 0, len(attachments)+1)
	for _, attachment := range attachments {
		if u := strings.TrimSpace(attachment.URL); u != "" {
			parts = append(parts, map[string]any{
				"text": "Attachment URL: " + u,
			})
			continue
		}
		bin, ok := shared.DecodeAttachmentBinary(attachment)
		if !ok {
			continue
		}
		parts = append(parts, map[string]any{
			"inlineData": map[string]any{
				"mimeType": bin.MIME,
				"data":     base64.StdEncoding.EncodeToString(bin.Data),
			},
		})
	}
	if strings.TrimSpace(text) != "" || len(parts) == 0 {
		parts = append(parts, map[string]any{"text": text})
	}
	return parts, nil
}
