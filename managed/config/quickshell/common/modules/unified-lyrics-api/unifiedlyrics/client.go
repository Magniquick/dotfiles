package unifiedlyrics

import (
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"strings"

	"spotify-lyrics-api/spotifylyrics"
)

type Request struct {
	SPDC            string
	SpotifyTrackRef string
	TrackName       string
	ArtistName      string
	AlbumName       string
	LengthMicros    string
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

type Client struct {
	spotifyCacheDir string
}

func New(spotifyCacheDir string) *Client {
	return &Client{
		spotifyCacheDir: strings.TrimSpace(spotifyCacheDir),
	}
}

func (c *Client) Fetch(ctx context.Context, req Request) (*Result, error) {
	if c == nil {
		return nil, errors.New("nil client")
	}
	tuple := identityTuple(req)
	if tuple != "" {
		key := spotifylyrics.FinalLyricsCacheKey(tuple)
		if payload, _, err := spotifylyrics.ReadUnifiedCachePayload(c.spotifyCacheDir, key); err == nil {
			var cached finalLyricsCachePayload
			if json.Unmarshal(payload, &cached) == nil && len(cached.Result.Lines) > 0 {
				return cloneResult(&cached.Result), nil
			}
		}
	}

	var spotifyOut *Result
	var lrclibOut *Result
	var spotifyErr error
	var lrclibErr error

	spdc := strings.TrimSpace(req.SPDC)
	spotifyRef := strings.TrimSpace(req.SpotifyTrackRef)
	if spdc != "" && spotifyRef != "" {
		sc, err := spotifylyrics.NewWithCacheDir(spdc, c.spotifyCacheDir)
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
	durationSeconds := durationSecondsFromMicros(req.LengthMicros)
	if track != "" && artist != "" {
		lc := NewLrcLibClient()
		lr, err := lc.GetLyrics(ctx, track, artist, album, durationSeconds)
		if err == nil && lr != nil && len(lr.Lines) > 0 {
			syncType := strings.TrimSpace(lr.SyncType)
			lrclibOut = newResult("lrclib_normal", syncType, lr.Lines)
			if strings.EqualFold(syncType, "LINE_SYNCED") {
				lrclibOut.Source = "lrclib_synced"
				return lrclibOut, nil
			}
		}
		if err != nil {
			lrclibErr = err
		}
	}

	if spotifyOut != nil {
		c.writeFinalCache(tuple, spotifyOut)
		return spotifyOut, nil
	}
	if lrclibOut != nil {
		c.writeFinalCache(tuple, lrclibOut)
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

type finalLyricsCachePayload struct {
	Result        Result `json:"result"`
	IdentityTuple string `json:"identityTuple"`
}

const tupleSep = "\u241E"

func identityTuple(req Request) string {
	title := strings.TrimSpace(req.TrackName)
	artist := strings.TrimSpace(req.ArtistName)
	album := strings.TrimSpace(req.AlbumName)
	length := normalizeLengthMicros(req.LengthMicros)
	return title + tupleSep + artist + tupleSep + album + tupleSep + length
}

func normalizeLengthMicros(lengthMicros string) string {
	s := strings.TrimSpace(lengthMicros)
	if s == "" {
		return ""
	}
	v, err := strconv.ParseInt(s, 10, 64)
	if err != nil || v < 0 {
		return ""
	}
	return strconv.FormatInt(v, 10)
}

func durationSecondsFromMicros(lengthMicros string) int {
	s := normalizeLengthMicros(lengthMicros)
	if s == "" {
		return 0
	}
	us, err := strconv.ParseInt(s, 10, 64)
	if err != nil || us <= 0 {
		return 0
	}
	return int(us / 1_000_000)
}

func (c *Client) writeFinalCache(tuple string, result *Result) {
	if strings.TrimSpace(tuple) == "" || result == nil || len(result.Lines) == 0 {
		return
	}
	key := spotifylyrics.FinalLyricsCacheKey(tuple)
	payload := finalLyricsCachePayload{
		Result:        *cloneResult(result),
		IdentityTuple: tuple,
	}
	b, err := json.Marshal(payload)
	if err != nil {
		return
	}
	_ = spotifylyrics.WriteUnifiedCachePayload(c.spotifyCacheDir, key, b)
}
