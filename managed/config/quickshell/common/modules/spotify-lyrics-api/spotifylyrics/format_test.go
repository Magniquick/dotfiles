package spotifylyrics

import "testing"

func TestFormatMS(t *testing.T) {
	if got := FormatMS(960); got != "00:00.96" {
		t.Fatalf("FormatMS: got %q want %q", got, "00:00.96")
	}
	if got := FormatMS(4020); got != "00:04.02" {
		t.Fatalf("FormatMS: got %q want %q", got, "00:04.02")
	}
}

func TestLinesToSRT_UpstreamBehavior(t *testing.T) {
	lines := []Line{
		{StartTimeMs: "1000", Words: "a"},
		{StartTimeMs: "2500", Words: "b"},
		{StartTimeMs: "5000", Words: "c"},
	}
	srt, err := LinesToSRT(lines)
	if err != nil {
		t.Fatal(err)
	}
	if len(srt) != 2 {
		t.Fatalf("len: got %d want %d", len(srt), 2)
	}
	if srt[0].Index != 1 || srt[0].Words != "a" || srt[0].StartTime != "00:00:01,000" || srt[0].EndTime != "00:00:02,500" {
		t.Fatalf("first: %+v", srt[0])
	}
	if srt[1].Index != 2 || srt[1].Words != "b" || srt[1].StartTime != "00:00:02,500" || srt[1].EndTime != "00:00:05,000" {
		t.Fatalf("second: %+v", srt[1])
	}
}
