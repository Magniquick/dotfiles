package spotify

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"unified-lyrics-api/cache"
	"unified-lyrics-api/internal/lyricsprovider"
)

const (
	defaultTokenURL      = "https://open.spotify.com/api/token"
	defaultLyricsBaseURL = "https://spclient.wg.spotify.com/color-lyrics/v2/track/"
	defaultServerTimeURL = "https://open.spotify.com/api/server-time"
)

var trackIDRegex = regexp.MustCompile(`(?i)(?:https?://open\.spotify\.com/)?(?:track/|track:)([A-Za-z0-9]+)`)

type Client struct {
	spdc string

	hc                       *http.Client
	insecureSpotifyTransport http.RoundTripper

	tokenURL       string
	lyricsBaseURL  string
	serverTimeURL  string
	secretDictURL  string
	cacheDir       string
	tokenCacheKey  string
	secretCacheKey string
	lyricsScopeKey string

	lyricsCacheTTL     time.Duration
	lyricsCacheEnabled bool

	tokenTimeout       time.Duration
	tokenUserAgent     string
	lyricsUserAgent    string
	insecureSpotifyTLS bool
}

type Option func(*Client)

func WithHTTPClient(hc *http.Client) Option {
	return func(c *Client) { c.hc = hc }
}

func WithCacheDir(dir string) Option {
	return func(c *Client) {
		dir = strings.TrimSpace(dir)
		if dir == "" {
			return
		}
		c.cacheDir = dir
	}
}

func WithLyricsCacheTTL(ttl time.Duration) Option {
	return func(c *Client) { c.lyricsCacheTTL = ttl }
}

func WithLyricsCacheEnabled(enabled bool) Option {
	return func(c *Client) { c.lyricsCacheEnabled = enabled }
}

func WithUserAgent(ua string) Option {
	return func(c *Client) {
		c.tokenUserAgent = ua
		c.lyricsUserAgent = ua
	}
}

func WithTokenUserAgent(ua string) Option {
	return func(c *Client) { c.tokenUserAgent = ua }
}

func WithLyricsUserAgent(ua string) Option {
	return func(c *Client) { c.lyricsUserAgent = ua }
}

func WithTokenTimeout(d time.Duration) Option {
	return func(c *Client) { c.tokenTimeout = d }
}

func WithInsecureSpotifyTLS(enabled bool) Option {
	return func(c *Client) { c.insecureSpotifyTLS = enabled }
}

func New(cacheDir string, opts ...Option) *Client {
	cacheDir = strings.TrimSpace(cacheDir)
	if cacheDir == "" {
		cacheDir = cache.DefaultDir()
	}
	c := &Client{
		hc:                 &http.Client{Timeout: 30 * time.Second},
		tokenURL:           defaultTokenURL,
		lyricsBaseURL:      defaultLyricsBaseURL,
		serverTimeURL:      defaultServerTimeURL,
		secretDictURL:      defaultSecretDictURL,
		cacheDir:           cacheDir,
		lyricsCacheTTL:     7 * 24 * time.Hour,
		lyricsCacheEnabled: true,
		tokenTimeout:       600 * time.Second,
		tokenUserAgent:     "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
		lyricsUserAgent:    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/101.0.0.0 Safari/537.36",
		insecureSpotifyTLS: true,
	}
	for _, opt := range opts {
		opt(c)
	}
	if c.insecureSpotifyTLS {
		_ = c.spotifyTransport(true)
	}
	return c
}

func (c *Client) Name() string {
	return providerName
}

func (c *Client) Supports(req lyricsprovider.Request) bool {
	return strings.TrimSpace(req.SPDC) != "" && strings.TrimSpace(req.SpotifyTrackRef) != ""
}

func (c *Client) Fetch(ctx context.Context, req lyricsprovider.Request) (*lyricsprovider.Result, error) {
	if !c.Supports(req) {
		return nil, nil
	}
	sc, err := NewWithSPDC(strings.TrimSpace(req.SPDC), c.cacheDir)
	if err != nil {
		return nil, err
	}
	lr, err := sc.GetLyricsFromURL(ctx, req.SpotifyTrackRef)
	if err != nil {
		return nil, err
	}
	lines := make([]lyricsprovider.Line, 0, len(lr.Lyrics.Lines))
	for _, ln := range lr.Lyrics.Lines {
		lines = append(lines, lyricsprovider.Line{
			StartTimeMs: strings.TrimSpace(ln.StartTimeMs),
			EndTimeMs:   strings.TrimSpace(ln.EndTimeMs),
			Words:       ln.Words,
		})
	}
	if len(lines) == 0 {
		return nil, nil
	}
	return &lyricsprovider.Result{
		Provider: providerName,
		SyncType: normalizeSyncType(strings.TrimSpace(lr.Lyrics.SyncType), lines),
		Lines:    lines,
	}, nil
}

