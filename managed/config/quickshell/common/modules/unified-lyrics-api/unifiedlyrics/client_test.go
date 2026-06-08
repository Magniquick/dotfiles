package unifiedlyrics

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"unified-lyrics-api/cache"
	"unified-lyrics-api/internal/lyricsprovider"
)

type stubProvider struct {
	name     string
	supports bool
	result   *lyricsprovider.Result
	err      error
	calls    *int
	fetch    func(context.Context) (*lyricsprovider.Result, error)
}

func (p stubProvider) Name() string { return p.name }

func (p stubProvider) Supports(lyricsprovider.Request) bool { return p.supports }

func (p stubProvider) Fetch(ctx context.Context, _ lyricsprovider.Request) (*lyricsprovider.Result, error) {
	if p.calls != nil {
		*p.calls++
	}
	if p.fetch != nil {
		return p.fetch(ctx)
	}
	return p.result, p.err
}

func TestFetch_PrefersFirstSameTierByRegistryOrder(t *testing.T) {
	client := &Client{
		cacheDir: t.TempDir(),
		providers: []lyricsprovider.Provider{
			stubProvider{
				name:     "spotify",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "spotify",
					SyncType: lyricsprovider.SyncTypeLine,
					Lines:    []lyricsprovider.Line{{StartTimeMs: "1", Words: "spotify"}},
				},
			},
			stubProvider{
				name:     "netease",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "netease",
					SyncType: lyricsprovider.SyncTypeLine,
					Lines:    []lyricsprovider.Line{{StartTimeMs: "1", Words: "netease"}},
				},
			},
		},
	}

	got, err := client.Fetch(t.Context(), Request{TrackName: "Song", ArtistName: "Artist"})
	if err != nil {
		t.Fatal(err)
	}
	if got.Source != "spotify_synced" {
		t.Fatalf("Source = %q, want spotify_synced", got.Source)
	}
}

func TestFetch_PrefersSyncedOverEarlierUnsynced(t *testing.T) {
	client := &Client{
		cacheDir: t.TempDir(),
		providers: []lyricsprovider.Provider{
			stubProvider{
				name:     "spotify",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "spotify",
					SyncType: lyricsprovider.SyncTypeNone,
					Lines:    []lyricsprovider.Line{{Words: "spotify"}},
				},
			},
			stubProvider{
				name:     "netease",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "netease",
					SyncType: lyricsprovider.SyncTypeLine,
					Lines:    []lyricsprovider.Line{{StartTimeMs: "1", Words: "netease"}},
				},
			},
		},
	}

	got, err := client.Fetch(t.Context(), Request{TrackName: "Song", ArtistName: "Artist"})
	if err != nil {
		t.Fatal(err)
	}
	if got.Source != "netease_synced" {
		t.Fatalf("Source = %q, want netease_synced", got.Source)
	}
}

func TestFetch_PrefersWordSyncedOverEarlierLineSynced(t *testing.T) {
	client := &Client{
		cacheDir: t.TempDir(),
		providers: []lyricsprovider.Provider{
			stubProvider{
				name:     "spotify",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "spotify",
					SyncType: lyricsprovider.SyncTypeLine,
					Lines:    []lyricsprovider.Line{{StartTimeMs: "1000", Words: "spotify"}},
				},
			},
			stubProvider{
				name:     "netease",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "netease",
					SyncType: lyricsprovider.SyncTypeWord,
					Lines: []lyricsprovider.Line{{
						StartTimeMs: "1000",
						EndTimeMs:   "2000",
						Words:       "netease",
						Segments: []lyricsprovider.Segment{{
							StartTimeMs: "1000",
							EndTimeMs:   "1500",
							Text:        "nete",
						}},
					}},
				},
			},
		},
	}

	got, err := client.Fetch(t.Context(), Request{TrackName: "Song", ArtistName: "Artist"})
	if err != nil {
		t.Fatal(err)
	}
	if got.Source != "netease_word" {
		t.Fatalf("Source = %q, want netease_word", got.Source)
	}
}

func TestFetch_PrefersFirstUnsyncedWhenNoSyncedExists(t *testing.T) {
	client := &Client{
		cacheDir: t.TempDir(),
		providers: []lyricsprovider.Provider{
			stubProvider{
				name:     "spotify",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "spotify",
					SyncType: lyricsprovider.SyncTypeNone,
					Lines:    []lyricsprovider.Line{{Words: "spotify"}},
				},
			},
			stubProvider{
				name:     "netease",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "netease",
					SyncType: lyricsprovider.SyncTypeNone,
					Lines:    []lyricsprovider.Line{{Words: "netease"}},
				},
			},
		},
	}

	got, err := client.Fetch(t.Context(), Request{TrackName: "Song", ArtistName: "Artist"})
	if err != nil {
		t.Fatal(err)
	}
	if got.Source != "spotify_normal" {
		t.Fatalf("Source = %q, want spotify_normal", got.Source)
	}
}

