// Package gemini implements the Google Gemini provider.
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

	"qs-go/internal/ai/providers"
	"qs-go/internal/ai/shared"
)

// Provider streams requests to Gemini.
type Provider struct{}

func init() {
	providers.Register(Provider{})
}

// Metadata returns Gemini provider metadata shown in the UI.
func (Provider) Metadata() shared.ProviderMetadata {
	return shared.ProviderMetadata{
		ID:          "gemini",
		Label:       "Gemini",
		Description: "Google Gemini multimodal inference",
	}
}

// Stream sends a streaming request to Gemini.
func (Provider) Stream(ctx context.Context, req shared.StreamRequest, onToken func(string)) (shared.StreamResult, error) {
	url := "https://generativelanguage.googleapis.com/v1beta/models/" + req.RawModelID + ":streamGenerateContent?alt=sse&key=" + strings.TrimSpace(req.Config.APIKey)
	payload, err := buildPayloadForModel(req.RawModelID, req.SystemPrompt, req.History, req.Message, req.Attachments, req.Tools)
	if err != nil {
		return shared.StreamResult{}, err
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
	defer func() {
		_ = resp.Body.Close()
	}()
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

func buildPayload(systemPrompt string, history []shared.HistoryMessage, message string, attachments []shared.Attachment) (map[string]any, error) {
	return buildPayloadForModel("", systemPrompt, history, message, attachments, nil)
}

func buildPayloadForModel(rawModelID string, systemPrompt string, history []shared.HistoryMessage, message string, attachments []shared.Attachment, tools []shared.ToolDescriptor) (map[string]any, error) {
	contents := make([]map[string]any, 0, len(history)+1)
	for _, item := range history {
		if item.ToolCall != nil {
			args := item.ToolCall.Arguments
			if strings.TrimSpace(item.ToolCall.Input) != "" && len(args) == 0 {
				args = map[string]any{"input": item.ToolCall.Input}
			}
			contents = append(contents, map[string]any{
				"role": "model",
				"parts": []map[string]any{
					{
						"functionCall": map[string]any{
							"name": item.ToolCall.Name,
							"args": normalizeSchemaMap(args),
						},
					},
				},
			})
			continue
		}
		if item.ToolResult != nil {
			response := shared.ToolResultTranscriptPayload(*item.ToolResult)
			if len(response) == 0 {
				response["result"] = ""
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
	if searchEnabledForModel(rawModelID) {
		payload["tools"] = append(payloadTools(payload), map[string]any{"googleSearch": map[string]any{}})
	}
	if len(tools) > 0 {
		payload["tools"] = append(payloadTools(payload), map[string]any{
			"functionDeclarations": buildToolDeclarations(tools),
		})
	}
	if supportsCombinedServerTools(rawModelID) && len(tools) > 0 {
		payload["toolConfig"] = map[string]any{
			"includeServerSideToolInvocations": true,
		}
	}
	return payload, nil
}

func payloadTools(payload map[string]any) []map[string]any {
	if existing, ok := payload["tools"].([]map[string]any); ok {
		return existing
	}
	return []map[string]any{}
}

func searchEnabledForModel(rawModelID string) bool {
	id := strings.TrimSpace(rawModelID)
	if id == "" {
		return false
	}
	return supportsCombinedServerTools(id)
}

func supportsCombinedServerTools(rawModelID string) bool {
	return strings.HasPrefix(strings.TrimSpace(rawModelID), "gemini-3")
}

func buildToolDeclarations(tools []shared.ToolDescriptor) []map[string]any {
	out := make([]map[string]any, 0, len(tools))
	for _, tool := range tools {
		schema := defaultSchema(tool.InputSchema)
		if strings.TrimSpace(tool.Kind) == "freeform" {
			schema = freeformFallbackSchema()
		}
		out = append(out, map[string]any{
			"name":        tool.Name,
			"description": tool.Description,
			"parameters":  schema,
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

func freeformFallbackSchema() map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"input": map[string]any{
				"type":        "string",
				"description": "Raw freeform tool input.",
			},
		},
		"required": []string{"input"},
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
