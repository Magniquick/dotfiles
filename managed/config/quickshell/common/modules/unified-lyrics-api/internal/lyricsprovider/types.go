package lyricsprovider

import "context"

const (
	SyncTypeWord = "WORD_SYNCED"
	SyncTypeLine = "LINE_SYNCED"
	SyncTypeNone = "UNSYNCED"
)

type Request struct {
	SPDC            string
	SpotifyTrackRef string
	TrackName       string
	ArtistName      string
	AlbumName       string
	LengthMicros    string
}

type Segment struct {
	StartTimeMs string `json:"startTimeMs"`
	EndTimeMs   string `json:"endTimeMs"`
	Text        string `json:"text"`
}

type Line struct {
	StartTimeMs string    `json:"startTimeMs"`
	EndTimeMs   string    `json:"endTimeMs"`
	Words       string    `json:"words"`
	Segments    []Segment `json:"segments,omitempty"`
}

type Result struct {
	Provider string
	SyncType string
	Lines    []Line
}

type Provider interface {
	Name() string
	Supports(Request) bool
	Fetch(context.Context, Request) (*Result, error)
}

func RankSyncType(syncType string) int {
	switch syncType {
	case SyncTypeWord:
		return 3
	case SyncTypeLine:
		return 2
	default:
		return 1
	}
}

func SourceFor(provider, syncType string) string {
	switch syncType {
	case SyncTypeWord:
		return provider + "_word"
	case SyncTypeLine:
		return provider + "_synced"
	default:
		return provider + "_normal"
	}
}