func TestFetch_SkipsUnsupportedProviders(t *testing.T) {
	client := &Client{
		cacheDir: t.TempDir(),
		providers: []lyricsprovider.Provider{
			stubProvider{name: "spotify", supports: false},
			stubProvider{
				name:     "netease",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "netease",
					SyncType: lyricsprovider.SyncTypeNone,
					Lines:    []lyricsprovider.Line{{Words: "netease"}},
				},
			},
		},
	}

	got, err := client.Fetch(t.Context(), Request{TrackName: "Song", ArtistName: "Artist"})
	if err != nil {
		t.Fatal(err)
	}
	if got.Source != "netease_normal" {
		t.Fatalf("Source = %q, want netease_normal", got.Source)
	}
}

func TestFetch_ReportsCombinedProviderFailure(t *testing.T) {
	client := &Client{
		cacheDir: t.TempDir(),
		providers: []lyricsprovider.Provider{
			stubProvider{name: "spotify", supports: true, err: errors.New("nope")},
			stubProvider{name: "netease", supports: true, err: errors.New("nope")},
			stubProvider{name: "lrclib", supports: true, err: errors.New("nope")},
		},
	}

	_, err := client.Fetch(t.Context(), Request{
		TrackName:       "Song",
		ArtistName:      "Artist",
		SPDC:            "x",
		SpotifyTrackRef: "spotify:track:1",
	})
	if err == nil || err.Error() != "spotify and netease and lrclib failed" {
		t.Fatalf("err = %v, want combined provider failure", err)
	}
}

func TestFetch_NoCacheSkipsFinalCacheReadAndWrite(t *testing.T) {
	cacheDir := t.TempDir()
	req := Request{TrackName: "Song", ArtistName: "Artist"}
	tuple := identityTuple(req)
	cached := finalLyricsCachePayload{
		Result: Result{
			Source:   "cached_synced",
			SyncType: lyricsprovider.SyncTypeLine,
			Lines:    []Line{{StartTimeMs: "1", Words: "cached"}},
			Metadata: ResultMetadata{Provider: "cached"},
		},
		IdentityTuple: tuple,
	}
	cachedPayload, err := json.Marshal(cached)
	if err != nil {
		t.Fatal(err)
	}
	if err := cache.WritePayload(cacheDir, cache.FinalLyricsKey(tuple), cachedPayload); err != nil {
		t.Fatal(err)
	}

	providerCalls := 0
	client := &Client{
		cacheDir: cacheDir,
		noCache:  true,
		providers: []lyricsprovider.Provider{
			stubProvider{
				name:     "netease",
				supports: true,
				calls:    &providerCalls,
				result: &lyricsprovider.Result{
					Provider: "netease",
					SyncType: lyricsprovider.SyncTypeWord,
					Lines: []lyricsprovider.Line{{
						StartTimeMs: "1000",
						EndTimeMs:   "2000",
						Words:       "fresh",
						Segments: []lyricsprovider.Segment{{
							StartTimeMs: "1000",
							EndTimeMs:   "1500",
							Text:        "fresh",
						}},
					}},
				},
			},
		},
	}

	got, err := client.Fetch(t.Context(), req)
	if err != nil {
		t.Fatal(err)
	}
	if providerCalls != 1 {
		t.Fatalf("provider calls = %d, want 1", providerCalls)
	}
	if got.Source != "netease_word" {
		t.Fatalf("Source = %q, want netease_word", got.Source)
	}
	payload, _, err := cache.ReadPayload(cacheDir, cache.FinalLyricsKey(tuple))
	if err != nil || string(payload) != string(cachedPayload) {
		t.Fatalf("final cache was unexpectedly rewritten")
	}
}

func TestFetch_NoCacheDoesNotCreateFinalCache(t *testing.T) {
	cacheDir := t.TempDir()
	client := &Client{
		cacheDir: cacheDir,
		noCache:  true,
		providers: []lyricsprovider.Provider{
			stubProvider{
				name:     "netease",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "netease",
					SyncType: lyricsprovider.SyncTypeLine,
					Lines:    []lyricsprovider.Line{{StartTimeMs: "1000", Words: "fresh"}},
				},
			},
		},
	}

	_, err := client.Fetch(t.Context(), Request{TrackName: "Song", ArtistName: "Artist"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(cacheDir, "entries")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("entries dir stat err = %v, want os.ErrNotExist", err)
	}
}

func TestFetch_NoCacheStopsAfterNeteaseWordSynced(t *testing.T) {
	spotifyCalls := 0
	client := &Client{
		cacheDir: t.TempDir(),
		noCache:  true,
		providers: []lyricsprovider.Provider{
			stubProvider{
				name:     "spotify",
				supports: true,
				calls:    &spotifyCalls,
				result: &lyricsprovider.Result{
					Provider: "spotify",
					SyncType: lyricsprovider.SyncTypeLine,
					Lines:    []lyricsprovider.Line{{StartTimeMs: "1000", Words: "spotify"}},
				},
			},
			stubProvider{
				name:     "netease",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "netease",
					SyncType: lyricsprovider.SyncTypeWord,
					Lines: []lyricsprovider.Line{{
						StartTimeMs: "1000",
						EndTimeMs:   "2000",
						Words:       "netease",
						Segments: []lyricsprovider.Segment{{
							StartTimeMs: "1000",
							EndTimeMs:   "1500",
							Text:        "nete",
						}},
					}},
				},
			},
			stubProvider{
				name:     "lrclib",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "lrclib",
					SyncType: lyricsprovider.SyncTypeLine,
					Lines:    []lyricsprovider.Line{{StartTimeMs: "1", Words: "lrclib"}},
				},
			},
		},
	}

	got, err := client.Fetch(t.Context(), Request{
		SPDC:            "x",
		SpotifyTrackRef: "spotify:track:1",
		TrackName:       "Song",
		ArtistName:      "Artist",
	})
	if err != nil {
		t.Fatal(err)
	}
	if got.Source != "netease_word" {
		t.Fatalf("Source = %q, want netease_word", got.Source)
	}
}

