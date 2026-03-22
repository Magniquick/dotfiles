package providers

import (
	"context"
	"fmt"
	"strings"

	"qs-go/internal/ai/shared"
)

type Provider interface {
	Metadata() shared.ProviderMetadata
	ListModels(ctx context.Context, cfg shared.ProviderConfig) ([]shared.ModelDescriptor, error)
	Stream(ctx context.Context, req shared.StreamRequest, onToken func(string)) (shared.StreamResult, error)
}

var registry = map[string]Provider{}

func Register(provider Provider) {
	if provider == nil {
		return
	}
	name := strings.TrimSpace(provider.Metadata().ID)
	if name == "" {
		panic("provider metadata id cannot be empty")
	}
	registry[name] = provider
}

func MustProvider(name string) Provider {
	provider, ok := Get(name)
	if !ok {
		panic("provider not registered: " + name)
	}
	return provider
}

func Get(name string) (Provider, bool) {
	provider, ok := registry[strings.TrimSpace(name)]
	return provider, ok
}

func All() []Provider {
	out := make([]Provider, 0, len(registry))
	for _, provider := range registry {
		out = append(out, provider)
	}
	return out
}

func SplitModelID(modelID string) (string, string, error) {
	trimmed := strings.TrimSpace(modelID)
	parts := strings.SplitN(trimmed, "/", 2)
	if len(parts) != 2 || strings.TrimSpace(parts[0]) == "" || strings.TrimSpace(parts[1]) == "" {
		return "", "", fmt.Errorf("invalid canonical model id: %q", modelID)
	}
	return strings.TrimSpace(parts[0]), strings.TrimSpace(parts[1]), nil
}

func CanonicalModelID(providerID, rawModelID string) string {
	return strings.TrimSpace(providerID) + "/" + strings.TrimSpace(rawModelID)
}
