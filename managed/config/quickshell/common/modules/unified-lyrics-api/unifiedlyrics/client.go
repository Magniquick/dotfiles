package unifiedlyrics

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"math"
	"os"
	"path/filepath"
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

	disabledCache := cacheDisabled(c.cacheDir)
	providers := c.providers
	if disabledCache {
		providers = disabledCacheProviderOrder(c.providers)
	}
	providerPriority := providerPriority(c.providers)

	var best *Result
	var providerErrs []string
	if disabledCache {
		best, providerErrs = c.fetchProvidersConcurrent(ctx, req, providers, providerPriority)
	} else {
		best, providerErrs = c.fetchProvidersSerial(ctx, req, providers, providerPriority)
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

func (c *Client) fetchProvidersSerial(ctx context.Context, req Request, providers []lyricsprovider.Provider, providerPriority map[string]int) (*Result, []string) {
	var best *Result
	bestRank := 0
	bestPriority := math.MaxInt
	var providerErrs []string
	for i, provider := range providers {
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
		priority := providerPriority[provider.Name()]
		if best == nil || rank > bestRank || (rank == bestRank && priority < bestPriority) {
			best = result
			bestRank = rank
			bestPriority = priority
			log.Printf("unifiedlyrics: selected provider=%s source=%s sync=%s rank=%d", best.Metadata.Provider, best.Source, best.SyncType, bestRank)
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

type providerCandidate struct {
	index    int
	provider lyricsprovider.Provider
	priority int
	maxRank  int
}

type providerFetchResult struct {
	candidate providerCandidate
	result    *Result
	rank      int
	err       error
	empty     bool
}

func (c *Client) fetchProvidersConcurrent(ctx context.Context, req Request, providers []lyricsprovider.Provider, providerPriority map[string]int) (*Result, []string) {
	raceCtx, cancel := context.WithCancel(ctx)
	defer cancel()

	candidates := make([]providerCandidate, 0, len(providers))
	for _, provider := range providers {
		if !provider.Supports(req) {
			log.Printf("unifiedlyrics: skip provider=%s unsupported track=%q artist=%q album=%q spotifyRef=%t", provider.Name(), req.TrackName, req.ArtistName, req.AlbumName, strings.TrimSpace(req.SpotifyTrackRef) != "")
			continue
		}
		candidates = append(candidates, providerCandidate{
			index:    len(candidates),
			provider: provider,
			priority: providerPriority[provider.Name()],
			maxRank:  maxProviderRank(provider.Name()),
		})
	}
	if len(candidates) == 0 {
		return nil, nil
	}

	results := make(chan providerFetchResult, len(candidates))
	pending := make(map[int]providerCandidate, len(candidates))
	running := make(map[int]providerCandidate, len(candidates))
	waiting := make([]providerCandidate, 0, len(candidates))
	for _, candidate := range candidates {
		pending[candidate.index] = candidate
		if shouldStartInitialRace(candidate) {
			startProviderFetch(raceCtx, req, candidate, results)
			running[candidate.index] = candidate
		} else {
			waiting = append(waiting, candidate)
		}
	}
	if len(running) == 0 {
		startNextCandidate(raceCtx, req, &waiting, running, results)
	}

	var best *Result
	bestRank := 0
	bestPriority := math.MaxInt
	var providerErrs []string

	for len(pending) > 0 {
		if len(running) == 0 {
			if shouldStopCandidateSearch(bestRank, bestPriority, pending) {
				cancel()
				return best, providerErrs
			}
			if !startNextCandidate(raceCtx, req, &waiting, running, results) {
				break
			}
		}

		fetchResult := <-results
		candidate := fetchResult.candidate
		delete(pending, candidate.index)
		delete(running, candidate.index)

		if fetchResult.err != nil {
			log.Printf("unifiedlyrics: provider=%s error=%v track=%q artist=%q album=%q", candidate.provider.Name(), fetchResult.err, req.TrackName, req.ArtistName, req.AlbumName)
			providerErrs = append(providerErrs, candidate.provider.Name())
		} else if fetchResult.empty {
			log.Printf("unifiedlyrics: provider=%s empty result", candidate.provider.Name())
		} else {
			log.Printf("unifiedlyrics: candidate provider=%s source=%s sync=%s rank=%d lines=%d", candidate.provider.Name(), fetchResult.result.Source, fetchResult.result.SyncType, fetchResult.rank, len(fetchResult.result.Lines))
			if best == nil || fetchResult.rank > bestRank || (fetchResult.rank == bestRank && candidate.priority < bestPriority) {
				best = fetchResult.result
				bestRank = fetchResult.rank
				bestPriority = candidate.priority
				log.Printf("unifiedlyrics: selected provider=%s source=%s sync=%s rank=%d", best.Metadata.Provider, best.Source, best.SyncType, bestRank)
			}
		}

		if shouldStopCandidateSearch(bestRank, bestPriority, pending) {
			cancel()
			return best, providerErrs
		}
	}

	return best, providerErrs
}

func shouldStartInitialRace(candidate providerCandidate) bool {
	switch candidate.provider.Name() {
	case "netease", "spotify":
		return true
	default:
		return false
	}
}

func startNextCandidate(ctx context.Context, req Request, waiting *[]providerCandidate, running map[int]providerCandidate, results chan<- providerFetchResult) bool {
	if len(*waiting) == 0 {
		return false
	}
	candidate := (*waiting)[0]
	*waiting = (*waiting)[1:]
	startProviderFetch(ctx, req, candidate, results)
	running[candidate.index] = candidate
	return true
}

func startProviderFetch(ctx context.Context, req Request, candidate providerCandidate, results chan<- providerFetchResult) {
	go func() {
		out, err := candidate.provider.Fetch(ctx, req)
		fetchResult := providerFetchResult{candidate: candidate, err: err}
		if err == nil {
			if out == nil || len(out.Lines) == 0 {
				fetchResult.empty = true
			} else {
				fetchResult.result = newResult(out.Provider, out.SyncType, out.Lines)
				fetchResult.rank = lyricsprovider.RankSyncType(strings.TrimSpace(out.SyncType))
			}
		}
		results <- fetchResult
	}()
}

func cacheDisabled(cacheDir string) bool {
	cacheDir = strings.TrimSpace(cacheDir)
	if cacheDir == "" {
		return false
	}
	if cacheDir == os.DevNull {
		return true
	}
	cleaned := filepath.Clean(cacheDir)
	return cleaned == filepath.Clean(os.DevNull)
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

func disabledCacheProviderOrder(providers []lyricsprovider.Provider) []lyricsprovider.Provider {
	out := make([]lyricsprovider.Provider, 0, len(providers))
	for _, name := range []string{"netease", "spotify"} {
		for _, provider := range providers {
			if provider.Name() == name {
				out = append(out, provider)
			}
		}
	}
	for _, provider := range providers {
		if provider.Name() == "netease" || provider.Name() == "spotify" {
			continue
		}
		out = append(out, provider)
	}
	return out
}

func shouldStopProviderSearch(bestRank int, bestPriority int, remaining []lyricsprovider.Provider, priorities map[string]int) bool {
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

func shouldStopCandidateSearch(bestRank int, bestPriority int, pending map[int]providerCandidate) bool {
	if bestRank == 0 {
		return false
	}
	for _, candidate := range pending {
		if candidate.maxRank > bestRank {
			return false
		}
		if candidate.maxRank == bestRank && candidate.priority < bestPriority {
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
