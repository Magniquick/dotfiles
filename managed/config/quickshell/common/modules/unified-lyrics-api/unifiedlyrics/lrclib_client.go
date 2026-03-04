package unifiedlyrics

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	defaultLrcLibBaseURL   = "https://lrclib.net/api/get"
	defaultLrcLibUserAgent = "quickshell-unified-lyrics-api v1.0.0 (https://github.com/Magniquick/dotfiles/tree/main/managed/config/quickshell/common/modules/unified-lyrics-api)"
)

type Line struct {
	StartTimeMs string `json:"startTimeMs"`
	Words       string `json:"words"`
}

type lrcLibFetchResult struct {
	SyncType string `json:"syncType"`
	Lines    []Line `json:"lines"`
}

type lrcLibAPIResponse struct {
	SyncedLyrics string `json:"syncedLyrics"`
	PlainLyrics  string `json:"plainLyrics"`
}

type LrcLibClient struct {
	hc      *http.Client
	baseURL string
}

func NewLrcLibClient() *LrcLibClient {
	return &LrcLibClient{
		hc:      &http.Client{Timeout: 8 * time.Second},
		baseURL: defaultLrcLibBaseURL,
	}
}

func (c *LrcLibClient) GetLyrics(ctx context.Context, trackName, artistName, albumName string, durationSeconds int) (*lrcLibFetchResult, error) {
	trackName = strings.TrimSpace(trackName)
	artistName = strings.TrimSpace(artistName)
	albumName = strings.TrimSpace(albumName)

	if trackName == "" || artistName == "" {
		return nil, fmt.Errorf("track and artist are required")
	}

	u, err := url.Parse(c.baseURL)
	if err != nil {
		return nil, err
	}
	q := u.Query()
	q.Set("track_name", trackName)
	q.Set("artist_name", artistName)
	if albumName != "" {
		q.Set("album_name", albumName)
	}
	if durationSeconds > 0 {
		q.Set("duration", strconv.Itoa(durationSeconds))
	}
	u.RawQuery = q.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", defaultLrcLibUserAgent)
	resp, err := c.hc.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, fmt.Errorf("lyrics not found")
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("lrclib api error (HTTP %d)", resp.StatusCode)
	}

	var payload lrcLibAPIResponse
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, fmt.Errorf("invalid lrclib response: %w", err)
	}

	syncedLines := parseSyncedLyrics(payload.SyncedLyrics)
	if len(syncedLines) > 0 {
		return &lrcLibFetchResult{
			SyncType: "LINE_SYNCED",
			Lines:    syncedLines,
		}, nil
	}

	plainLines := parsePlainLyrics(payload.PlainLyrics)
	if len(plainLines) > 0 {
		return &lrcLibFetchResult{
			SyncType: "UNSYNCED",
			Lines:    plainLines,
		}, nil
	}

	return &lrcLibFetchResult{SyncType: "UNSYNCED", Lines: []Line{}}, nil
}

var lrcTagRe = regexp.MustCompile(`\[(\d{1,2}:\d{2}(?:\.\d{1,3})?)\]`)

func parseSyncedLyrics(text string) []Line {
	text = strings.TrimSpace(text)
	if text == "" {
		return nil
	}

	out := make([]Line, 0, 64)
	rows := strings.Split(text, "\n")
	for _, row := range rows {
		row = strings.TrimSpace(row)
		if row == "" {
			continue
		}

		tags := lrcTagRe.FindAllStringSubmatch(row, -1)
		if len(tags) == 0 {
			continue
		}
		words := strings.TrimSpace(lrcTagRe.ReplaceAllString(row, ""))
		if words == "" {
			words = "♪"
		}

		for _, tag := range tags {
			if len(tag) < 2 {
				continue
			}
			ms := parseLrcTimeToMs(tag[1])
			if ms < 0 {
				continue
			}
			out = append(out, Line{
				StartTimeMs: strconv.Itoa(ms),
				Words:       words,
			})
		}
	}

	sort.Slice(out, func(i, j int) bool {
		li, _ := strconv.Atoi(out[i].StartTimeMs)
		lj, _ := strconv.Atoi(out[j].StartTimeMs)
		return li < lj
	})

	return out
}

func parsePlainLyrics(text string) []Line {
	text = strings.TrimSpace(text)
	if text == "" {
		return nil
	}

	rows := strings.Split(text, "\n")
	out := make([]Line, 0, len(rows))
	for _, row := range rows {
		row = strings.TrimSpace(row)
		if row == "" {
			continue
		}
		out = append(out, Line{StartTimeMs: "", Words: row})
	}
	return out
}

func parseLrcTimeToMs(tag string) int {
	parts := strings.Split(tag, ":")
	if len(parts) != 2 {
		return -1
	}
	min, err := strconv.Atoi(parts[0])
	if err != nil {
		return -1
	}
	secParts := strings.Split(parts[1], ".")
	sec, err := strconv.Atoi(secParts[0])
	if err != nil {
		return -1
	}

	fractionMs := 0
	if len(secParts) > 1 {
		f := secParts[1]
		if len(f) == 1 {
			v, err := strconv.Atoi(f)
			if err == nil {
				fractionMs = v * 100
			}
		} else if len(f) == 2 {
			v, err := strconv.Atoi(f)
			if err == nil {
				fractionMs = v * 10
			}
		} else {
			v, err := strconv.Atoi(f[:3])
			if err == nil {
				fractionMs = v
			}
		}
	}

	return min*60000 + sec*1000 + fractionMs
}
