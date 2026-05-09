package spotify

import "testing"

func TestTrackIDFromURLAcceptsBareID(t *testing.T) {
	got, err := TrackIDFromURL("1QrbZhFYlViXd60g130vw1")
	if err != nil {
		t.Fatal(err)
	}
	if got != "1QrbZhFYlViXd60g130vw1" {
		t.Fatalf("TrackIDFromURL() = %q, want bare id", got)
	}
}
