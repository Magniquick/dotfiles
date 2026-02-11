package spotifylyrics

import (
	"os"
	"path/filepath"
)

// defaultCacheDir returns an XDG-compliant cache directory for this library.
// On Linux, os.UserCacheDir() respects XDG_CACHE_HOME.
func defaultCacheDir() string {
	ucd, err := os.UserCacheDir()
	if err == nil && ucd != "" {
		return filepath.Join(ucd, "quickshell", "spotify-lyrics-api")
	}
	// Fallback: keep behavior functional even in weird environments.
	return filepath.Join(os.TempDir(), "spotify-lyrics-api")
}
