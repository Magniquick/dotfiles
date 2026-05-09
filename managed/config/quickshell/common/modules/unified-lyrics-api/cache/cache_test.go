package cache

import (
	"errors"
	"os"
	"testing"
)

func disabledCacheDirs() []string {
	dirs := []string{"/dev/null"}
	if os.DevNull != "/dev/null" {
		dirs = append(dirs, os.DevNull)
	}
	return dirs
}

func TestReadPayloadDisabledCacheReturnsMiss(t *testing.T) {
	for _, dir := range disabledCacheDirs() {
		t.Run(dir, func(t *testing.T) {
			payload, savedAt, err := ReadPayload(dir, "lyrics-key")
			if err == nil {
				t.Fatal("ReadPayload returned nil error for disabled cache")
			}
			if !errors.Is(err, os.ErrNotExist) {
				t.Fatalf("ReadPayload error = %v, want os.ErrNotExist", err)
			}
			if payload != nil {
				t.Fatalf("ReadPayload payload = %q, want nil", string(payload))
			}
			if savedAt != 0 {
				t.Fatalf("ReadPayload savedAt = %d, want 0", savedAt)
			}
		})
	}
}

func TestWritePayloadDisabledCacheNoops(t *testing.T) {
	for _, dir := range disabledCacheDirs() {
		t.Run(dir, func(t *testing.T) {
			if err := WritePayload(dir, "lyrics-key", []byte(`{"ok":true}`)); err != nil {
				t.Fatalf("WritePayload returned error for disabled cache: %v", err)
			}
		})
	}
}

func TestDeletePayloadDisabledCacheNoops(t *testing.T) {
	for _, dir := range disabledCacheDirs() {
		t.Run(dir, func(_ *testing.T) {
			DeletePayload(dir, "lyrics-key")
		})
	}
}
