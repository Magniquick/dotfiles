package spotifylyrics

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestFetchLatestSecret_TransformsAndSelectsLatest(t *testing.T) {
	// Minimal dict with 2 versions; upstream picks the *last key* in JSON order.
	// This is the "encoded" secret: for i=0, decode does b ^ 9.
	// For plaintext 'A' (65), encoded is 65 ^ 9 = 72.
	encodedV1 := []int{72}
	encodedV2 := []int{73} // plaintext 'B' (66): 66 ^ 9 = 75, so this isn't 'B'; we'll compute expected below.

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Put version "1" last to ensure we follow object order.
		_, _ = fmt.Fprintf(w, `{"2":%v,"1":%v}`, encodedV2, encodedV1)
	}))
	defer srv.Close()

	cachePath := filepath.Join(t.TempDir(), "secret_cache.json")
	hc := &http.Client{Timeout: 2 * time.Second}
	secret, ver, err := fetchLatestSecret(context.Background(), hc, srv.URL, cachePath)
	if err != nil {
		t.Fatal(err)
	}
	if ver != "1" {
		t.Fatalf("ver: got %q want %q", ver, "1")
	}

	// Decode expected for i=0: x ^ 9.
	want := fmt.Sprintf("%d", encodedV1[0]^9)
	if secret != want {
		t.Fatalf("secret: got %q want %q", secret, want)
	}
}

func TestFetchLatestSecret_UsesETagCacheOn304(t *testing.T) {
	var reqCount int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reqCount++
		if reqCount == 1 {
			w.Header().Set("ETag", `"v1"`)
			_, _ = fmt.Fprintf(w, `{"1":[72]}`)
			return
		}
		if inm := r.Header.Get("If-None-Match"); inm != `"v1"` {
			t.Fatalf("If-None-Match: got %q want %q", inm, `"v1"`)
		}
		w.WriteHeader(http.StatusNotModified)
	}))
	defer srv.Close()

	cachePath := filepath.Join(t.TempDir(), "secret_cache.json")
	hc := &http.Client{Timeout: 2 * time.Second}

	secret1, ver1, err := fetchLatestSecret(context.Background(), hc, srv.URL, cachePath)
	if err != nil {
		t.Fatal(err)
	}
	if ver1 != "1" || secret1 != "65" {
		t.Fatalf("first: ver=%q secret=%q", ver1, secret1)
	}
	if _, err := os.Stat(cachePath); err != nil {
		t.Fatalf("cache not written: %v", err)
	}

	secret2, ver2, err := fetchLatestSecret(context.Background(), hc, srv.URL, cachePath)
	if err != nil {
		t.Fatal(err)
	}
	if ver2 != "1" || secret2 != "65" {
		t.Fatalf("second: ver=%q secret=%q", ver2, secret2)
	}
	if reqCount != 2 {
		t.Fatalf("reqCount: got %d want %d", reqCount, 2)
	}
}
