package netease

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math"
	mathrand "math/rand/v2"
	"net/http"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	"unified-lyrics-api/cache"
	"unified-lyrics-api/internal/lyricsprovider"
)

const (
	providerName        = "netease"
	baseURL             = "https://interface.music.163.com"
	appVersion          = "3.1.3.203419"
	defaultUserAgent    = "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/3.1.3.203419"
	defaultModel        = "ASUS ROG STRIX Z790"
	defaultOSVersion    = "Microsoft-Windows-10--build-22631-64bit"
	searchLimit         = 20
	sessionTTL          = 10 * 24 * time.Hour
	requestTimeout      = 15 * time.Second
	searchRejectScore   = 100
	durationTightWindow = 2 * time.Second
	durationMidWindow   = 5 * time.Second
	durationWideWindow  = 10 * time.Second
)

var (
	featSuffixRe      = regexp.MustCompile(`(?i)\s*[\(\[]\s*(feat|ft|with|remaster|version|live|edit)[^)\]]*[\)\]]`)
	nonAlnumSpaceRe   = regexp.MustCompile(`[^\p{L}\p{N}]+`)
	whitespaceTrimRe  = regexp.MustCompile(`\s+`)
	clientSignCharSet = []rune("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
	deviceIDs         = []string{
		"AA9955F5FE37BA7EAF48F8EF0C9966B28293CC8D6415CCD93549",
		"C4BE5BA8E337E26A1ECA938DAF7DDC6D99AA353D9E2E69F5DE2A",
		"2A6626990ED0B095ADBF14D63D91C6F8AE4CF352FF9BD1FE724E",
		"184117F946D9CF013300B74BAAFF42C04B74CE59EDA3A7B31C8E",
		"7051B0BEB96D5DC0DA8C17A034008DE086A21AB833EA41D321FF",
		"90D08AFA4FD3368D3ADD9C7BEB9D40B38066E55B4B2E9C123A26",
	}
)

type Client struct {
	hc       *http.Client
	cacheDir string

	mu      sync.Mutex
	session *sessionState
}

type sessionState struct {
	UserID int64             `json:"userId"`
	Cookie map[string]string `json:"cookie"`
	Expire int64             `json:"expire"`
}

type apiResponse struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type anonymousResponse struct {
	apiResponse
	UserID int64 `json:"userId"`
}

type searchResponse struct {
	apiResponse
	Data struct {
		Resources []searchResource `json:"resources"`
	} `json:"data"`
}

type searchResource struct {
	BaseInfo struct {
		SimpleSongData song `json:"simpleSongData"`
	} `json:"baseInfo"`
}

type song struct {
	ID       int64  `json:"id"`
	Name     string `json:"name"`
	Duration int64  `json:"dt"`
	Artists  []struct {
		Name string `json:"name"`
	} `json:"ar"`
	Album struct {
		Name string `json:"name"`
	} `json:"al"`
}

type lyricsBlock struct {
	Lyric string `json:"lyric"`
}

type lyricsResponse struct {
	apiResponse
	YRC lyricsBlock `json:"yrc"`
	LRC lyricsBlock `json:"lrc"`
}

type scoredSong struct {
	song  song
	score int
}

func New(cacheDir string) *Client {
	cacheDir = strings.TrimSpace(cacheDir)
	if cacheDir == "" {
		cacheDir = cache.DefaultDir()
	}
	return &Client{
		hc:       &http.Client{Timeout: requestTimeout},
		cacheDir: cacheDir,
	}
}

func (c *Client) Name() string {
	return providerName
}

func (c *Client) Supports(req lyricsprovider.Request) bool {
	return strings.TrimSpace(req.TrackName) != "" && strings.TrimSpace(req.ArtistName) != ""
}

func (c *Client) Fetch(ctx context.Context, req lyricsprovider.Request) (*lyricsprovider.Result, error) {
	if !c.Supports(req) {
		return nil, nil
	}

	match, err := c.searchBestSong(ctx, req)
	if err != nil {
		return nil, err
	}

	lyrics, err := c.fetchLyrics(ctx, match.ID)
	if err != nil {
		return nil, err
	}

	if lines := parseYRC(lyrics.YRC.Lyric); len(lines) > 0 {
		return &lyricsprovider.Result{
			Provider: providerName,
			SyncType: lyricsprovider.SyncTypeWord,
			Lines:    lines,
		}, nil
	}

	lrc := strings.TrimSpace(lyrics.LRC.Lyric)
	if lrc == "" {
		return nil, fmt.Errorf("lyrics not found")
	}
	lines := lyricsprovider.ParseSyncedLRC(lrc)
	if len(lines) > 0 {
		return &lyricsprovider.Result{
			Provider: providerName,
			SyncType: lyricsprovider.SyncTypeLine,
			Lines:    lines,
		}, nil
	}
	lines = lyricsprovider.ParsePlainText(lrc)
	if len(lines) == 0 {
		return nil, fmt.Errorf("lyrics not found")
	}
	return &lyricsprovider.Result{
		Provider: providerName,
		SyncType: lyricsprovider.SyncTypeNone,
		Lines:    lines,
	}, nil
}

func (c *Client) searchBestSong(ctx context.Context, req lyricsprovider.Request) (*song, error) {
	query := strings.TrimSpace(req.TrackName + " " + req.ArtistName)
	if query == "" {
		return nil, fmt.Errorf("empty search query")
	}

	var payload searchResponse
	if err := c.request(ctx, "/eapi/search/song/list/page", map[string]any{
		"limit":       strconv.Itoa(searchLimit),
		"offset":      "0",
		"keyword":     query,
		"scene":       "NORMAL",
		"needCorrect": "true",
	}, &payload); err != nil {
		return nil, err
	}
	if len(payload.Data.Resources) == 0 {
		return nil, fmt.Errorf("lyrics not found")
	}

	scored := make([]scoredSong, 0, len(payload.Data.Resources))
	for _, resource := range payload.Data.Resources {
		candidate := resource.BaseInfo.SimpleSongData
		if candidate.ID == 0 {
			continue
		}
		score, ok := scoreSong(req, candidate)
		if !ok {
			continue
		}
		scored = append(scored, scoredSong{song: candidate, score: score})
	}
	if len(scored) == 0 {
		return nil, fmt.Errorf("lyrics not found")
	}

	slices.SortFunc(scored, func(a, b scoredSong) int {
		if a.score == b.score {
			return 0
		}
		if a.score > b.score {
			return -1
		}
		return 1
	})
	if scored[0].score < searchRejectScore {
		return nil, fmt.Errorf("lyrics not found")
	}
	return &scored[0].song, nil
}

func scoreSong(req lyricsprovider.Request, candidate song) (int, bool) {
	wantTitle := normalizeMatch(strings.TrimSpace(req.TrackName))
	wantArtist := normalizeMatch(strings.TrimSpace(req.ArtistName))
	wantAlbum := normalizeMatch(strings.TrimSpace(req.AlbumName))
	if wantTitle == "" || wantArtist == "" {
		return 0, false
	}

	titleScore := scoreString(wantTitle, normalizeMatch(candidate.Name), 100, 60)
	artistScore := 0
	for _, artist := range candidate.Artists {
		artistScore = max(artistScore, scoreString(wantArtist, normalizeMatch(artist.Name), 80, 40))
	}
	if titleScore == 0 || artistScore == 0 {
		return 0, false
	}

	score := titleScore + artistScore
	if wantAlbum != "" {
		score += scoreString(wantAlbum, normalizeMatch(candidate.Album.Name), 20, 10)
	}

	if wantMs := parseLengthMicros(req.LengthMicros); wantMs > 0 && candidate.Duration > 0 {
		delta := time.Duration(math.Abs(float64(candidate.Duration-wantMs))) * time.Millisecond
		switch {
		case delta <= durationTightWindow:
			score += 20
		case delta <= durationMidWindow:
			score += 10
		case delta <= durationWideWindow:
			score += 5
		}
	}

	return score, true
}

func scoreString(want, have string, exactScore, fuzzyScore int) int {
	if want == "" || have == "" {
		return 0
	}
	if want == have {
		return exactScore
	}
	if strings.Contains(have, want) || strings.Contains(want, have) {
		return fuzzyScore
	}
	return 0
}

func normalizeMatch(s string) string {
	s = strings.TrimSpace(strings.ToLower(s))
	s = featSuffixRe.ReplaceAllString(s, "")
	s = nonAlnumSpaceRe.ReplaceAllString(s, " ")
	s = whitespaceTrimRe.ReplaceAllString(s, " ")
	return strings.TrimSpace(s)
}

func parseLengthMicros(v string) int64 {
	s := strings.TrimSpace(v)
	if s == "" {
		return 0
	}
	us, err := strconv.ParseInt(s, 10, 64)
	if err != nil || us <= 0 {
		return 0
	}
	return us / 1_000_000
}

func (c *Client) fetchLyrics(ctx context.Context, songID int64) (*lyricsResponse, error) {
	var payload lyricsResponse
	if err := c.request(ctx, "/eapi/song/lyric/v1", map[string]any{
		"id": songID,
		"lv": "-1",
		"tv": "-1",
		"rv": "-1",
		"yv": "-1",
	}, &payload); err != nil {
		return nil, err
	}
	return &payload, nil
}

func (c *Client) request(ctx context.Context, path string, params map[string]any, out any) error {
	state, err := c.ensureSession(ctx)
	if err != nil {
		return err
	}

	if params == nil {
		params = map[string]any{}
	}
	params["e_r"] = true
	params["header"] = paramsHeader(state.Cookie)

	body, err := encryptEapiParams(strings.Replace(path, "eapi", "api", 1), params)
	if err != nil {
		return err
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, baseURL+path, strings.NewReader(body))
	if err != nil {
		return err
	}
	setCommonHeaders(httpReq.Header, state.Cookie)

	resp, err := c.hc.Do(httpReq)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("netease api error (HTTP %d)", resp.StatusCode)
	}

	enc, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	plain, err := decryptEapiResponse(enc)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(plain, out); err != nil {
		return fmt.Errorf("invalid netease response: %w", err)
	}

	var api apiResponse
	if err := json.Unmarshal(plain, &api); err == nil && api.Code != 0 && api.Code != http.StatusOK {
		if strings.TrimSpace(api.Message) != "" {
			return fmt.Errorf("netease api error: %s", strings.TrimSpace(api.Message))
		}
		return fmt.Errorf("netease api error: code %d", api.Code)
	}
	return nil
}

