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

// Envelope is the serialized wrapper stored for each cache entry.
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

func cacheDisabled(cacheDir string) bool {
	dir := strings.TrimSpace(cacheDir)
	cleanDir := filepath.Clean(dir)
	return dir == "/dev/null" ||
		dir == os.DevNull ||
		cleanDir == filepath.Clean("/dev/null") ||
		cleanDir == filepath.Clean(os.DevNull)
}

// EntryPath returns the filesystem path for a logical cache key.
func EntryPath(cacheDir, logicalKey string) string {
	return entryPath(cacheDir, logicalKey)
}

// ReadPayload loads a cache entry payload and saved timestamp.
func ReadPayload(cacheDir, logicalKey string) (json.RawMessage, int64, error) {
	path := entryPath(cacheDir, logicalKey)
	if cacheDisabled(cacheDir) {
		return nil, 0, &os.PathError{Op: "open", Path: path, Err: os.ErrNotExist}
	}
	//nolint:gosec // Cache entry paths are cacheDir plus a sha256-derived filename.
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

// WritePayload stores a payload for a logical cache key.
func WritePayload(cacheDir, logicalKey string, payload []byte) error {
	if strings.TrimSpace(cacheDir) == "" || strings.TrimSpace(logicalKey) == "" || len(payload) == 0 {
		return nil
	}
	if cacheDisabled(cacheDir) {
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

// DeletePayload removes a payload for a logical cache key.
func DeletePayload(cacheDir, logicalKey string) {
	if strings.TrimSpace(cacheDir) == "" || strings.TrimSpace(logicalKey) == "" {
		return
	}
	if cacheDisabled(cacheDir) {
		return
	}
	_ = os.Remove(entryPath(cacheDir, logicalKey))
}

// ProviderTokenKey returns the token cache key for a provider scope.
func ProviderTokenKey(provider, scope string) string {
	return logicalKey(provider+"_token", hashScopeTag("spdc_sha256", scope), "default")
}

// ProviderSecretKey returns the secret dictionary cache key for a provider URL.
func ProviderSecretKey(provider, sourceURL string) string {
	return logicalKey(provider+"_secret_dict", "global", hashScopeTag("url_sha256", sourceURL))
}

// ProviderLyricsKey returns the lyrics cache key for a provider track ID.
func ProviderLyricsKey(provider, trackID string) string {
	return logicalKey(provider+"_lyrics", "global", "track:"+strings.ToLower(strings.TrimSpace(trackID)))
}

// ProviderSessionKey returns the session cache key for a provider scope.
func ProviderSessionKey(provider, scope string) string {
	scope = strings.TrimSpace(scope)
	if scope == "" {
		scope = "default"
	}
	return logicalKey(provider+"_session", "global", scope)
}

// FinalLyricsKey returns the normalized final-result cache key.
func FinalLyricsKey(identityTuple string) string {
	return logicalKey("final_lyrics", "global", "meta:"+identityTuple)
}
