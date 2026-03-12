package spotify

import (
	"strings"
	"testing"
)

func TestCacheKeys_AreDeterministic(t *testing.T) {
	spdc := "  sample_spdc  "
	trackID := "AbC123"
	secretURL := "https://example.com/secret.json"

	tokenA := tokenCacheKey(spdc)
	tokenB := tokenCacheKey("sample_spdc")
	if tokenA != tokenB {
		t.Fatalf("token key mismatch: %q != %q", tokenA, tokenB)
	}

	lyricsA := lyricsCacheKey(trackID)
	lyricsB := lyricsCacheKey("abc123")
	if lyricsA != lyricsB {
		t.Fatalf("lyrics key mismatch: %q != %q", lyricsA, lyricsB)
	}

	secretA := secretCacheKey(secretURL)
	secretB := secretCacheKey(secretURL)
	if secretA != secretB {
		t.Fatalf("secret key mismatch: %q != %q", secretA, secretB)
	}
}

func TestCacheKeys_AreVersionedAndNamespaced(t *testing.T) {
	if !strings.HasPrefix(tokenCacheKey("x"), "unifiedlyrics:v1:spotify_token:") {
		t.Fatalf("unexpected token key prefix")
	}
	if !strings.HasPrefix(secretCacheKey("https://example.com"), "unifiedlyrics:v1:spotify_secret_dict:") {
		t.Fatalf("unexpected secret key prefix")
	}
	if !strings.HasPrefix(lyricsCacheKey("y"), "unifiedlyrics:v1:spotify_lyrics:") {
		t.Fatalf("unexpected lyrics key prefix")
	}
}
