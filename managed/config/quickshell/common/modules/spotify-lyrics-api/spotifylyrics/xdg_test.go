package spotifylyrics

import (
	"path/filepath"
	"testing"
)

func TestDefaultCacheDir_UsesXDGCacheHome(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", "/tmp/xdg-cache-home-test")
	got := defaultCacheDir()
	want := filepath.Join("/tmp/xdg-cache-home-test", "quickshell", "spotify-lyrics-api")
	if got != want {
		t.Fatalf("defaultCacheDir() = %q, want %q", got, want)
	}
}
