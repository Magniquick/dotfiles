package lyricsprovider

import "context"

const (
	// SyncTypeWord marks word-level synchronized lyrics.
	SyncTypeWord = "WORD_SYNCED"
	// SyncTypeLine marks line-level synchronized lyrics.
	SyncTypeLine = "LINE_SYNCED"
	// SyncTypeNone marks unsynchronized plain-text lyrics.
	SyncTypeNone = "UNSYNCED"
)

// Request describes the track metadata available to lyric providers.
type Request struct {
	SPDC            string
	SpotifyTrackRef string
	TrackName       string
	ArtistName      string
	AlbumName       string
	LengthMicros    string
}

// Segment describes one word-level lyric timing span.
type Segment struct {
	StartTimeMs string `json:"startTimeMs"`
	EndTimeMs   string `json:"endTimeMs"`
	Text        string `json:"text"`
}

// Line describes one lyric line and optional word-level timing segments.
type Line struct {
	StartTimeMs string    `json:"startTimeMs"`
	EndTimeMs   string    `json:"endTimeMs"`
	Words       string    `json:"words"`
	Segments    []Segment `json:"segments,omitempty"`
}

// Result is the normalized lyric payload returned by a provider.
type Result struct {
	Provider string
	SyncType string
	Lines    []Line
}

// Provider is implemented by concrete lyric source backends.
type Provider interface {
	Name() string
	Supports(Request) bool
	Fetch(context.Context, Request) (*Result, error)
}

// RankSyncType returns a preference score for a sync type.
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

// SourceFor returns a stable source label for provider and sync type.
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
