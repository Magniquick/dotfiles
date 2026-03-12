package spotify

import (
	"encoding/json"
	"time"

	"unified-lyrics-api/cache"
)

const providerName = "spotify"

type lyricsCache struct {
	SavedAt int64           `json:"savedAt"`
	Body    json.RawMessage `json:"body"`
}

func tokenCacheKey(spdc string) string {
	return cache.ProviderTokenKey(providerName, spdc)
}

func secretCacheKey(secretURL string) string {
	return cache.ProviderSecretKey(providerName, secretURL)
}

func lyricsCacheKey(trackID string) string {
	return cache.ProviderLyricsKey(providerName, trackID)
}

func cacheEntryPath(cacheDir, logicalKey string) string {
	return cache.EntryPath(cacheDir, logicalKey)
}

func readCachePayload(cacheDir, logicalKey string) (json.RawMessage, int64, error) {
	return cache.ReadPayload(cacheDir, logicalKey)
}

func writeCachePayload(cacheDir, logicalKey string, payload []byte) error {
	return cache.WritePayload(cacheDir, logicalKey, payload)
}

func deleteCachePayload(cacheDir, logicalKey string) {
	cache.DeletePayload(cacheDir, logicalKey)
}

func readLyricsCache(cacheDir, cacheKey string, ttl time.Duration) (*LyricsResponse, bool) {
	if cacheDir == "" || cacheKey == "" || ttl <= 0 {
		return nil, false
	}

	b, savedAt, err := readCachePayload(cacheDir, cacheKey)
	if err != nil {
		return nil, false
	}

	var lc lyricsCache
	if err := json.Unmarshal(b, &lc); err != nil {
		return nil, false
	}
	if len(lc.Body) == 0 {
		return nil, false
	}
	if savedAt <= 0 || time.Since(time.Unix(savedAt, 0)) > ttl {
		return nil, false
	}

	var lr LyricsResponse
	if err := json.Unmarshal(lc.Body, &lr); err != nil {
		return nil, false
	}
	if lr.Lyrics.Lines == nil {
		return nil, false
	}
	return &lr, true
}

func writeLyricsCache(cacheDir, cacheKey string, body []byte) error {
	if cacheDir == "" || cacheKey == "" || len(body) == 0 {
		return nil
	}

	lc := lyricsCache{
		SavedAt: time.Now().Unix(),
		Body:    json.RawMessage(body),
	}
	b, err := json.Marshal(lc)
	if err != nil {
		return err
	}
	return writeCachePayload(cacheDir, cacheKey, b)
}
