package spotifylyrics

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLyricsCache_Roundtrip(t *testing.T) {
	dir := t.TempDir()
	trackID := "5f8eCNwTlr0RJopE9vQ6mB"
	key := lyricsCacheKey(trackID)

	body := []byte(`{"lyrics":{"syncType":"LINE_SYNCED","lines":[{"startTimeMs":"1000","words":"hello","syllables":[],"endTimeMs":"2000"}]}}`)
	if err := writeLyricsCache(dir, key, body); err != nil {
		t.Fatalf("writeLyricsCache: %v", err)
	}

	// Ensure file exists where we expect it.
	if _, err := os.Stat(cacheEntryPath(dir, key)); err != nil {
		t.Fatalf("cache file missing: %v", err)
	}

	lr, ok := readLyricsCache(dir, key, 24*time.Hour)
	if !ok || lr == nil {
		t.Fatalf("expected cache hit")
	}
	if lr.Lyrics.SyncType != "LINE_SYNCED" {
		t.Fatalf("unexpected syncType: %q", lr.Lyrics.SyncType)
	}
	if len(lr.Lyrics.Lines) != 1 || lr.Lyrics.Lines[0].Words != "hello" {
		t.Fatalf("unexpected lines: %#v", lr.Lyrics.Lines)
	}
}

func TestLyricsCache_TTLExpiry(t *testing.T) {
	dir := t.TempDir()
	trackID := "5f8eCNwTlr0RJopE9vQ6mB"
	key := lyricsCacheKey(trackID)

	// Write an envelope with an old timestamp.
	payload, err := json.Marshal(lyricsCache{
		SavedAt: 1,
		Body:    json.RawMessage(`{"lyrics":{"syncType":"LINE_SYNCED","lines":[{"startTimeMs":"1000","words":"hello","syllables":[],"endTimeMs":"2000"}]}}`),
	})
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}
	old, err := json.Marshal(cacheEnvelope{
		Key:     key,
		SavedAt: 1,
		Payload: payload,
	})
	if err != nil {
		t.Fatalf("marshal envelope: %v", err)
	}
	path := cacheEntryPath(dir, key)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(path, old, 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}

	if _, ok := readLyricsCache(dir, key, 1*time.Second); ok {
		t.Fatalf("expected cache miss due to TTL")
	}
}
