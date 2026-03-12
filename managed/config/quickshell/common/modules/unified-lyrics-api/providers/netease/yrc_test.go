package netease

import "testing"

func TestParseYRC_ReturnsWordTimedLines(t *testing.T) {
	lines := parseYRC("[1000,2000](1000,500,0)Hel(1500,500,0)lo(2000,1000,0) world")
	if len(lines) != 1 {
		t.Fatalf("len(lines) = %d, want 1", len(lines))
	}
	if lines[0].StartTimeMs != "1000" || lines[0].EndTimeMs != "3000" {
		t.Fatalf("line timing = %#v, want 1000-3000", lines[0])
	}
	if lines[0].Words != "Hello world" {
		t.Fatalf("words = %q, want Hello world", lines[0].Words)
	}
	if len(lines[0].Segments) != 3 {
		t.Fatalf("len(segments) = %d, want 3", len(lines[0].Segments))
	}
	if lines[0].Segments[1].Text != "lo" {
		t.Fatalf("segment[1].text = %q, want lo", lines[0].Segments[1].Text)
	}
}

func TestParseYRC_FallsBackToLineTextWithoutSegments(t *testing.T) {
	lines := parseYRC("[1000,2000]hello world")
	if len(lines) != 1 {
		t.Fatalf("len(lines) = %d, want 1", len(lines))
	}
	if lines[0].Words != "hello world" {
		t.Fatalf("words = %q, want hello world", lines[0].Words)
	}
	if len(lines[0].Segments) != 0 {
		t.Fatalf("segments = %#v, want none", lines[0].Segments)
	}
}
