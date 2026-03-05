package ai

import "context"

type providerRequest struct {
	ModelID      string
	OpenAIKey    string
	GeminiKey    string
	BaseURL      string
	SystemPrompt string
	History      []HistoryMessage
	Message      string
	Attachments  []Attachment
}

type providerResult struct {
	PromptTokens int
	OutputTokens int
}

type provider interface {
	Name() string
	Stream(ctx context.Context, req providerRequest, onToken func(string)) (providerResult, error)
	ListModels(ctx context.Context, req providerRequest) ([]ModelOption, error)
}
