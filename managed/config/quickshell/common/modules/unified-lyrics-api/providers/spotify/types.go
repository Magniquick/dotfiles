package spotify

type serverTimeResponse struct {
	ServerTime int64 `json:"serverTime"`
}

// TokenResponse is Spotify's web-player token response.
type TokenResponse struct {
	AccessToken                      string `json:"accessToken"`
	AccessTokenExpirationTimestampMs int64  `json:"accessTokenExpirationTimestampMs"`
	IsAnonymous                      bool   `json:"isAnonymous"`
}

// LyricsResponse is Spotify's color-lyrics response.
type LyricsResponse struct {
	Lyrics Lyrics `json:"lyrics"`
}

// Lyrics contains Spotify lyric timing and line data.
type Lyrics struct {
	SyncType string `json:"syncType"`
	Lines    []Line `json:"lines"`
}

// Line describes one Spotify lyric line.
type Line struct {
	StartTimeMs string   `json:"startTimeMs"`
	Words       string   `json:"words"`
	Syllables   []string `json:"syllables"`
	EndTimeMs   string   `json:"endTimeMs"`
}

// LRCLine is one formatted LRC lyric row.
type LRCLine struct {
	TimeTag string `json:"timeTag"`
	Words   string `json:"words"`
}

// SRTLine is one formatted SRT caption row.
type SRTLine struct {
	Index     int    `json:"index"`
	StartTime string `json:"startTime"`
	EndTime   string `json:"endTime"`
	Words     string `json:"words"`
}
