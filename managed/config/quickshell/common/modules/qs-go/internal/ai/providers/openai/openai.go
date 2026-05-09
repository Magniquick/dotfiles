// Package openai implements the OpenAI provider.
package openai

import (
	"context"
	"strings"

	"qs-go/internal/ai/providers"
	"qs-go/internal/ai/providers/oai"
	"qs-go/internal/ai/shared"
)

// Provider streams requests to OpenAI.
type Provider struct{}

func init() {
	providers.Register(Provider{})
}

// Metadata returns OpenAI provider metadata shown in the UI.
func (Provider) Metadata() shared.ProviderMetadata {
	return shared.ProviderMetadata{
		ID:          "openai",
		Label:       "OpenAI",
		Description: "OpenAI Responses API inference",
	}
}

// Stream sends a streaming Responses API request to OpenAI.
func (Provider) Stream(ctx context.Context, req shared.StreamRequest, onToken func(string)) (shared.StreamResult, error) {
	baseURL := openAIBaseURL(req.Config)
	input, err := oai.BuildResponsesInput(req.History, req.Message, req.Attachments, "OpenAI")
	if err != nil {
		return shared.StreamResult{}, err
	}
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

func openAIBaseURL(cfg shared.ProviderConfig) string {
	return oai.BaseURL(cfg.BaseURL, "https://api.openai.com/v1")
}