func TestFetch_NoCacheKeepsSpotifyTiePreference(t *testing.T) {
	spotifyCalls := 0
	client := &Client{
		cacheDir: t.TempDir(),
		noCache:  true,
		providers: []lyricsprovider.Provider{
			stubProvider{
				name:     "spotify",
				supports: true,
				calls:    &spotifyCalls,
				result: &lyricsprovider.Result{
					Provider: "spotify",
					SyncType: lyricsprovider.SyncTypeLine,
					Lines:    []lyricsprovider.Line{{StartTimeMs: "1000", Words: "spotify"}},
				},
			},
			stubProvider{
				name:     "netease",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "netease",
					SyncType: lyricsprovider.SyncTypeLine,
					Lines:    []lyricsprovider.Line{{StartTimeMs: "1000", Words: "netease"}},
				},
			},
			stubProvider{
				name:     "lrclib",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "lrclib",
					SyncType: lyricsprovider.SyncTypeLine,
					Lines:    []lyricsprovider.Line{{StartTimeMs: "1", Words: "lrclib"}},
				},
			},
		},
	}

	got, err := client.Fetch(t.Context(), Request{
		SPDC:            "x",
		SpotifyTrackRef: "spotify:track:1",
		TrackName:       "Song",
		ArtistName:      "Artist",
	})
	if err != nil {
		t.Fatal(err)
	}
	if got.Source != "spotify_synced" {
		t.Fatalf("Source = %q, want spotify_synced", got.Source)
	}
	if spotifyCalls != 1 {
		t.Fatalf("spotify calls = %d, want 1", spotifyCalls)
	}
}

func TestFetch_NoCacheDoesNotStartLowerPriorityLRCLIB(t *testing.T) {
	lrclibStarted := make(chan struct{})
	client := &Client{
		cacheDir: t.TempDir(),
		noCache:  true,
		providers: []lyricsprovider.Provider{
			stubProvider{name: "spotify", supports: false},
			stubProvider{
				name:     "netease",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "netease",
					SyncType: lyricsprovider.SyncTypeLine,
					Lines:    []lyricsprovider.Line{{StartTimeMs: "1000", Words: "netease"}},
				},
			},
			stubProvider{
				name:     "lrclib",
				supports: true,
				fetch: func(_ context.Context) (*lyricsprovider.Result, error) {
					close(lrclibStarted)
					return &lyricsprovider.Result{
						Provider: "lrclib",
						SyncType: lyricsprovider.SyncTypeLine,
						Lines:    []lyricsprovider.Line{{StartTimeMs: "1000", Words: "lrclib"}},
					}, nil
				},
			},
		},
	}

	start := time.Now()
	got, err := client.Fetch(t.Context(), Request{TrackName: "Song", ArtistName: "Artist"})
	if err != nil {
		t.Fatal(err)
	}
	if elapsed := time.Since(start); elapsed > 100*time.Millisecond {
		t.Fatalf("Fetch waited %s for lower-priority lrclib", elapsed)
	}
	if got.Source != "netease_synced" {
		t.Fatalf("Source = %q, want netease_synced", got.Source)
	}
	select {
	case <-lrclibStarted:
		t.Fatal("lrclib provider started even though it could not beat netease")
	default:
	}
}

func TestFetch_NoCacheUsesLRCLIBFallbackAfterPrimaryFailures(t *testing.T) {
	client := &Client{
		cacheDir: t.TempDir(),
		noCache:  true,
		providers: []lyricsprovider.Provider{
			stubProvider{name: "spotify", supports: true, err: errors.New("spotify failed")},
			stubProvider{name: "netease", supports: true, err: errors.New("netease failed")},
			stubProvider{
				name:     "lrclib",
				supports: true,
				result: &lyricsprovider.Result{
					Provider: "lrclib",
					SyncType: lyricsprovider.SyncTypeLine,
					Lines:    []lyricsprovider.Line{{StartTimeMs: "1000", Words: "lrclib"}},
				},
			},
		},
	}

	got, err := client.Fetch(t.Context(), Request{
		SPDC:            "x",
		SpotifyTrackRef: "spotify:track:1",
		TrackName:       "Song",
		ArtistName:      "Artist",
	})
	if err != nil {
		t.Fatal(err)
	}
	if got.Source != "lrclib_synced" {
		t.Fatalf("Source = %q, want lrclib_synced", got.Source)
	}
}
