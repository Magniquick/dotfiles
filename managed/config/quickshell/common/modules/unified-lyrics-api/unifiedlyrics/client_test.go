package unifiedlyrics

import (
	"context"
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"

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

func (p stubProvider) Fetch(ctx context.Context, req lyricsprovider.Request) (*lyricsprovider.Result, error) {
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

	got, err := client.Fetch(context.Background(), Request{TrackName: "Song", ArtistName: "Artist"})
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

	got, err := client.Fetch(context.Background(), Request{TrackName: "Song", ArtistName: "Artist"})
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

	got, err := client.Fetch(context.Background(), Request{TrackName: "Song", ArtistName: "Artist"})
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

	got, err := client.Fetch(context.Background(), Request{TrackName: "Song", ArtistName: "Artist"})
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

	got, err := client.Fetch(context.Background(), Request{TrackName: "Song", ArtistName: "Artist"})
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

	_, err := client.Fetch(context.Background(), Request{TrackName: "Song", ArtistName: "Artist", SPDC: "x", SpotifyTrackRef: "spotify:track:1"})
	if err == nil || err.Error() != "spotify and netease and lrclib failed" {
		t.Fatalf("err = %v, want combined provider failure", err)
	}
}

func TestFetch_DisabledCacheStopsAfterNeteaseWordSynced(t *testing.T) {
	spotifyCalls := 0
	client := &Client{
		cacheDir: "/dev/null",
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

	got, err := client.Fetch(context.Background(), Request{
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

func TestFetch_DisabledCacheCancelsSpotifyAfterNeteaseWordSynced(t *testing.T) {
	spotifyStarted := make(chan struct{})
	spotifyCanceled := make(chan struct{})
	var closeSpotifyStarted sync.Once
	var closeSpotifyCanceled sync.Once

	client := &Client{
		cacheDir: "/dev/null",
		providers: []lyricsprovider.Provider{
			stubProvider{
				name:     "spotify",
				supports: true,
				fetch: func(ctx context.Context) (*lyricsprovider.Result, error) {
					closeSpotifyStarted.Do(func() { close(spotifyStarted) })
					<-ctx.Done()
					closeSpotifyCanceled.Do(func() { close(spotifyCanceled) })
					return nil, ctx.Err()
				},
			},
			stubProvider{
				name:     "netease",
				supports: true,
				fetch: func(ctx context.Context) (*lyricsprovider.Result, error) {
					select {
					case <-spotifyStarted:
					case <-ctx.Done():
						return nil, ctx.Err()
					}
					return &lyricsprovider.Result{
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
					}, nil
				},
			},
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	got, err := client.Fetch(ctx, Request{
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
	select {
	case <-spotifyCanceled:
	case <-time.After(100 * time.Millisecond):
		t.Fatal("spotify provider was not canceled after word-synced netease result")
	}
}

func TestFetch_DisabledCacheKeepsSpotifyTiePreference(t *testing.T) {
	spotifyCalls := 0
	client := &Client{
		cacheDir: "/dev/null",
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

	got, err := client.Fetch(context.Background(), Request{
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

func TestFetch_DisabledCacheStartsTieCandidatesConcurrently(t *testing.T) {
	var spotifyCalls int
	var neteaseSawSpotifyStarted atomic.Bool
	spotifyStarted := make(chan struct{})
	var closeSpotifyStarted sync.Once

	client := &Client{
		cacheDir: "/dev/null",
		providers: []lyricsprovider.Provider{
			stubProvider{
				name:     "spotify",
				supports: true,
				calls:    &spotifyCalls,
				fetch: func(context.Context) (*lyricsprovider.Result, error) {
					closeSpotifyStarted.Do(func() { close(spotifyStarted) })
					return &lyricsprovider.Result{
						Provider: "spotify",
						SyncType: lyricsprovider.SyncTypeLine,
						Lines:    []lyricsprovider.Line{{StartTimeMs: "1000", Words: "spotify"}},
					}, nil
				},
			},
			stubProvider{
				name:     "netease",
				supports: true,
				fetch: func(context.Context) (*lyricsprovider.Result, error) {
					select {
					case <-spotifyStarted:
						neteaseSawSpotifyStarted.Store(true)
					case <-time.After(75 * time.Millisecond):
					}
					return &lyricsprovider.Result{
						Provider: "netease",
						SyncType: lyricsprovider.SyncTypeLine,
						Lines:    []lyricsprovider.Line{{StartTimeMs: "1000", Words: "netease"}},
					}, nil
				},
			},
		},
	}

	got, err := client.Fetch(context.Background(), Request{
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
	if !neteaseSawSpotifyStarted.Load() {
		t.Fatal("netease returned before spotify fetch started; providers were not raced")
	}
}

func TestFetch_DisabledCacheDoesNotStartLowerPriorityLRCLIB(t *testing.T) {
	lrclibStarted := make(chan struct{})
	client := &Client{
		cacheDir: "/dev/null",
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
				fetch: func(ctx context.Context) (*lyricsprovider.Result, error) {
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
	got, err := client.Fetch(context.Background(), Request{TrackName: "Song", ArtistName: "Artist"})
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

func TestFetch_DisabledCacheUsesLRCLIBFallbackAfterPrimaryFailures(t *testing.T) {
	client := &Client{
		cacheDir: "/dev/null",
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

	got, err := client.Fetch(context.Background(), Request{
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
