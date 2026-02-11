package spotifylyrics

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLyricsCache_Roundtrip(t *testing.T) {
	dir := t.TempDir()
	trackID := "5f8eCNwTlr0RJopE9vQ6mB"

	body := []byte(`{"lyrics":{"syncType":"LINE_SYNCED","lines":[{"startTimeMs":"1000","words":"hello","syllables":[],"endTimeMs":"2000"}]}}`)
	if err := writeLyricsCache(dir, trackID, body); err != nil {
		t.Fatalf("writeLyricsCache: %v", err)
	}

	// Ensure file exists where we expect it.
	if _, err := os.Stat(lyricsCachePath(dir, trackID)); err != nil {
		t.Fatalf("cache file missing: %v", err)
	}

	lr, ok := readLyricsCache(dir, trackID, 24*time.Hour)
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

	// Write a cache file with an old timestamp.
	path := lyricsCachePath(dir, trackID)
	old := []byte(`{"savedAt":1,"body":{"lyrics":{"syncType":"LINE_SYNCED","lines":[{"startTimeMs":"1000","words":"hello","syllables":[],"endTimeMs":"2000"}]}}}`)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(path, old, 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}

	if _, ok := readLyricsCache(dir, trackID, 1*time.Second); ok {
		t.Fatalf("expected cache miss due to TTL")
	}
}
