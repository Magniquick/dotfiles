package local

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"qs-go/internal/ai/providers"
	"qs-go/internal/ai/providers/oai"
	"qs-go/internal/ai/shared"
)

type Provider struct{}

func init() {
	providers.Register(Provider{})
}

func (Provider) Metadata() shared.ProviderMetadata {
	return shared.ProviderMetadata{
		ID:          "local",
		Label:       "Local",
		Description: "Local OpenAI-compatible Responses API proxy",
	}
}

func (Provider) Stream(ctx context.Context, req shared.StreamRequest, onToken func(string)) (shared.StreamResult, error) {
	baseURL := localBaseURL(req.Config)
	input, err := oai.BuildResponsesInput(req.History, req.Message, req.Attachments, "Local")
	if err != nil {
		return shared.StreamResult{}, err
	}
	input = compactInputIfLarge(ctx, baseURL, req.Config.APIKey, req.RawModelID, input)
	payload := map[string]any{
		"model":  req.RawModelID,
		"input":  input,
		"stream": true,
	}
	if strings.TrimSpace(req.SystemPrompt) != "" {
		payload["instructions"] = req.SystemPrompt
	}
	tools := oai.BuildResponsesTools(req.Tools, true)
	if len(tools) > 0 {
		payload["tools"] = tools
		payload["tool_choice"] = "auto"
	}
	return oai.StreamResponses(ctx, baseURL, req.Config.APIKey, payload, onToken)
}

func localBaseURL(cfg shared.ProviderConfig) string {
	return oai.BaseURL(cfg.BaseURL, "http://127.0.0.1:8317/v1")
}

func compactInputIfLarge(ctx context.Context, baseURL string, apiKey string, model string, input []map[string]any) []map[string]any {
	const compactThreshold = 16
	if len(input) < compactThreshold || len(input) < 2 {
		return input
	}

	keepLast := input[len(input)-1]
	prefix := input[:len(input)-1]
	body, _ := json.Marshal(map[string]any{
		"model": model,
		"input": prefix,
	})
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, baseURL+"/responses/compact", bytes.NewReader(body))
	if err != nil {
		return input
	}
	httpReq.Header.Set("Authorization", "Bearer "+strings.TrimSpace(apiKey))
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := (&http.Client{Timeout: 30 * time.Second}).Do(httpReq)
	if err != nil {
		return input
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return input
	}
	var compacted struct {
		Output []map[string]any `json:"output"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&compacted); err != nil || len(compacted.Output) == 0 {
		return input
	}
	out := oai.NormalizeCompactOutput(compacted.Output)
	out = append(out, keepLast)
	return out
}
