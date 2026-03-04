package spotifylyrics

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

const (
	cacheKeyPrefix   = "lyrics:v1"
	cacheKindToken   = "token"
	cacheKindSecret  = "secret_dict"
	cacheKindLyrics  = "lyrics"
	cacheKindFinal   = "final_lyrics"
	cacheSecretScope = "global"
	cacheTokenID     = "default"
)

type cacheEnvelope struct {
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

func cacheLogicalKey(kind, scope, id string) string {
	return fmt.Sprintf("%s:%s:%s:%s", cacheKeyPrefix, kind, scope, id)
}

func cacheEntryPath(cacheDir, logicalKey string) string {
	name := sha256Hex(logicalKey) + ".json"
	return filepath.Join(cacheDir, "entries", name)
}

func readCachePayload(cacheDir, logicalKey string) (json.RawMessage, int64, error) {
	path := cacheEntryPath(cacheDir, logicalKey)
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, 0, err
	}

	var env cacheEnvelope
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

func writeCachePayload(cacheDir, logicalKey string, payload []byte) error {
	if strings.TrimSpace(cacheDir) == "" || strings.TrimSpace(logicalKey) == "" || len(payload) == 0 {
		return nil
	}

	env := cacheEnvelope{
		Key:     logicalKey,
		SavedAt: time.Now().Unix(),
		Payload: json.RawMessage(payload),
	}
	b, err := json.Marshal(env)
	if err != nil {
		return err
	}
	return writeFileAtomic(cacheEntryPath(cacheDir, logicalKey), b, 0o600)
}

func deleteCachePayload(cacheDir, logicalKey string) {
	if strings.TrimSpace(cacheDir) == "" || strings.TrimSpace(logicalKey) == "" {
		return
	}
	_ = os.Remove(cacheEntryPath(cacheDir, logicalKey))
}

func tokenCacheKey(spdc string) string {
	scope := hashScopeTag("spdc_sha256", spdc)
	return cacheLogicalKey(cacheKindToken, scope, cacheTokenID)
}

func secretCacheKey(secretURL string) string {
	id := hashScopeTag("url_sha256", secretURL)
	return cacheLogicalKey(cacheKindSecret, cacheSecretScope, id)
}

func lyricsCacheKey(trackID string) string {
	scope := "global"
	id := "track:" + strings.ToLower(strings.TrimSpace(trackID))
	return cacheLogicalKey(cacheKindLyrics, scope, id)
}

func FinalLyricsCacheKey(identityTuple string) string {
	scope := "global"
	id := "meta:" + identityTuple
	return cacheLogicalKey(cacheKindFinal, scope, id)
}

func ReadUnifiedCachePayload(cacheDir, key string) (json.RawMessage, int64, error) {
	return readCachePayload(cacheDir, key)
}

func WriteUnifiedCachePayload(cacheDir, key string, payload []byte) error {
	return writeCachePayload(cacheDir, key, payload)
}
