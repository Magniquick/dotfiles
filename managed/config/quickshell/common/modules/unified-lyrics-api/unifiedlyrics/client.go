package unifiedlyrics

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"strconv"
	"strings"

	"unified-lyrics-api/cache"
	"unified-lyrics-api/internal/lyricsprovider"
	"unified-lyrics-api/providers/lrclib"
	"unified-lyrics-api/providers/netease"
	"unified-lyrics-api/providers/spotify"
)

type Request = lyricsprovider.Request

type Line = lyricsprovider.Line

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
	cacheDir  string
	providers []lyricsprovider.Provider
}

func New(cacheDir string) *Client {
	cacheDir = strings.TrimSpace(cacheDir)
	if cacheDir == "" {
		cacheDir = cache.DefaultDir()
	}
	return &Client{
		cacheDir: cacheDir,
		providers: []lyricsprovider.Provider{
			spotify.New(cacheDir),
			netease.New(cacheDir),
			lrclib.New(),
		},
	}
}

func (c *Client) Fetch(ctx context.Context, req Request) (*Result, error) {
	if c == nil {
		return nil, errors.New("nil client")
	}

	tuple := identityTuple(req)
	if tuple != "" {
		key := cache.FinalLyricsKey(tuple)
		if payload, _, err := cache.ReadPayload(c.cacheDir, key); err == nil {
			var cached finalLyricsCachePayload
			if json.Unmarshal(payload, &cached) == nil && len(cached.Result.Lines) > 0 {
				log.Printf("unifiedlyrics: cache hit tuple=%q source=%s provider=%s sync=%s lines=%d", tuple, cached.Result.Source, cached.Result.Metadata.Provider, cached.Result.SyncType, len(cached.Result.Lines))
				return cloneResult(&cached.Result), nil
			}
		}
	}

	var best *Result
	bestRank := 0
	var providerErrs []string
	for _, provider := range c.providers {
		if !provider.Supports(req) {
			log.Printf("unifiedlyrics: skip provider=%s unsupported track=%q artist=%q album=%q spotifyRef=%t", provider.Name(), req.TrackName, req.ArtistName, req.AlbumName, strings.TrimSpace(req.SpotifyTrackRef) != "")
			continue
		}
		out, err := provider.Fetch(ctx, req)
		if err != nil {
			log.Printf("unifiedlyrics: provider=%s error=%v track=%q artist=%q album=%q", provider.Name(), err, req.TrackName, req.ArtistName, req.AlbumName)
			providerErrs = append(providerErrs, provider.Name())
			continue
		}
		if out == nil || len(out.Lines) == 0 {
			log.Printf("unifiedlyrics: provider=%s empty result", provider.Name())
			continue
		}

		result := newResult(out.Provider, out.SyncType, out.Lines)
		rank := lyricsprovider.RankSyncType(strings.TrimSpace(out.SyncType))
		log.Printf("unifiedlyrics: candidate provider=%s source=%s sync=%s rank=%d lines=%d", out.Provider, result.Source, out.SyncType, rank, len(out.Lines))
		if best == nil || rank > bestRank {
			best = result
			bestRank = rank
			log.Printf("unifiedlyrics: selected provider=%s source=%s sync=%s rank=%d", best.Metadata.Provider, best.Source, best.SyncType, bestRank)
			if bestRank >= lyricsprovider.RankSyncType(lyricsprovider.SyncTypeWord) {
				break
			}
		}
	}

	if best != nil {
		log.Printf("unifiedlyrics: final source=%s provider=%s sync=%s lines=%d", best.Source, best.Metadata.Provider, best.SyncType, len(best.Lines))
		c.writeFinalCache(tuple, best)
		return best, nil
	}
	if len(providerErrs) > 1 {
		return nil, errors.New(strings.Join(providerErrs, " and ") + " failed")
	}
	if len(providerErrs) == 1 {
		return nil, errors.New(providerErrs[0] + " failed")
	}
	return nil, errors.New("no lyrics available")
}

func newResult(provider, syncType string, lines []Line) *Result {
	return &Result{
		Source:   lyricsprovider.SourceFor(provider, strings.TrimSpace(syncType)),
		SyncType: syncType,
		Lines:    cloneLines(lines),
		Metadata: ResultMetadata{Provider: provider},
	}
}

func cloneLines(lines []Line) []Line {
	if len(lines) == 0 {
		return []Line{}
	}
	out := make([]Line, len(lines))
	for i := range lines {
		out[i] = Line{
			StartTimeMs: lines[i].StartTimeMs,
			EndTimeMs:   lines[i].EndTimeMs,
			Words:       lines[i].Words,
			Segments:    cloneSegments(lines[i].Segments),
		}
	}
	return out
}

func cloneSegments(segments []lyricsprovider.Segment) []lyricsprovider.Segment {
	if len(segments) == 0 {
		return nil
	}
	out := make([]lyricsprovider.Segment, len(segments))
	copy(out, segments)
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

func (c *Client) writeFinalCache(tuple string, result *Result) {
	if strings.TrimSpace(tuple) == "" || result == nil || len(result.Lines) == 0 {
		return
	}
	key := cache.FinalLyricsKey(tuple)
	payload := finalLyricsCachePayload{
		Result:        *cloneResult(result),
		IdentityTuple: tuple,
	}
	b, err := json.Marshal(payload)
	if err != nil {
		return
	}
	_ = cache.WritePayload(c.cacheDir, key, b)
}
