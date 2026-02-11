package spotifylyrics

type serverTimeResponse struct {
	ServerTime int64 `json:"serverTime"`
}

// TokenResponse is the JSON returned by https://open.spotify.com/api/token.
// We keep fields that this project needs.
type TokenResponse struct {
	AccessToken                      string `json:"accessToken"`
	AccessTokenExpirationTimestampMs int64  `json:"accessTokenExpirationTimestampMs"`
	IsAnonymous                      bool   `json:"isAnonymous"`
}

// LyricsResponse matches the shape returned by the lyrics endpoint:
// https://spclient.wg.spotify.com/color-lyrics/v2/track/{id}?format=json&market=from_token
type LyricsResponse struct {
	Lyrics Lyrics `json:"lyrics"`
}

type Lyrics struct {
	SyncType string `json:"syncType"`
	Lines    []Line `json:"lines"`
}

type Line struct {
	StartTimeMs string   `json:"startTimeMs"`
	Words       string   `json:"words"`
	Syllables   []string `json:"syllables"`
	EndTimeMs   string   `json:"endTimeMs"`
}

type LRCLine struct {
	TimeTag string `json:"timeTag"`
	Words   string `json:"words"`
}

type SRTLine struct {
	Index     int    `json:"index"`
	StartTime string `json:"startTime"`
	EndTime   string `json:"endTime"`
	Words     string `json:"words"`
}
