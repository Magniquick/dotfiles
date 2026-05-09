package ai

import (
	"encoding/json"
	"errors"
	"strings"

	"qs-go/internal/ai/providers"
	"qs-go/internal/ai/shared"
)

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
