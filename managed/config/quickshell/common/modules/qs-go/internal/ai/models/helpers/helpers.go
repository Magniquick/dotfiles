package helpers

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"qs-go/internal/ai/shared"
)

const (
	liteLLMCatalogURL     = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
	liteLLMCatalogVersion = 1
	liteLLMRefreshTTL     = 6 * time.Hour
)

type cacheEnvelope struct {
	Version   int                                 `json:"version"`
	FetchedAt int64                               `json:"fetched_at"`
	ETag      string                              `json:"etag,omitempty"`
	Models    map[string]shared.ModelCapabilities `json:"models"`
}

var liteLLMMu sync.Mutex

func Query(canonicalModelID string) (shared.ModelCapabilities, bool) {
	catalog, err := loadCatalog()
	if err != nil {
		return shared.ModelCapabilities{}, false
	}
	value, ok := catalog.Models[strings.TrimSpace(canonicalModelID)]
	return value, ok
}

func CatalogPath() string {
	base, err := os.UserCacheDir()
	if err != nil || strings.TrimSpace(base) == "" {
		base = filepath.Join(os.TempDir(), "quickshell")
	}
	return filepath.Join(base, "quickshell", "qs-go", "ai_model_caps.json")
}

func loadCatalog() (*cacheEnvelope, error) {
	liteLLMMu.Lock()
	defer liteLLMMu.Unlock()

	cachePath := CatalogPath()
	env, err := readCatalog(cachePath)
	if err == nil && time.Since(time.Unix(env.FetchedAt, 0)) < liteLLMRefreshTTL {
		return env, nil
	}

	next, refreshErr := refreshCatalog(cachePath, env)
	if refreshErr == nil {
		return next, nil
	}
	if env != nil {
		return env, nil
	}
	return nil, refreshErr
}

func readCatalog(cachePath string) (*cacheEnvelope, error) {
	b, err := os.ReadFile(cachePath)
	if err != nil {
		return nil, err
	}
	var env cacheEnvelope
	if err := json.Unmarshal(b, &env); err != nil {
		return nil, err
	}
	if env.Version != liteLLMCatalogVersion {
		return nil, fmt.Errorf("cache version mismatch")
	}
	if env.Models == nil {
		env.Models = map[string]shared.ModelCapabilities{}
	}
	return &env, nil
}

func refreshCatalog(cachePath string, current *cacheEnvelope) (*cacheEnvelope, error) {
	req, err := http.NewRequest(http.MethodGet, liteLLMCatalogURL, nil)
	if err != nil {
		return nil, err
	}
	if current != nil && strings.TrimSpace(current.ETag) != "" {
		req.Header.Set("If-None-Match", current.ETag)
	}

	resp, err := (&http.Client{Timeout: 30 * time.Second}).Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	switch resp.StatusCode {
	case http.StatusNotModified:
		if current == nil {
			return nil, fmt.Errorf("received 304 without existing cache")
		}
		current.FetchedAt = time.Now().Unix()
		if err := writeCatalog(cachePath, current); err != nil {
			return nil, err
		}
		return current, nil
	case http.StatusOK:
		raw, err := io.ReadAll(resp.Body)
		if err != nil {
			return nil, err
		}
		models, err := normalizeLiteLLMCapabilities(raw)
		if err != nil {
			return nil, err
		}
		next := &cacheEnvelope{
			Version:   liteLLMCatalogVersion,
			FetchedAt: time.Now().Unix(),
			ETag:      strings.TrimSpace(resp.Header.Get("ETag")),
			Models:    models,
		}
		if err := writeCatalog(cachePath, next); err != nil {
			return nil, err
		}
		return next, nil
	default:
		raw, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, shared.ExtractErrorMessage(raw))
	}
}

func normalizeLiteLLMCapabilities(raw []byte) (map[string]shared.ModelCapabilities, error) {
	var payload map[string]map[string]any
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil, err
	}

	out := make(map[string]shared.ModelCapabilities)
	for model, spec := range payload {
		if model == "sample_spec" {
			continue
		}
		provider := normalizeProvider(stringField(spec, "litellm_provider"))
		rawModelID := normalizeRawModelID(provider, model)
		if provider == "" || rawModelID == "" || strings.TrimSpace(stringField(spec, "mode")) != "chat" {
			continue
		}

		canonicalID := provider + "/" + rawModelID
		out[canonicalID] = shared.ModelCapabilities{
			SupportsImages:     boolField(spec, "supports_vision") || provider == "gemini",
			SupportsTools:      boolField(spec, "supports_function_calling"),
			SupportsReasoning:  strings.HasPrefix(rawModelID, "o") || boolField(spec, "supports_reasoning"),
			SupportsMultimodal: boolField(spec, "supports_vision") || provider == "gemini",
			MaxInputTokens:     firstInt(intField(spec, "max_input_tokens"), intField(spec, "max_tokens")),
			MaxOutputTokens:    firstInt(intField(spec, "max_output_tokens"), intField(spec, "max_tokens")),
		}
	}
	return out, nil
}

func normalizeRawModelID(provider, model string) string {
	prefix := provider + "/"
	if strings.HasPrefix(model, prefix) {
		return strings.TrimPrefix(model, prefix)
	}
	return strings.TrimSpace(model)
}

func stringField(m map[string]any, key string) string {
	v, ok := m[key]
	if !ok || v == nil {
		return ""
	}
	switch x := v.(type) {
	case string:
		return x
	default:
		return fmt.Sprint(x)
	}
}

func boolField(m map[string]any, key string) bool {
	v, ok := m[key]
	if !ok || v == nil {
		return false
	}
	b, ok := v.(bool)
	return ok && b
}

func intField(m map[string]any, key string) int {
	v, ok := m[key]
	if !ok || v == nil {
		return 0
	}
	switch x := v.(type) {
	case float64:
		return int(x)
	case int:
		return x
	case json.Number:
		n, _ := x.Int64()
		return int(n)
	case string:
		n, err := strconv.Atoi(strings.TrimSpace(x))
		if err == nil {
			return n
		}
	}
	return 0
}

func normalizeProvider(provider string) string {
	switch strings.TrimSpace(provider) {
	case "openai":
		return "openai"
	case "gemini":
		return "gemini"
	default:
		return ""
	}
}

func writeCatalog(path string, env *cacheEnvelope) error {
	if env == nil {
		return fmt.Errorf("nil capability catalog")
	}
	b, err := json.Marshal(env)
	if err != nil {
		return err
	}
	return writeFileAtomic(path, b, 0o600)
}

func writeFileAtomic(path string, data []byte, perm os.FileMode) error {
	if strings.TrimSpace(path) == "" {
		return fmt.Errorf("empty path")
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, "tmp-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)

	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Chmod(perm); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpName, path)
}

func firstInt(values ...int) int {
	for _, value := range values {
		if value > 0 {
			return value
		}
	}
	return 0
}
