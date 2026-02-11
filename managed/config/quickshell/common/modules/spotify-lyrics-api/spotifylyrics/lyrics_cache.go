package spotifylyrics

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

type lyricsCache struct {
	SavedAt int64           `json:"savedAt"`
	Body    json.RawMessage `json:"body"`
}

func lyricsCachePath(cacheDir, trackID string) string {
	// Avoid path issues and keep filenames deterministic even if the input isn't.
	sum := sha256.Sum256([]byte(trackID))
	name := hex.EncodeToString(sum[:]) + ".json"
	return filepath.Join(cacheDir, name)
}

func readLyricsCache(cacheDir, trackID string, ttl time.Duration) (*LyricsResponse, bool) {
	if cacheDir == "" || trackID == "" || ttl <= 0 {
		return nil, false
	}

	path := lyricsCachePath(cacheDir, trackID)
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, false
	}

	var lc lyricsCache
	if err := json.Unmarshal(b, &lc); err != nil {
		return nil, false
	}
	if len(lc.Body) == 0 || lc.SavedAt <= 0 {
		return nil, false
	}
	if time.Since(time.Unix(lc.SavedAt, 0)) > ttl {
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

func writeLyricsCache(cacheDir, trackID string, body []byte) error {
	if cacheDir == "" || trackID == "" || len(body) == 0 {
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
	path := lyricsCachePath(cacheDir, trackID)
	return writeFileAtomic(path, b, 0o600)
}
