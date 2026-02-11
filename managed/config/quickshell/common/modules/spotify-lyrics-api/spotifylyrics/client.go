package spotifylyrics

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const (
	defaultTokenURL      = "https://open.spotify.com/api/token"
	defaultLyricsBaseURL = "https://spclient.wg.spotify.com/color-lyrics/v2/track/"
	defaultServerTimeURL = "https://open.spotify.com/api/server-time"
)

var (
	trackIDRegex = regexp.MustCompile(`(?i)(?:https?://open\.spotify\.com/)?(?:track/|track:)([A-Za-z0-9]+)`)
)

func logTokenFailure(format string, args ...interface{}) {
	line := fmt.Sprintf("[spotifylyrics] "+format+"\n", args...)
	_, _ = fmt.Fprint(os.Stdout, line)
	_, _ = fmt.Fprint(os.Stderr, line)

	// Best-effort local log file for environments where stdout/stderr are not visible.
	logPath := filepath.Join(os.TempDir(), "spotifylyrics.log")
	f, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return
	}
	_, _ = f.WriteString(time.Now().Format(time.RFC3339) + " " + line)
	_ = f.Close()
}

func writeTokenFailureSnapshot(status int, body []byte) {
	payload := map[string]interface{}{
		"timestamp": time.Now().Format(time.RFC3339),
		"status":    status,
		"body":      string(body),
	}
	b, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		return
	}
	path := filepath.Join(os.TempDir(), "spotifylyrics-token-error.json")
	_ = os.WriteFile(path, b, 0o600)
}

type Client struct {
	spdc string

	hc                       *http.Client
	insecureSpotifyTransport http.RoundTripper

	tokenURL        string
	lyricsBaseURL   string
	serverTimeURL   string
	secretDictURL   string
	secretCachePath string

	cachePath string // token cache path

	lyricsCacheDir     string
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

func WithCachePath(path string) Option {
	return func(c *Client) { c.cachePath = path }
}

func WithSecretCachePath(path string) Option {
	return func(c *Client) { c.secretCachePath = path }
}

func WithLyricsCacheDir(dir string) Option {
	return func(c *Client) { c.lyricsCacheDir = dir }
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

// WithTokenUserAgent overrides the User-Agent for token-related calls.
func WithTokenUserAgent(ua string) Option {
	return func(c *Client) { c.tokenUserAgent = ua }
}

// WithLyricsUserAgent overrides the User-Agent for lyrics calls.
func WithLyricsUserAgent(ua string) Option {
	return func(c *Client) { c.lyricsUserAgent = ua }
}

// WithTokenTimeout sets the HTTP client timeout for token-related calls.
func WithTokenTimeout(d time.Duration) Option {
	return func(c *Client) { c.tokenTimeout = d }
}

// WithInsecureSpotifyTLS disables TLS verification for Spotify endpoints
// (server-time/token/lyrics) to match upstream behavior for some calls.
func WithInsecureSpotifyTLS(enabled bool) Option {
	return func(c *Client) { c.insecureSpotifyTLS = enabled }
}

// New creates a Spotify lyrics client. The sp_dc value is required; pass it in
// from the SP_DC environment variable or other source.
func New(spdc string, opts ...Option) (*Client, error) {
	spdc = strings.TrimSpace(spdc)
	if spdc == "" {
		return nil, &Error{Message: "SP_DC is required"}
	}
	cacheDir := defaultCacheDir()
	c := &Client{
		spdc:               spdc,
		hc:                 &http.Client{Timeout: 30 * time.Second},
		tokenURL:           defaultTokenURL,
		lyricsBaseURL:      defaultLyricsBaseURL,
		serverTimeURL:      defaultServerTimeURL,
		secretDictURL:      defaultSecretDictURL,
		secretCachePath:    filepath.Join(cacheDir, "secretDict_cache.json"),
		cachePath:          filepath.Join(cacheDir, "token.json"),
		lyricsCacheDir:     filepath.Join(cacheDir, "lyrics"),
		lyricsCacheTTL:     7 * 24 * time.Hour,
		lyricsCacheEnabled: true,
		// Upstream uses different UA strings per request.
		tokenTimeout:       600 * time.Second,
		tokenUserAgent:     "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
		lyricsUserAgent:    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/101.0.0.0 Safari/537.36",
		insecureSpotifyTLS: true,
	}
	for _, opt := range opts {
		opt(c)
	}
	if c.hc == nil {
		return nil, &Error{Message: "http client is nil"}
	}
	if strings.TrimSpace(c.tokenUserAgent) == "" || strings.TrimSpace(c.lyricsUserAgent) == "" {
		return nil, &Error{Message: "user agent is empty"}
	}
	if c.tokenTimeout <= 0 {
		return nil, &Error{Message: "token timeout must be > 0"}
	}
	// Precompute transport so Client use is race-free if called from multiple goroutines.
	if c.insecureSpotifyTLS {
		_ = c.spotifyTransport(true)
	}
	return c, nil
}

// TrackIDFromURL extracts a track ID from a Spotify URL or URI.
func TrackIDFromURL(s string) (string, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return "", fmt.Errorf("empty url")
	}

	// Try a real URL parse first.
	if strings.HasPrefix(s, "http://") || strings.HasPrefix(s, "https://") {
		u, err := url.Parse(s)
		if err == nil {
			parts := strings.Split(strings.Trim(u.Path, "/"), "/")
			if len(parts) >= 2 && strings.EqualFold(parts[0], "track") && parts[1] != "" {
				return parts[1], nil
			}
		}
	}

	// Support spotify:track:{id} and other simple forms.
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

	// Clone a base transport (prefer the configured client transport).
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
	secret, version, err := fetchLatestSecret(ctx, c.hc, c.secretDictURL, c.secretCachePath)
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
		logTokenFailure("token params failed: %v", err)
		return nil, err
	}
	u := c.tokenURL + "?" + params.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		logTokenFailure("token request build failed: %v", err)
		return nil, err
	}
	req.Header.Set("User-Agent", c.tokenUserAgent)
	req.Header.Set("Cookie", "sp_dc="+c.spdc)

	hc := c.spotifyHTTPClient(c.tokenTimeout, c.insecureSpotifyTLS)
	resp, err := hc.Do(req)
	if err != nil {
		logTokenFailure("token http call failed: %v", err)
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		logTokenFailure("token response read failed: %v", err)
		return nil, err
	}
	if resp.StatusCode >= 400 {
		writeTokenFailureSnapshot(resp.StatusCode, body)
		msg := strings.TrimSpace(string(body))
		if msg == "" {
			msg = "token request failed"
		} else {
			// Keep errors readable in UI/logging.
			const maxLen = 600
			if len(msg) > maxLen {
				msg = msg[:maxLen] + "..."
			}
			msg = "token request failed: " + msg
		}
		logTokenFailure("token request failed (status=%d): %s", resp.StatusCode, msg)
		return nil, &Error{Status: resp.StatusCode, Message: msg}
	}

	var tr TokenResponse
	if err := json.Unmarshal(body, &tr); err != nil {
		logTokenFailure("token json decode failed: %v", err)
		return nil, fmt.Errorf("invalid token response: %w", err)
	}
	if tr.AccessToken == "" || tr.IsAnonymous {
		logTokenFailure("token validation failed: anonymous or empty access token")
		return nil, &Error{Message: "SP_DC appears to be invalid"}
	}
	if tr.AccessTokenExpirationTimestampMs == 0 {
		logTokenFailure("token validation failed: missing expiration timestamp")
		return nil, &Error{Message: "token response missing expiration timestamp"}
	}

	// Cache the raw JSON so future schema additions don't break us.
	if err := writeFileAtomic(c.cachePath, body, 0o600); err != nil {
		logTokenFailure("token cache write failed: %v", err)
		return nil, fmt.Errorf("failed to write token cache: %w", err)
	}
	return &tr, nil
}

