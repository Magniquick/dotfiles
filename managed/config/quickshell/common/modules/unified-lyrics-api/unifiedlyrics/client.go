package unifiedlyrics

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"math"
	"strconv"
	"strings"

	"unified-lyrics-api/cache"
	"unified-lyrics-api/internal/lyricsprovider"
	"unified-lyrics-api/providers/lrclib"
	"unified-lyrics-api/providers/netease"
	"unified-lyrics-api/providers/spotify"
)

// Request describes the track metadata passed to lyric providers.
type Request = lyricsprovider.Request

// Line describes one normalized lyric line.
type Line = lyricsprovider.Line

// Result is the final lyric response returned to callers.
type Result struct {
	Source   string         `json:"source"`
	SyncType string         `json:"syncType"`
	Lines    []Line         `json:"lines"`
	Metadata ResultMetadata `json:"metadata"`
}

// ResultMetadata describes the provider that produced the result.
type ResultMetadata struct {
	Provider string `json:"provider"`
}

// Client coordinates Spotify, NetEase, and LRCLIB providers.
type Client struct {
	cacheDir  string
	noCache   bool
	providers []lyricsprovider.Provider
}

// Option customizes a Client.
type Option func(*Client)

// WithNoCache disables all cache reads and writes for the unified provider stack.
func WithNoCache(noCache bool) Option {
	return func(c *Client) { c.noCache = noCache }
}

// New creates a unified lyrics client.
func New(cacheDir string, opts ...Option) *Client {
	cacheDir = strings.TrimSpace(cacheDir)
	if cacheDir == "" {
		cacheDir = cache.DefaultDir()
	}

	c := &Client{cacheDir: cacheDir}
	for _, opt := range opts {
		opt(c)
	}

	spotifyOpts := []spotify.Option{}
	neteaseOpts := []netease.Option{}
	if c.noCache {
		spotifyOpts = append(spotifyOpts, spotify.WithCacheEnabled(false), spotify.WithLyricsCacheEnabled(false))
		neteaseOpts = append(neteaseOpts, netease.WithCacheEnabled(false))
	}
	c.providers = []lyricsprovider.Provider{
		spotify.New(cacheDir, spotifyOpts...),
		netease.New(cacheDir, neteaseOpts...),
		lrclib.New(),
	}
	return c
}

// Fetch returns the best available lyrics for a request.
func (c *Client) Fetch(ctx context.Context, req Request) (*Result, error) {
	if c == nil {
		return nil, errors.New("nil client")
	}

	tuple := identityTuple(req)
	if !c.noCache && tuple != "" {
		key := cache.FinalLyricsKey(tuple)
		if payload, _, err := cache.ReadPayload(c.cacheDir, key); err == nil {
			var cached finalLyricsCachePayload
			if json.Unmarshal(payload, &cached) == nil && len(cached.Result.Lines) > 0 {
				log.Printf(
					"unifiedlyrics: cache hit tuple=%q source=%s provider=%s sync=%s lines=%d",
					tuple,
					cached.Result.Source,
					cached.Result.Metadata.Provider,
					cached.Result.SyncType,
					len(cached.Result.Lines),
				)
				return cloneResult(&cached.Result), nil
			}
		}
	}

	providerPriority := providerPriority(c.providers)

	var best *Result
	var providerErrs []string
	best, providerErrs = c.fetchProvidersSerial(ctx, req, c.providers, providerPriority)

	if best != nil {
		log.Printf(
			"unifiedlyrics: final source=%s provider=%s sync=%s lines=%d",
			best.Source,
			best.Metadata.Provider,
			best.SyncType,
			len(best.Lines),
		)
		if !c.noCache {
			c.writeFinalCache(tuple, best)
		}
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

func (c *Client) fetchProvidersSerial(
	ctx context.Context,
	req Request,
	providers []lyricsprovider.Provider,
	providerPriority map[string]int,
) (*Result, []string) {
	var best *Result
	bestRank := 0
	bestPriority := math.MaxInt
	var providerErrs []string
	for i, provider := range providers {
		if !provider.Supports(req) {
			logUnsupportedProvider(provider.Name(), req)
			continue
		}
		out, err := provider.Fetch(ctx, req)
		if err != nil {
			logProviderError(provider.Name(), err, req)
			providerErrs = append(providerErrs, provider.Name())
			continue
		}
		if out == nil || len(out.Lines) == 0 {
			log.Printf("unifiedlyrics: provider=%s empty result", provider.Name())
			continue
		}

		result := newResult(out.Provider, out.SyncType, out.Lines)
		rank := lyricsprovider.RankSyncType(strings.TrimSpace(out.SyncType))
		logProviderCandidate(out.Provider, result.Source, out.SyncType, rank, len(out.Lines))
		priority := providerPriority[provider.Name()]
		if best == nil || rank > bestRank || (rank == bestRank && priority < bestPriority) {
			best = result
			bestRank = rank
			bestPriority = priority
			logProviderSelected(best.Metadata.Provider, best.Source, best.SyncType, bestRank)
			if bestRank >= lyricsprovider.RankSyncType(lyricsprovider.SyncTypeWord) {
				break
			}
		}
		if shouldStopProviderSearch(bestRank, bestPriority, providers[i+1:], providerPriority) {
			break
		}
	}
	return best, providerErrs
}

func logUnsupportedProvider(provider string, req Request) {
	log.Printf(
		"unifiedlyrics: skip provider=%s unsupported track=%q artist=%q album=%q spotifyRef=%t",
		provider,
		req.TrackName,
		req.ArtistName,
		req.AlbumName,
		strings.TrimSpace(req.SpotifyTrackRef) != "",
	)
}

func logProviderError(provider string, err error, req Request) {
	log.Printf(
		"unifiedlyrics: provider=%s error=%v track=%q artist=%q album=%q",
		provider,
		err,
		req.TrackName,
		req.ArtistName,
		req.AlbumName,
	)
}

func logProviderCandidate(provider string, source string, syncType string, rank int, lineCount int) {
	log.Printf(
		"unifiedlyrics: candidate provider=%s source=%s sync=%s rank=%d lines=%d",
		provider,
		source,
		syncType,
		rank,
		lineCount,
	)
}

func logProviderSelected(provider string, source string, syncType string, rank int) {
	log.Printf(
		"unifiedlyrics: selected provider=%s source=%s sync=%s rank=%d",
		provider,
		source,
		syncType,
		rank,
	)
}

func providerPriority(providers []lyricsprovider.Provider) map[string]int {
	out := make(map[string]int, len(providers))
	for i, provider := range providers {
		if _, ok := out[provider.Name()]; !ok {
			out[provider.Name()] = i
		}
	}
	return out
}

func shouldStopProviderSearch(
	bestRank int,
	bestPriority int,
	remaining []lyricsprovider.Provider,
	priorities map[string]int,
) bool {
	if bestRank == 0 {
		return false
	}
	for _, provider := range remaining {
		rank := maxProviderRank(provider.Name())
		if rank > bestRank {
			return false
		}
		if rank == bestRank && priorities[provider.Name()] < bestPriority {
			return false
		}
	}
	return true
}

func maxProviderRank(name string) int {
	switch name {
	case "spotify", "lrclib":
		return lyricsprovider.RankSyncType(lyricsprovider.SyncTypeLine)
	default:
		return lyricsprovider.RankSyncType(lyricsprovider.SyncTypeWord)
	}
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
