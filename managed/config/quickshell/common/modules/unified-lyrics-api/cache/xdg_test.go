package cache

import (
	"path/filepath"
	"testing"
)

func TestDefaultDir_UsesXDGCacheHome(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", "/tmp/xdg-cache-home-test")
	got := DefaultDir()
	want := filepath.Join("/tmp/xdg-cache-home-test", "quickshell", "unified-lyrics-api")
	if got != want {
		t.Fatalf("DefaultDir() = %q, want %q", got, want)
	}
}