func (c *Client) ensureSession(ctx context.Context) (*sessionState, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.session != nil && time.Now().Unix() < c.session.Expire {
		return c.session, nil
	}
	if state, ok := c.readCachedSession(); ok {
		c.session = state
		return state, nil
	}

	state, err := c.bootstrapAnonymousSession(ctx)
	if err != nil {
		return nil, err
	}
	c.session = state
	c.writeCachedSession(state)
	return state, nil
}

func (c *Client) readCachedSession() (*sessionState, bool) {
	b, _, err := cache.ReadPayload(c.cacheDir, cache.ProviderSessionKey(providerName, "anonymous"))
	if err != nil {
		return nil, false
	}
	var state sessionState
	if json.Unmarshal(b, &state) != nil {
		return nil, false
	}
	if time.Now().Unix() >= state.Expire || len(state.Cookie) == 0 {
		return nil, false
	}
	return &state, true
}

func (c *Client) writeCachedSession(state *sessionState) {
	if state == nil {
		return
	}
	b, err := json.Marshal(state)
	if err != nil {
		return
	}
	_ = cache.WritePayload(c.cacheDir, cache.ProviderSessionKey(providerName, "anonymous"), b)
}

func (c *Client) bootstrapAnonymousSession(ctx context.Context) (*sessionState, error) {
	deviceID := deviceIDs[mathrand.IntN(len(deviceIDs))]
	clientSign, err := randomClientSign()
	if err != nil {
		return nil, err
	}

	preCookie := map[string]string{
		"os":         "pc",
		"deviceId":   deviceID,
		"osver":      defaultOSVersion,
		"clientSign": clientSign,
		"channel":    "netease",
		"mode":       defaultModel,
		"appver":     appVersion,
	}
	params := map[string]any{
		"username": anonymousUsername(deviceID),
	}
	params["e_r"] = true
	params["header"] = paramsHeader(preCookie)

	body, err := encryptEapiParams("/api/register/anonimous", params)
	if err != nil {
		return nil, err
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, baseURL+"/eapi/register/anonimous", strings.NewReader(body))
	if err != nil {
		return nil, err
	}
	setCommonHeaders(httpReq.Header, preCookie)

	resp, err := c.hc.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("netease anonymous login failed (HTTP %d)", resp.StatusCode)
	}
	enc, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	plain, err := decryptEapiResponse(enc)
	if err != nil {
		return nil, err
	}
	var payload anonymousResponse
	if err := json.Unmarshal(plain, &payload); err != nil {
		return nil, fmt.Errorf("invalid netease login response: %w", err)
	}
	if payload.Code != http.StatusOK {
		return nil, fmt.Errorf("netease anonymous login failed: code %d", payload.Code)
	}

	cookie := map[string]string{
		"WEVNSM":     "1.0.0",
		"os":         preCookie["os"],
		"deviceId":   preCookie["deviceId"],
		"osver":      preCookie["osver"],
		"clientSign": preCookie["clientSign"],
		"channel":    preCookie["channel"],
		"mode":       preCookie["mode"],
		"appver":     preCookie["appver"],
	}
	for _, entry := range resp.Cookies() {
		if strings.TrimSpace(entry.Name) == "" || strings.TrimSpace(entry.Value) == "" {
			continue
		}
		cookie[entry.Name] = entry.Value
	}
	if _, ok := cookie["WNMCID"]; !ok {
		cookie["WNMCID"] = randomWNMCID()
	}

	return &sessionState{
		UserID: payload.UserID,
		Cookie: cookie,
		Expire: time.Now().Add(sessionTTL).Unix(),
	}, nil
}

