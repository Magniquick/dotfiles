package ai

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"sync"
	"time"

	_ "qs-go/internal/ai/providers/gemini"
	_ "qs-go/internal/ai/providers/openai"

	"qs-go/internal/ai/models/helpers"
	"qs-go/internal/ai/providers"
	"qs-go/internal/ai/shared"
)

var (
	catalogMu       sync.Mutex
	catalogCache    shared.CatalogPayload
	catalogCachedAt time.Time
	catalogKeyHash  string
)

const catalogTTL = 10 * time.Minute

func RefreshCatalog(providerConfigJSON string) string {
	config := parseProviderConfig(providerConfigJSON)
	catalogMu.Lock()
	defer catalogMu.Unlock()

	keyHash := strings.TrimSpace(providerConfigJSON)
	if len(catalogCache.Providers) > 0 && time.Since(catalogCachedAt) < catalogTTL && catalogKeyHash == keyHash {
		cached := catalogCache
		cached.Status = "Ready (cached)"
		b, _ := json.Marshal(cached)
		return string(b)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()

	payload := shared.CatalogPayload{
		Providers: make([]shared.ProviderCatalog, 0),
		Status:    "Ready",
	}

	var errs []string
	for _, provider := range providers.All() {
		meta := provider.Metadata()
		cfg := config[meta.ID]
		providerCatalog := shared.ProviderCatalog{
			ID:          meta.ID,
			Label:       meta.Label,
			Description: meta.Description,
			Enabled:     strings.TrimSpace(cfg.APIKey) != "",
		}

		models := meta.FallbackModels
		if providerCatalog.Enabled {
			list, err := provider.ListModels(ctx, cfg)
			if err != nil {
				errs = append(errs, meta.Label+": "+err.Error())
			} else {
				models = list
			}
		}

		annotated := annotateModels(meta, models)
		providerCatalog.Models = annotated
		providerCatalog.RecommendedModels = pickRecommended(annotated)
		payload.Providers = append(payload.Providers, providerCatalog)
	}

	if len(errs) > 0 {
		payload.Error = strings.Join(errs, "; ")
		if allProvidersEmpty(payload.Providers) {
			payload.Status = "Error"
		} else {
			payload.Status = "Ready (partial)"
		}
	}
	if len(errs) == 0 {
		catalogCache = payload
		catalogCachedAt = time.Now()
		catalogKeyHash = keyHash
	}

	if !anyProviderEnabled(payload.Providers) && payload.Status == "Ready" {
		payload.Status = "No provider credentials"
	}

	b, _ := json.Marshal(payload)
	return string(b)
}

func annotateModels(meta shared.ProviderMetadata, models []shared.ModelDescriptor) []shared.ModelDescriptor {
	out := make([]shared.ModelDescriptor, 0, len(models))
	recommended := map[string]bool{}
	for i, rawID := range meta.RecommendedRawID {
		if i >= 2 {
			break
		}
		recommended[strings.TrimSpace(rawID)] = true
	}

	for _, model := range models {
		rawID := strings.TrimSpace(model.RawID)
		if rawID == "" {
			continue
		}
		model.Provider = meta.ID
		model.RawID = rawID
		model.ID = providers.CanonicalModelID(meta.ID, rawID)
		model.Recommended = recommended[rawID]
		if model.Label == "" {
			model.Label = rawID
		}
		if caps, ok := helpers.Query(model.ID); ok {
			model.Capabilities = caps
		}
		out = append(out, model)
	}
	return out
}

func pickRecommended(models []shared.ModelDescriptor) []shared.ModelDescriptor {
	out := make([]shared.ModelDescriptor, 0, 2)
	for _, model := range models {
		if model.Recommended {
			out = append(out, model)
		}
		if len(out) == 2 {
			break
		}
	}
	return out
}

func anyProviderEnabled(providers []shared.ProviderCatalog) bool {
	for _, provider := range providers {
		if provider.Enabled {
			return true
		}
	}
	return false
}

func allProvidersEmpty(providers []shared.ProviderCatalog) bool {
	for _, provider := range providers {
		if len(provider.Models) > 0 {
			return false
		}
	}
	return true
}

func parseProviderConfig(raw string) map[string]shared.ProviderConfig {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" || trimmed == "{}" || trimmed == "null" {
		return map[string]shared.ProviderConfig{}
	}
	var parsed map[string]shared.ProviderConfig
	if err := json.Unmarshal([]byte(trimmed), &parsed); err != nil {
		return map[string]shared.ProviderConfig{}
	}
	return parsed
}

func splitCanonicalModelID(modelID string) (string, string, error) {
	providerID, rawModelID, err := providers.SplitModelID(modelID)
	if err != nil {
		return "", "", err
	}
	if _, ok := providers.Get(providerID); !ok {
		return "", "", errors.New("unknown provider: " + providerID)
	}
	return providerID, rawModelID, nil
}