func normalizeSyncType(syncType string, lines []lyricsprovider.Line) string {
	switch strings.ToUpper(strings.TrimSpace(syncType)) {
	case lyricsprovider.SyncTypeLine:
		return lyricsprovider.SyncTypeLine
	case lyricsprovider.SyncTypeNone:
		return lyricsprovider.SyncTypeNone
	}
	for _, line := range lines {
		if strings.TrimSpace(line.StartTimeMs) != "" {
			return lyricsprovider.SyncTypeLine
		}
	}
	return lyricsprovider.SyncTypeNone
}

func NewWithSPDC(spdc string, cacheDir string, opts ...Option) (*Client, error) {
	spdc = strings.TrimSpace(spdc)
	if spdc == "" {
		return nil, &Error{Message: "SP_DC is required"}
	}
	c := New(cacheDir, opts...)
	c.spdc = spdc
	if c.hc == nil {
		return nil, &Error{Message: "http client is nil"}
	}
	if strings.TrimSpace(c.tokenUserAgent) == "" || strings.TrimSpace(c.lyricsUserAgent) == "" {
		return nil, &Error{Message: "user agent is empty"}
	}
	if c.tokenTimeout <= 0 {
		return nil, &Error{Message: "token timeout must be > 0"}
	}
	return c, nil
}

func (c *Client) tokenCacheEntryKey() string {
	if c.tokenCacheKey != "" {
		return c.tokenCacheKey
	}
	return tokenCacheKey(c.spdc)
}

func (c *Client) secretCacheEntryKey() string {
	if c.secretCacheKey != "" {
		return c.secretCacheKey
	}
	return secretCacheKey(c.secretDictURL)
}

func (c *Client) lyricsCacheEntryKey(trackID string) string {
	if c.lyricsScopeKey != "" {
		return cache.ProviderLyricsKey(providerName, c.lyricsScopeKey+":"+strings.ToLower(strings.TrimSpace(trackID)))
	}
	return lyricsCacheKey(trackID)
}

func TrackIDFromURL(s string) (string, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return "", fmt.Errorf("empty url")
	}

	if strings.HasPrefix(s, "http://") || strings.HasPrefix(s, "https://") {
		u, err := url.Parse(s)
		if err == nil {
			parts := strings.Split(strings.Trim(u.Path, "/"), "/")
			if len(parts) >= 2 && strings.EqualFold(parts[0], "track") && parts[1] != "" {
				return parts[1], nil
			}
		}
	}

	if m := trackIDRegex.FindStringSubmatch(s); len(m) == 2 {
		return m[1], nil
	}

	return "", fmt.Errorf("could not extract track id")
}

func (c *Client) spotifyTransport(insecure bool) http.RoundTripper {
	if !insecure {
		if c.hc.Transport != nil {
			return c.hc.Transport
		}
		return http.DefaultTransport
	}
	if c.insecureSpotifyTransport != nil {
		return c.insecureSpotifyTransport
	}

	var base *http.Transport
	if t, ok := c.hc.Transport.(*http.Transport); ok && t != nil {
		base = t.Clone()
	} else if t, ok := http.DefaultTransport.(*http.Transport); ok && t != nil {
		base = t.Clone()
	} else {
		base = (&http.Transport{}).Clone()
	}

	tlsCfg := base.TLSClientConfig
	if tlsCfg != nil {
		tlsCfg = tlsCfg.Clone()
	} else {
		tlsCfg = &tls.Config{}
	}
	tlsCfg.InsecureSkipVerify = true
	base.TLSClientConfig = tlsCfg

	c.insecureSpotifyTransport = base
	return c.insecureSpotifyTransport
}

func (c *Client) spotifyHTTPClient(timeout time.Duration, insecure bool) *http.Client {
	return &http.Client{
		Transport:     c.spotifyTransport(insecure),
		CheckRedirect: c.hc.CheckRedirect,
		Jar:           c.hc.Jar,
		Timeout:       timeout,
	}
}

func (c *Client) getServerTimeSeconds(ctx context.Context) (int64, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.serverTimeURL, nil)
	if err != nil {
		return 0, err
	}
	req.Header.Set("User-Agent", c.tokenUserAgent)

	hc := c.spotifyHTTPClient(c.tokenTimeout, c.insecureSpotifyTLS)
	resp, err := hc.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return 0, &Error{Status: resp.StatusCode, Message: "failed to fetch server time"}
	}
	var st serverTimeResponse
	if err := json.NewDecoder(resp.Body).Decode(&st); err != nil {
		return 0, fmt.Errorf("invalid server time response: %w", err)
	}
	if st.ServerTime <= 0 {
		return 0, fmt.Errorf("invalid server time value")
	}
	return st.ServerTime, nil
}

func (c *Client) getTokenParams(ctx context.Context) (url.Values, error) {
	serverTime, err := c.getServerTimeSeconds(ctx)
	if err != nil {
		return nil, err
	}
	secret, version, err := fetchLatestSecret(ctx, c.hc, c.secretDictURL, c.cacheDir, c.secretCacheEntryKey())
	if err != nil {
		return nil, err
	}
	totp, err := generateTOTP(serverTime, secret)
	if err != nil {
		return nil, err
	}

	params := url.Values{}
	params.Set("reason", "transport")
	params.Set("productType", "web-player")
	params.Set("totp", totp)
	params.Set("totpVer", version)
	params.Set("ts", fmt.Sprintf("%d", time.Now().Unix()))
	return params, nil
}