func setCommonHeaders(header http.Header, cookie map[string]string) {
	header.Set("Accept", "*/*")
	header.Set("Content-Type", "application/x-www-form-urlencoded")
	header.Set("Mconfig-Info", `{"IuRPVVmc3WWul9fT":{"version":733184,"appver":"3.1.3.203419"}}`)
	header.Set("Origin", "orpheus://orpheus")
	header.Set("User-Agent", defaultUserAgent)
	header.Set("Sec-Ch-Ua", `"Chromium";v="91"`)
	header.Set("Sec-Ch-Ua-Mobile", "?0")
	header.Set("Sec-Fetch-Site", "cross-site")
	header.Set("Sec-Fetch-Mode", "cors")
	header.Set("Sec-Fetch-Dest", "empty")
	header.Set("Accept-Language", "en-US,en;q=0.9")

	if len(cookie) > 0 {
		keys := make([]string, 0, len(cookie))
		for key := range cookie {
			keys = append(keys, key)
		}
		slices.Sort(keys)
		parts := make([]string, 0, len(keys))
		for _, key := range keys {
			if strings.TrimSpace(cookie[key]) == "" {
				continue
			}
			parts = append(parts, key+"="+cookie[key])
		}
		header.Set("Cookie", strings.Join(parts, "; "))
	}
}

