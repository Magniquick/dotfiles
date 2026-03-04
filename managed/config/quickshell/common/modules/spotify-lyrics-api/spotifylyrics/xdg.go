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
	home, homeErr := os.UserHomeDir()
	if homeErr == nil && home != "" {
		return filepath.Join(home, ".cache", "quickshell", "spotify-lyrics-api")
	}
	// Final sane default when home lookup is unavailable.
	return filepath.Join(".cache", "quickshell", "spotify-lyrics-api")
}
