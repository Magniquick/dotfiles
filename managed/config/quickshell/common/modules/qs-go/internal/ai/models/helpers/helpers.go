// Package helpers provides static model capability lookup helpers.
package helpers

import (
	"strings"

	"qs-go/internal/ai/shared"
)

var staticCapabilities = map[string]shared.ModelCapabilities{
	"openai/gpt-5.5": {
		SupportsImages:     true,
		SupportsTools:      true,
		SupportsMultimodal: true,
	},
	"openai/gpt-5.4-mini": {
		SupportsImages:     true,
		SupportsTools:      true,
		SupportsMultimodal: true,
	},
	"openai/gpt-5.3-codex": {
		SupportsImages:     true,
		SupportsTools:      true,
		SupportsMultimodal: true,
	},
	"local/gpt-5.5": {
		SupportsImages:     true,
		SupportsTools:      true,
		SupportsMultimodal: true,
	},
	"local/gpt-5.4-mini": {
		SupportsImages:     true,
		SupportsTools:      true,
		SupportsMultimodal: true,
	},
	"local/gpt-5.3-codex": {
		SupportsImages:     true,
		SupportsTools:      true,
		SupportsMultimodal: true,
	},
	"gemini/gemini-2.5-flash": {
		SupportsImages:     true,
		SupportsTools:      true,
		SupportsMultimodal: true,
	},
	"gemini/gemini-2.0-flash": {
		SupportsImages:     true,
		SupportsTools:      true,
		SupportsMultimodal: true,
	},
}

// Query returns capabilities for a canonical model ID.
func Query(canonicalModelID string) (shared.ModelCapabilities, bool) {
	value, ok := staticCapabilities[strings.TrimSpace(canonicalModelID)]
	return value, ok
}
