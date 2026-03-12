package cache

import (
	"os"
	"path/filepath"
)

func DefaultDir() string {
	ucd, err := os.UserCacheDir()
	if err == nil && ucd != "" {
		return filepath.Join(ucd, "quickshell", "unified-lyrics-api")
	}
	home, homeErr := os.UserHomeDir()
	if homeErr == nil && home != "" {
		return filepath.Join(home, ".cache", "quickshell", "unified-lyrics-api")
	}
	return filepath.Join(".cache", "quickshell", "unified-lyrics-api")
}
