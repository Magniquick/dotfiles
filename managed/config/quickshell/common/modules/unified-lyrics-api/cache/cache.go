package cache

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const keyPrefix = "unifiedlyrics:v1"

type Envelope struct {
	Key     string          `json:"key"`
	SavedAt int64           `json:"savedAt"`
	Payload json.RawMessage `json:"payload"`
}

func sha256Hex(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

func hashScopeTag(prefix, value string) string {
	return prefix + ":" + sha256Hex(strings.TrimSpace(value))
}

func logicalKey(kind, scope, id string) string {
	return fmt.Sprintf("%s:%s:%s:%s", keyPrefix, kind, scope, id)
}

func entryPath(cacheDir, logicalKey string) string {
	name := sha256Hex(logicalKey) + ".json"
	return filepath.Join(cacheDir, "entries", name)
}

func EntryPath(cacheDir, logicalKey string) string {
	return entryPath(cacheDir, logicalKey)
}

func ReadPayload(cacheDir, logicalKey string) (json.RawMessage, int64, error) {
	path := entryPath(cacheDir, logicalKey)
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, 0, err
	}

	var env Envelope
	if err := json.Unmarshal(b, &env); err != nil {
		return nil, 0, err
	}
	if env.Key != logicalKey {
		return nil, 0, fmt.Errorf("cache key mismatch")
	}
	if len(env.Payload) == 0 {
		return nil, 0, fmt.Errorf("cache payload empty")
	}
	return env.Payload, env.SavedAt, nil
}

func WritePayload(cacheDir, logicalKey string, payload []byte) error {
	if strings.TrimSpace(cacheDir) == "" || strings.TrimSpace(logicalKey) == "" || len(payload) == 0 {
		return nil
	}

	env := Envelope{
		Key:     logicalKey,
		SavedAt: time.Now().Unix(),
		Payload: json.RawMessage(payload),
	}
	b, err := json.Marshal(env)
	if err != nil {
		return err
	}
	return writeFileAtomic(entryPath(cacheDir, logicalKey), b, 0o600)
}

func DeletePayload(cacheDir, logicalKey string) {
	if strings.TrimSpace(cacheDir) == "" || strings.TrimSpace(logicalKey) == "" {
		return
	}
	_ = os.Remove(entryPath(cacheDir, logicalKey))
}

func ProviderTokenKey(provider, scope string) string {
	return logicalKey(provider+"_token", hashScopeTag("spdc_sha256", scope), "default")
}

func ProviderSecretKey(provider, sourceURL string) string {
	return logicalKey(provider+"_secret_dict", "global", hashScopeTag("url_sha256", sourceURL))
}

func ProviderLyricsKey(provider, trackID string) string {
	return logicalKey(provider+"_lyrics", "global", "track:"+strings.ToLower(strings.TrimSpace(trackID)))
}

func ProviderSessionKey(provider, scope string) string {
	scope = strings.TrimSpace(scope)
	if scope == "" {
		scope = "default"
	}
	return logicalKey(provider+"_session", "global", scope)
}

func FinalLyricsKey(identityTuple string) string {
	return logicalKey("final_lyrics", "global", "meta:"+identityTuple)
}
