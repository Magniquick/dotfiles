package spotify

type serverTimeResponse struct {
	ServerTime int64 `json:"serverTime"`
}

type TokenResponse struct {
	AccessToken                      string `json:"accessToken"`
	AccessTokenExpirationTimestampMs int64  `json:"accessTokenExpirationTimestampMs"`
	IsAnonymous                      bool   `json:"isAnonymous"`
}

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