func (c *Client) fetchToken(ctx context.Context) (*TokenResponse, error) {
	params, err := c.getTokenParams(ctx)
	if err != nil {
		return nil, err
	}
	u := c.tokenURL + "?" + params.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", c.tokenUserAgent)
	req.Header.Set("Cookie", "sp_dc="+c.spdc)

	hc := c.spotifyHTTPClient(c.tokenTimeout, c.insecureSpotifyTLS)
	resp, err := hc.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode >= 400 {
		msg := strings.TrimSpace(string(body))
		if msg == "" {
			msg = "token request failed"
		} else {
			const maxLen = 600
			if len(msg) > maxLen {
				msg = msg[:maxLen] + "..."
			}
			msg = "token request failed: " + msg
		}
		return nil, &Error{Status: resp.StatusCode, Message: msg}
	}

	var tr TokenResponse
	if err := json.Unmarshal(body, &tr); err != nil {
		return nil, fmt.Errorf("invalid token response: %w", err)
	}
	if tr.AccessToken == "" || tr.IsAnonymous {
		return nil, &Error{Message: "SP_DC appears to be invalid"}
	}
	if tr.AccessTokenExpirationTimestampMs == 0 {
		return nil, &Error{Message: "token response missing expiration timestamp"}
	}

	if err := writeCachePayload(c.cacheDir, c.tokenCacheEntryKey(), body); err != nil {
		return nil, fmt.Errorf("failed to write token cache: %w", err)
	}
	return &tr, nil
}

func (c *Client) readCachedToken() (*TokenResponse, error) {
	b, _, err := readCachePayload(c.cacheDir, c.tokenCacheEntryKey())
	if err != nil {
		return nil, err
	}
	var tr TokenResponse
	if err := json.Unmarshal(b, &tr); err != nil {
		return nil, err
	}
	if tr.AccessToken == "" || tr.AccessTokenExpirationTimestampMs == 0 {
		return nil, errors.New("cache missing required token fields")
	}
	return &tr, nil
}

func (c *Client) invalidateCachedToken() {
	deleteCachePayload(c.cacheDir, c.tokenCacheEntryKey())
}

func (c *Client) EnsureToken(ctx context.Context) (*TokenResponse, error) {
	tr, err := c.readCachedToken()
	if err == nil {
		nowMs := time.Now().UnixMilli()
		if tr.AccessTokenExpirationTimestampMs > nowMs {
			return tr, nil
		}
	}
	return c.fetchToken(ctx)
}

func (c *Client) GetLyrics(ctx context.Context, trackID string) (*LyricsResponse, error) {
	trackID = strings.TrimSpace(trackID)
	if trackID == "" {
		return nil, &Error{Message: "track id is required"}
	}
	lyricsCacheKey := c.lyricsCacheEntryKey(trackID)

	if c.lyricsCacheEnabled {
		if lr, ok := readLyricsCache(c.cacheDir, lyricsCacheKey, c.lyricsCacheTTL); ok {
			return lr, nil
		}
	}

	tr, err := c.EnsureToken(ctx)
	if err != nil {
		return nil, err
	}

	u := c.lyricsBaseURL + trackID + "?format=json&market=from_token"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", c.lyricsUserAgent)
	req.Header.Set("App-platform", "WebPlayer")
	req.Header.Set("authorization", "Bearer "+tr.AccessToken)

	hc := c.spotifyHTTPClient(c.hc.Timeout, c.insecureSpotifyTLS)
	resp, err := hc.Do(req)
	if err != nil {
		c.invalidateCachedToken()
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		c.invalidateCachedToken()
		return nil, err
	}

	switch resp.StatusCode {
	case 200:
	case 404:
		c.invalidateCachedToken()
		return nil, &Error{Status: 404, Message: "lyrics for this track were not found on spotify"}
	case 429:
		c.invalidateCachedToken()
		return nil, &Error{Status: 429, Message: "rate limited by spotify; try again later"}
	default:
		if resp.StatusCode >= 400 {
			c.invalidateCachedToken()
			return nil, &Error{Status: resp.StatusCode, Message: "spotify api error"}
		}
	}

	var lr LyricsResponse
	if err := json.Unmarshal(body, &lr); err != nil {
		c.invalidateCachedToken()
		return nil, fmt.Errorf("invalid lyrics response: %w", err)
	}
	if lr.Lyrics.Lines == nil {
		c.invalidateCachedToken()
		return nil, &Error{Message: "spotify returned an invalid lyrics response"}
	}

	if c.lyricsCacheEnabled {
		_ = writeLyricsCache(c.cacheDir, lyricsCacheKey, body)
	}
	return &lr, nil
}

func (c *Client) GetLyricsFromURL(ctx context.Context, trackURL string) (*LyricsResponse, error) {
	id, err := TrackIDFromURL(trackURL)
	if err != nil {
		return nil, err
	}
	return c.GetLyrics(ctx, id)
}