func (c *Client) readCachedToken() (*TokenResponse, error) {
	b, err := os.ReadFile(c.cachePath)
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
	if strings.TrimSpace(c.cachePath) == "" {
		return
	}
	// Best-effort invalidation; callers already have the primary error context.
	_ = os.Remove(c.cachePath)
}

// EnsureToken makes sure a non-expired token exists (uses the cache file).
func (c *Client) EnsureToken(ctx context.Context) (*TokenResponse, error) {
	tr, err := c.readCachedToken()
	if err == nil {
		nowMs := time.Now().UnixMilli()
		if tr.AccessTokenExpirationTimestampMs > nowMs {
			return tr, nil
		}
	}
	// Cache is missing/invalid/expired; fetch a new one.
	return c.fetchToken(ctx)
}

// GetLyrics fetches the lyrics for a track ID.
func (c *Client) GetLyrics(ctx context.Context, trackID string) (*LyricsResponse, error) {
	trackID = strings.TrimSpace(trackID)
	if trackID == "" {
		return nil, &Error{Message: "track id is required"}
	}

	if c.lyricsCacheEnabled {
		if lr, ok := readLyricsCache(c.lyricsCacheDir, trackID, c.lyricsCacheTTL); ok {
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
		// ok
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
		// Best-effort; don't fail the request if the cache write fails.
		_ = writeLyricsCache(c.lyricsCacheDir, trackID, body)
	}
	return &lr, nil
}

// GetLyricsFromURL extracts the track id from a Spotify URL/URI and fetches lyrics.
func (c *Client) GetLyricsFromURL(ctx context.Context, trackURL string) (*LyricsResponse, error) {
	id, err := TrackIDFromURL(trackURL)
	if err != nil {
		return nil, err
	}
	return c.GetLyrics(ctx, id)
}
