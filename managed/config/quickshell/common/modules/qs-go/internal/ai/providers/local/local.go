// Package local implements the local OpenAI-compatible provider.
package local

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"qs-go/internal/ai/providers"
	"qs-go/internal/ai/providers/oai"
	"qs-go/internal/ai/shared"
)

// Provider streams Responses API requests through a local proxy.
type Provider struct{}

func init() {
	providers.Register(Provider{})
}

// Metadata returns the local provider metadata shown in the UI.
func (Provider) Metadata() shared.ProviderMetadata {
	return shared.ProviderMetadata{
		ID:          "local",
		Label:       "Local",
		Description: "Local OpenAI-compatible Responses API proxy",
	}
}

// Stream sends a request to the configured local Responses-compatible endpoint.
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
		log.Printf("qs-go ai/local: responses tool payload %s", summarizeResponsesTools(tools))
		payload["tools"] = tools
		payload["tool_choice"] = "auto"
	}
	return oai.StreamResponses(ctx, baseURL, req.Config.APIKey, payload, onToken)
}

func summarizeResponsesTools(tools []map[string]any) string {
	parts := make([]string, 0, len(tools))
	for _, tool := range tools {
		kind := strings.TrimSpace(fmt.Sprint(tool["type"]))
		name := strings.TrimSpace(fmt.Sprint(tool["name"]))
		switch kind {
		case "namespace":
			children, _ := tool["tools"].([]map[string]any)
			parts = append(parts, fmt.Sprintf("namespace:%s:tools=%d:sample=[%s]", name, len(children), sampleToolNames(children, 6)))
		case "function", "custom":
			parts = append(parts, kind+":"+name)
		default:
			parts = append(parts, kind)
		}
	}
	return fmt.Sprintf("total=%d [%s]", len(tools), strings.Join(parts, ","))
}

func sampleToolNames(tools []map[string]any, limit int) string {
	names := make([]string, 0, min(len(tools), limit))
	for i, tool := range tools {
		if i >= limit {
			break
		}
		names = append(names, strings.TrimSpace(fmt.Sprint(tool["name"])))
	}
	if len(tools) > limit {
		names = append(names, fmt.Sprintf("+%d", len(tools)-limit))
	}
	return strings.Join(names, ",")
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
	defer func() {
		_ = resp.Body.Close()
	}()
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
