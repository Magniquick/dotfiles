package unifiedlyrics

import (
	"context"
	"errors"
	"testing"

	"unified-lyrics-api/internal/lyricsprovider"
)

type stubProvider struct {
	name     string
	supports bool
	result   *lyricsprovider.Result
	err      error
}

func (p stubProvider) Name() string { return p.name }

func (p stubProvider) Supports(lyricsprovider.Request) bool { return p.supports }

func (p stubProvider) Fetch(context.Context, lyricsprovider.Request) (*lyricsprovider.Result, error) {
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
