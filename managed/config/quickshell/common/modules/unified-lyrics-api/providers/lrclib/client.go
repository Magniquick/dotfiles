package lrclib

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"unified-lyrics-api/internal/lyricsprovider"
)

const (
	defaultBaseURL   = "https://lrclib.net/api/get"
	defaultUserAgent = "quickshell-unified-lyrics-api v1.0.0 (https://github.com/Magniquick/dotfiles/tree/main/managed/config/quickshell/common/modules/unified-lyrics-api)"
)

type apiResponse struct {
	SyncedLyrics string `json:"syncedLyrics"`
	PlainLyrics  string `json:"plainLyrics"`
}

type Client struct {
	hc      *http.Client
	baseURL string
}

func New() *Client {
	return &Client{
		hc:      &http.Client{Timeout: 8 * time.Second},
		baseURL: defaultBaseURL,
	}
}

func (c *Client) Name() string {
	return "lrclib"
}

func (c *Client) Supports(req lyricsprovider.Request) bool {
	return strings.TrimSpace(req.TrackName) != "" && strings.TrimSpace(req.ArtistName) != ""
}

func (c *Client) Fetch(ctx context.Context, req lyricsprovider.Request) (*lyricsprovider.Result, error) {
	if !c.Supports(req) {
		return nil, nil
	}

	u, err := url.Parse(c.baseURL)
	if err != nil {
		return nil, err
	}
	q := u.Query()
	q.Set("track_name", strings.TrimSpace(req.TrackName))
	q.Set("artist_name", strings.TrimSpace(req.ArtistName))
	if album := strings.TrimSpace(req.AlbumName); album != "" {
		q.Set("album_name", album)
	}
	if durationSeconds := durationSecondsFromMicros(req.LengthMicros); durationSeconds > 0 {
		q.Set("duration", strconv.Itoa(durationSeconds))
	}
	u.RawQuery = q.Encode()

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("User-Agent", defaultUserAgent)
	resp, err := c.hc.Do(httpReq)
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

	var payload apiResponse
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, fmt.Errorf("invalid lrclib response: %w", err)
	}

	lines := lyricsprovider.ParseSyncedLRC(payload.SyncedLyrics)
	syncType := lyricsprovider.SyncTypeLine
	if len(lines) == 0 {
		lines = lyricsprovider.ParsePlainText(payload.PlainLyrics)
		syncType = lyricsprovider.SyncTypeNone
	}
	if len(lines) == 0 {
		return nil, nil
	}

	return &lyricsprovider.Result{
		Provider: "lrclib",
		SyncType: syncType,
		Lines:    lines,
	}, nil
}

func durationSecondsFromMicros(lengthMicros string) int {
	s := strings.TrimSpace(lengthMicros)
	if s == "" {
		return 0
	}
	us, err := strconv.ParseInt(s, 10, 64)
	if err != nil || us <= 0 {
		return 0
	}
	return int(us / 1_000_000)
}
