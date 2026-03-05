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

type geminiProvider struct{}

func (p geminiProvider) Name() string { return "gemini" }

func (p geminiProvider) Stream(ctx context.Context, req providerRequest, onToken func(string)) (providerResult, error) {
	url := "https://generativelanguage.googleapis.com/v1beta/models/" + req.ModelID + ":streamGenerateContent?alt=sse&key=" + strings.TrimSpace(req.GeminiKey)
	payload, err := buildGeminiPayload(req.SystemPrompt, req.History, req.Message, req.Attachments)
	if err != nil {
		return providerResult{}, err
	}
	b, _ := json.Marshal(payload)

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(b))
	if err != nil {
		return providerResult{}, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	resp, err := (&http.Client{Timeout: 0}).Do(httpReq)
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

		var chunk struct {
			Candidates []struct {
				Content struct {
					Parts []struct {
						Text string `json:"text"`
					} `json:"parts"`
				} `json:"content"`
			} `json:"candidates"`
			UsageMetadata struct {
				PromptTokenCount     int `json:"promptTokenCount"`
				CandidatesTokenCount int `json:"candidatesTokenCount"`
			} `json:"usageMetadata"`
		}
		if err := json.Unmarshal([]byte(data), &chunk); err != nil {
			continue
		}
		for _, c := range chunk.Candidates {
			for _, part := range c.Content.Parts {
				if part.Text != "" {
					onToken(part.Text)
				}
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

func (p geminiProvider) ListModels(ctx context.Context, req providerRequest) ([]ModelOption, error) {
	url := "https://generativelanguage.googleapis.com/v1beta/models?key=" + strings.TrimSpace(req.GeminiKey)
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
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, extractErrorMessage(raw))
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

	models := make([]ModelOption, 0, len(payload.Models))
	for _, m := range payload.Models {
		id := strings.TrimPrefix(strings.TrimSpace(m.Name), "models/")
		if !strings.HasPrefix(id, "gemini-") {
			continue
		}
		supportsChat := false
		for _, method := range m.SupportedGenerationMethods {
			if method == "generateContent" {
				supportsChat = true
				break
			}
		}
		if !supportsChat {
			continue
		}
		label := strings.TrimSpace(m.DisplayName)
		if label == "" {
			label = id
		}
		models = append(models, ModelOption{
			Value:       id,
			Label:       label,
			Description: strings.TrimSpace(m.Description),
			Provider:    "gemini",
		})
	}
	return models, nil
}

func buildGeminiPayload(systemPrompt string, history []HistoryMessage, message string, attachments []Attachment) (map[string]any, error) {
	contents := make([]map[string]any, 0, len(history)+1)
	for _, h := range history {
		role := "user"
		if h.Sender == "assistant" {
			role = "model"
		}
		parts, err := buildGeminiParts(h.Body, h.Attachments)
		if err != nil {
			return nil, err
		}
		contents = append(contents, map[string]any{"role": role, "parts": parts})
	}
	parts, err := buildGeminiParts(message, attachments)
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

func buildGeminiParts(text string, attachments []Attachment) ([]map[string]any, error) {
	parts := make([]map[string]any, 0, len(attachments)+1)
	for _, a := range attachments {
		if u := strings.TrimSpace(a.URL); u != "" {
			parts = append(parts, map[string]any{
				"text": "Attachment URL: " + u,
			})
			continue
		}
		bin, ok := decodeAttachmentBinary(a)
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