func paramsHeader(cookie map[string]string) string {
	body, _ := json.Marshal(map[string]any{
		"clientSign": cookie["clientSign"],
		"os":         cookie["os"],
		"appver":     cookie["appver"],
		"deviceId":   cookie["deviceId"],
		"requestId":  0,
		"osver":      cookie["osver"],
	})
	return string(body)
}

func randomHex(n int) (string, error) {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}

func randomClientSign() (string, error) {
	macBytes := make([]byte, 6)
	if _, err := rand.Read(macBytes); err != nil {
		return "", err
	}
	mac := make([]string, 0, 6)
	for _, b := range macBytes {
		mac = append(mac, strings.ToUpper(hex.EncodeToString([]byte{b})))
	}
	randomStr := make([]rune, 8)
	for i := range randomStr {
		randomStr[i] = clientSignCharSet[mathrand.IntN(len(clientSignCharSet))]
	}
	hashPart, err := randomHex(32)
	if err != nil {
		return "", err
	}
	return strings.Join(mac, ":") + "@@@" + string(randomStr) + "@@@@@@" + hashPart, nil
}

func randomWNMCID() string {
	const letters = "abcdefghijklmnopqrstuvwxyz"
	buf := make([]byte, 6)
	for i := range buf {
		buf[i] = letters[mathrand.IntN(len(letters))]
	}
	return string(buf) + "." + strconv.FormatInt(time.Now().Add(-5*time.Second).UnixMilli(), 10) + ".01.0"
}
