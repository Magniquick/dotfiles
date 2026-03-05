package ai

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"
)

// ModelOption represents a single model in the picker.
type ModelOption struct {
	Value           string `json:"value"`
	Label           string `json:"label"`
	Description     string `json:"description"`
	Provider        string `json:"provider"`
	Recommended     bool   `json:"recommended"`
	Attachments     string `json:"attachments,omitempty"` // unknown|supported|unsupported
	MaxInputTokens  int    `json:"max_input_tokens,omitempty"`
	MaxOutputTokens int    `json:"max_output_tokens,omitempty"`
}

// ModelsOutput is the JSON payload returned by RefreshModels.
type ModelsOutput struct {
	Models []ModelOption `json:"models"`
	Status string        `json:"status"`
	Error  string        `json:"error,omitempty"`
}

// Pinned models always appear in the picker (even if the API doesn't return them).
var pinnedModels = []ModelOption{
	{
		Value:       "gemini-2.0-flash",
		Label:       "Gemini 2.0 Flash",
		Provider:    "gemini",
		Recommended: true,
		Description: "Google's fast multimodal model",
	},
	{
		Value:       "gemini-2.5-flash",
		Label:       "Gemini 2.5 Flash",
		Provider:    "gemini",
		Recommended: true,
		Description: "Google's latest flash model",
	},
	{
		Value:       "gpt-4o",
		Label:       "GPT-4o",
		Provider:    "openai",
		Recommended: true,
		Description: "OpenAI's flagship multimodal model",
	},
	{
		Value:       "gpt-4o-mini",
		Label:       "GPT-4o Mini",
		Provider:    "openai",
		Recommended: true,
		Description: "Fast, affordable GPT-4o variant",
	},
	{
		Value:       "o3-mini",
		Label:       "o3-mini",
		Provider:    "openai",
		Recommended: true,
		Description: "OpenAI reasoning model",
	},
}

// openAIModelAllowlist filters to only show relevant chat models.
var openAIModelAllowlist = []string{"gpt-", "o1", "o3", "o4", "chatgpt-", "claude-"}

func openAIModelAllowed(id string) bool {
	for _, prefix := range openAIModelAllowlist {
		if strings.HasPrefix(id, prefix) {
			return true
		}
	}
	return false
}

var (
	catalogMu       sync.Mutex
	catalogCache    []ModelOption
	catalogCachedAt time.Time
	catalogKeyHash  string
)

const catalogTTL = 10 * time.Minute

func modelsCacheKey(openaiKey, geminiKey, baseURL string) string {
	return fmt.Sprintf("%d|%d|%d", len(openaiKey), len(geminiKey), len(baseURL))
}

// RefreshModels fetches models from OpenAI and/or Gemini and returns JSON.
func RefreshModels(openaiKey, geminiKey, baseURL string) string {
	catalogMu.Lock()
	defer catalogMu.Unlock()

	openaiKey = strings.TrimSpace(openaiKey)
	geminiKey = strings.TrimSpace(geminiKey)
	baseURL = strings.TrimSpace(baseURL)

	keyHash := modelsCacheKey(openaiKey, geminiKey, baseURL)
	if len(catalogCache) > 0 && time.Since(catalogCachedAt) < catalogTTL && catalogKeyHash == keyHash {
		b, _ := json.Marshal(ModelsOutput{
			Models: catalogCache,
			Status: "Ready (cached)",
		})
		return string(b)
	}

	if openaiKey == "" && geminiKey == "" {
		models := withPinnedAndCapabilities(nil)
		b, _ := json.Marshal(ModelsOutput{
			Models: models,
			Status: "No API keys (static list)",
		})
		return string(b)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()

	byValue := make(map[string]ModelOption)
	var errs []string

	if openaiKey != "" {
		req := providerRequest{OpenAIKey: openaiKey, BaseURL: baseURL}
		list, err := (openAIProvider{}).ListModels(ctx, req)
		if err != nil {
			errs = append(errs, "OpenAI: "+err.Error())
		} else {
			for _, m := range list {
				if _, exists := byValue[m.Value]; !exists {
					byValue[m.Value] = m
				}
			}
		}
	}

	if geminiKey != "" {
		req := providerRequest{GeminiKey: geminiKey}
		list, err := (geminiProvider{}).ListModels(ctx, req)
		if err != nil {
			errs = append(errs, "Gemini: "+err.Error())
		} else {
			for _, m := range list {
				if _, exists := byValue[m.Value]; !exists {
					byValue[m.Value] = m
				}
			}
		}
	}

	models := make([]ModelOption, 0, len(byValue))
	for _, m := range byValue {
		models = append(models, m)
	}
	models = withPinnedAndCapabilities(models)

	status := "Ready"
	var errStr string
	if len(errs) > 0 {
		errStr = strings.Join(errs, "; ")
		if len(models) == 0 {
			status = "Error"
		} else {
			status = "Ready (partial)"
		}
	}

	if len(errs) == 0 {
		catalogCache = models
		catalogCachedAt = time.Now()
		catalogKeyHash = keyHash
	}

	out := ModelsOutput{Models: models, Status: status}
	if errStr != "" {
		out.Error = errStr
	}
	b, _ := json.Marshal(out)
	return string(b)
}

func withPinnedAndCapabilities(models []ModelOption) []ModelOption {
	byValue := map[string]ModelOption{}
	for _, m := range models {
		byValue[m.Value] = m
	}

	for _, pm := range pinnedModels {
		if _, exists := byValue[pm.Value]; !exists {
			byValue[pm.Value] = pm
		}
	}

	var caps map[string]modelCapability
	if catalog, err := loadCapabilityCatalog(); err == nil && catalog != nil {
		caps = catalog.Models
	}

	out := make([]ModelOption, 0, len(byValue))
	for _, m := range byValue {
		if cap, ok := caps[m.Value]; ok && cap.Provider == m.Provider {
			if m.Attachments == "" {
				m.Attachments = string(cap.Attachments)
			}
			if m.MaxInputTokens == 0 {
				m.MaxInputTokens = cap.MaxInputTokens
			}
			if m.MaxOutputTokens == 0 {
				m.MaxOutputTokens = cap.MaxOutputTokens
			}
		}
		if m.Attachments == "" {
			m.Attachments = string(AttachmentSupportUnknown)
		}
		if isPinned(m.Value) {
			m.Recommended = true
		}
		out = append(out, m)
	}
	applyPinnedOrder(out)
	return out
}

func isPinned(value string) bool {
	for _, p := range pinnedModels {
		if p.Value == value {
			return true
		}
	}
	return false
}

func applyPinnedOrder(models []ModelOption) {
	// Keep stable-enough ordering by pinning recommendation only;
	// QML picker currently doesn't require strict sort.
	for i := range models {
		if isPinned(models[i].Value) {
			models[i].Recommended = true
		}
	}
}

func extractErrorMessage(body []byte) string {
	var v struct {
		Error struct {
			Message string `json:"message"`
		} `json:"error"`
		Message string `json:"message"`
	}
	if json.Unmarshal(body, &v) == nil {
		if v.Error.Message != "" {
			return v.Error.Message
		}
		if v.Message != "" {
			return v.Message
		}
	}
	if len(body) > 200 {
		return string(body[:200])
	}
	return string(body)
}
