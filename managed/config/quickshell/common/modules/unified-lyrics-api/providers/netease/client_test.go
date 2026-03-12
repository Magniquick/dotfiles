package netease

import (
	"testing"

	"unified-lyrics-api/internal/lyricsprovider"
)

func TestScoreSong_PrefersExactTitleArtistWithDuration(t *testing.T) {
	req := lyricsprovider.Request{
		TrackName:    "The Less I Know The Better",
		ArtistName:   "Tame Impala",
		AlbumName:    "Currents",
		LengthMicros: "216320000",
	}
	candidate := song{
		Name:     "The Less I Know The Better",
		Duration: 216320,
	}
	candidate.Artists = []struct {
		Name string "json:\"name\""
	}{{Name: "Tame Impala"}}
	candidate.Album.Name = "Currents"

	score, ok := scoreSong(req, candidate)
	if !ok {
		t.Fatal("scoreSong rejected exact candidate")
	}
	if score < 200 {
		t.Fatalf("score = %d, want >= 200", score)
	}
}

func TestScoreSong_RejectsMissingArtistMatch(t *testing.T) {
	req := lyricsprovider.Request{
		TrackName:  "Song",
		ArtistName: "Wanted Artist",
	}
	candidate := song{Name: "Song"}
	candidate.Artists = []struct {
		Name string "json:\"name\""
	}{{Name: "Different Artist"}}

	if score, ok := scoreSong(req, candidate); ok || score != 0 {
		t.Fatalf("scoreSong = (%d, %v), want rejection", score, ok)
	}
}
