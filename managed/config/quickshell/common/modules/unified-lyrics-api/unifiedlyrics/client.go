package unifiedlyrics

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"spotify-lyrics-api/spotifylyrics"
)

type Request struct {
	SPDC            string
	SpotifyTrackRef string
	TrackName       string
	ArtistName      string
	AlbumName       string
	DurationSeconds int
}

type Result struct {
	Source   string         `json:"source"`
	SyncType string         `json:"syncType"`
	Lines    []Line         `json:"lines"`
	Metadata ResultMetadata `json:"metadata"`
}

type ResultMetadata struct {
	Provider string `json:"provider"`
}

type cacheEntry struct {
	result    Result
	expiresAt time.Time
}

type Client struct {
	mu       sync.RWMutex
	cache    map[string]cacheEntry
	cacheTTL time.Duration
}

func New() *Client {
	return &Client{
		cache:    make(map[string]cacheEntry),
		cacheTTL: 30 * time.Minute,
	}
}

func (c *Client) Fetch(ctx context.Context, req Request) (*Result, error) {
	if c == nil {
		return nil, errors.New("nil client")
	}

	cacheKey := buildCacheKey(req)
	if cached := c.getCached(cacheKey); cached != nil {
		return cached, nil
	}

	var spotifyOut *Result
	var lrclibOut *Result
	var spotifyErr error
	var lrclibErr error

	spdc := strings.TrimSpace(req.SPDC)
	spotifyRef := strings.TrimSpace(req.SpotifyTrackRef)
	if spdc != "" && spotifyRef != "" {
		sc, err := spotifylyrics.New(spdc)
		if err == nil {
			lr, err := sc.GetLyricsFromURL(ctx, spotifyRef)
			if err == nil && lr != nil && len(lr.Lyrics.Lines) > 0 {
				lines := make([]Line, 0, len(lr.Lyrics.Lines))
				for _, ln := range lr.Lyrics.Lines {
					lines = append(lines, Line{
						StartTimeMs: strings.TrimSpace(ln.StartTimeMs),
						Words:       ln.Words,
					})
				}
				syncType := strings.TrimSpace(lr.Lyrics.SyncType)
				spotifyOut = newResult("spotify_normal", syncType, lines)
				if strings.EqualFold(syncType, "LINE_SYNCED") {
					spotifyOut.Source = "spotify_synced"
					c.putCached(cacheKey, spotifyOut)
					return spotifyOut, nil
				}
			}
			if err != nil {
				spotifyErr = err
			}
		} else {
			spotifyErr = err
		}
	}

	track := strings.TrimSpace(req.TrackName)
	artist := strings.TrimSpace(req.ArtistName)
	album := strings.TrimSpace(req.AlbumName)
	if track != "" && artist != "" {
		lc := NewLrcLibClient()
		lr, err := lc.GetLyrics(ctx, track, artist, album, req.DurationSeconds)
		if err == nil && lr != nil && len(lr.Lines) > 0 {
			syncType := strings.TrimSpace(lr.SyncType)
			lrclibOut = newResult("lrclib_normal", syncType, lr.Lines)
			if strings.EqualFold(syncType, "LINE_SYNCED") {
				lrclibOut.Source = "lrclib_synced"
				c.putCached(cacheKey, lrclibOut)
				return lrclibOut, nil
			}
		}
		if err != nil {
			lrclibErr = err
		}
	}

	if spotifyOut != nil {
		c.putCached(cacheKey, spotifyOut)
		return spotifyOut, nil
	}
	if lrclibOut != nil {
		c.putCached(cacheKey, lrclibOut)
		return lrclibOut, nil
	}

	if spotifyErr != nil && lrclibErr != nil {
		return nil, errors.New("spotify and lrclib failed")
	}
	if spotifyErr != nil {
		return nil, spotifyErr
	}
	if lrclibErr != nil {
		return nil, lrclibErr
	}
	return nil, errors.New("no lyrics available")
}

func providerFromSource(source string) string {
	switch {
	case strings.HasPrefix(source, "spotify_"):
		return "spotify"
	case strings.HasPrefix(source, "lrclib_"):
		return "lrclib"
	default:
		return ""
	}
}

func newResult(source, syncType string, lines []Line) *Result {
	return &Result{
		Source:   source,
		SyncType: syncType,
		Lines:    cloneLines(lines),
		Metadata: ResultMetadata{
			Provider: providerFromSource(source),
		},
	}
}

func cloneLines(lines []Line) []Line {
	if len(lines) == 0 {
		return []Line{}
	}
	out := make([]Line, len(lines))
	copy(out, lines)
	return out
}

func cloneResult(r *Result) *Result {
	if r == nil {
		return nil
	}
	return &Result{
		Source:   r.Source,
		SyncType: r.SyncType,
		Lines:    cloneLines(r.Lines),
		Metadata: r.Metadata,
	}
}

func buildCacheKey(req Request) string {
	return fmt.Sprintf("%s\x1f%s\x1f%s\x1f%d",
		strings.TrimSpace(req.SpotifyTrackRef),
		strings.ToLower(strings.TrimSpace(req.TrackName)),
		strings.ToLower(strings.TrimSpace(req.ArtistName)),
		req.DurationSeconds,
	)
}

func (c *Client) getCached(key string) *Result {
	if key == "" {
		return nil
	}
	now := time.Now()

	c.mu.RLock()
	entry, ok := c.cache[key]
	c.mu.RUnlock()
	if !ok {
		return nil
	}
	if now.After(entry.expiresAt) {
		c.mu.Lock()
		delete(c.cache, key)
		c.mu.Unlock()
		return nil
	}
	return cloneResult(&entry.result)
}

func (c *Client) putCached(key string, r *Result) {
	if key == "" || r == nil || len(r.Lines) == 0 {
		return
	}
	exp := time.Now().Add(c.cacheTTL)
	clone := cloneResult(r)

	c.mu.Lock()
	c.cache[key] = cacheEntry{
		result:    *clone,
		expiresAt: exp,
	}
	c.mu.Unlock()
}
