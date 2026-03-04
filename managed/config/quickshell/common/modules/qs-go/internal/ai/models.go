package ai

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

// ModelOption represents a single model in the picker.
type ModelOption struct {
	Value       string `json:"value"`
	Label       string `json:"label"`
	Description string `json:"description"`
	Provider    string `json:"provider"`
	Recommended bool   `json:"recommended"`
}

// ModelsOutput is the JSON payload returned by RefreshModels.
type ModelsOutput struct {
	Models []ModelOption `json:"models"`
	Status string        `json:"status"`
	Error  string        `json:"error,omitempty"`
}

// Pinned models always appear in the picker (even if the API doesn't return them).
var pinnedModels = []ModelOption{
	{Value: "gemini-2.0-flash", Label: "Gemini 2.0 Flash", Provider: "gemini", Recommended: true,
		Description: "Google's fast multimodal model"},
	{Value: "gemini-2.5-flash", Label: "Gemini 2.5 Flash", Provider: "gemini", Recommended: true,
		Description: "Google's latest flash model"},
	{Value: "gpt-4o", Label: "GPT-4o", Provider: "openai", Recommended: true,
		Description: "OpenAI's flagship multimodal model"},
	{Value: "gpt-4o-mini", Label: "GPT-4o Mini", Provider: "openai", Recommended: true,
		Description: "Fast, affordable GPT-4o variant"},
	{Value: "o3-mini", Label: "o3-mini", Provider: "openai", Recommended: true,
		Description: "OpenAI reasoning model"},
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

// Cache
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

	keyHash := modelsCacheKey(openaiKey, geminiKey, baseURL)
	if len(catalogCache) > 0 && time.Since(catalogCachedAt) < catalogTTL && catalogKeyHash == keyHash {
		b, _ := json.Marshal(ModelsOutput{
			Models: catalogCache,
			Status: "Ready (cached)",
		})
		return string(b)
	}

	if strings.TrimSpace(openaiKey) == "" && strings.TrimSpace(geminiKey) == "" {
		models := make([]ModelOption, len(pinnedModels))
		copy(models, pinnedModels)
		b, _ := json.Marshal(ModelsOutput{
			Models: models,
			Status: "No API keys (static list)",
		})
		return string(b)
	}

	client := &http.Client{Timeout: 20 * time.Second}
	byValue := make(map[string]ModelOption)
	var errs []string

	// OpenAI
	if strings.TrimSpace(openaiKey) != "" {
		ids, err := fetchOpenAIModels(client, strings.TrimSpace(openaiKey), strings.TrimSpace(baseURL))
		if err != nil {
			errs = append(errs, "OpenAI: "+err.Error())
		} else {
			for _, id := range ids {
				if id == "" || !openAIModelAllowed(id) {
					continue
				}
				if _, exists := byValue[id]; !exists {
					byValue[id] = ModelOption{
						Value:    id,
						Label:    id,
						Provider: "openai",
					}
				}
			}
		}
	}

	// Gemini
	if strings.TrimSpace(geminiKey) != "" {
		models, err := fetchGeminiModels(client, strings.TrimSpace(geminiKey))
		if err != nil {
			errs = append(errs, "Gemini: "+err.Error())
		} else {
			for _, m := range models {
				if _, exists := byValue[m.Value]; !exists {
					byValue[m.Value] = m
				}
			}
		}
	}

	// Ensure pinned models are always present
	for _, pm := range pinnedModels {
		if _, exists := byValue[pm.Value]; !exists {
			byValue[pm.Value] = pm
		}
	}

	// Build sorted list (pinned first, then alphabetical)
	var models []ModelOption
	for _, m := range byValue {
		models = append(models, m)
	}
	applyPinnedOrder(models)

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

func fetchOpenAIModels(client *http.Client, apiKey, baseURL string) ([]string, error) {
	if baseURL == "" {
		baseURL = "https://api.openai.com/v1"
	}
	baseURL = strings.TrimSuffix(baseURL, "/")
	req, err := http.NewRequest(http.MethodGet, baseURL+"/models", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, extractErrorMessage(body))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var result struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, err
	}

	ids := make([]string, 0, len(result.Data))
	for _, m := range result.Data {
		ids = append(ids, strings.TrimSpace(m.ID))
	}
	return ids, nil
}

func fetchGeminiModels(client *http.Client, apiKey string) ([]ModelOption, error) {
	url := "https://generativelanguage.googleapis.com/v1beta/models?key=" + apiKey
	resp, err := client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, extractErrorMessage(body))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var result struct {
		Models []struct {
			Name                       string   `json:"name"`
			DisplayName                string   `json:"displayName"`
			Description                string   `json:"description"`
			SupportedGenerationMethods []string `json:"supportedGenerationMethods"`
		} `json:"models"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, err
	}

	var models []ModelOption
	for _, m := range result.Models {
		id := strings.TrimPrefix(m.Name, "models/")
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

func applyPinnedOrder(models []ModelOption) {
	pinnedSet := make(map[string]bool)
	for _, p := range pinnedModels {
		pinnedSet[p.Value] = true
	}
	// Mark recommended for pinned
	for i := range models {
		if pinnedSet[models[i].Value] {
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
