package pacman

import (
	"os"
	"strings"
	"testing"
)

func TestParseCheckupdatesLineRequiresArrowShape(t *testing.T) {
	item, ok := parseCheckupdatesLine("linux 6.8.1.arch1-1 -> 6.8.2.arch1-1")
	if !ok {
		t.Fatal("expected valid checkupdates line")
	}

	if item.Name != "linux" || item.OldVersion != "6.8.1.arch1-1" || item.NewVersion != "6.8.2.arch1-1" || item.Source != "pacman" {
		t.Fatalf("unexpected update item: %#v", item)
	}

	invalid := []string{
		"linux 6.8.1.arch1-1 6.8.2.arch1-1",
		"linux 6.8.1.arch1-1 => 6.8.2.arch1-1",
		"linux 6.8.1.arch1-1 ->",
		"linux 6.8.1.arch1-1 -> 6.8.2.arch1-1 extra",
	}
	for _, line := range invalid {
		if item, ok := parseCheckupdatesLine(line); ok {
			t.Fatalf("expected invalid line %q to be rejected, got %#v", line, item)
		}
	}
}

func TestParseYayQuaOutputUsesAURHelperBoundary(t *testing.T) {
	got := parseYayQuaOutput("foo 1.0-1 -> 1.1-1\nbar-bin 2:3.0-4 -> 2:3.1-1\n\n")
	want := []UpdateItem{
		{Name: "foo", OldVersion: "1.0-1", NewVersion: "1.1-1", Source: "aur"},
		{Name: "bar-bin", OldVersion: "2:3.0-4", NewVersion: "2:3.1-1", Source: "aur"},
	}
	if len(got) != len(want) {
		t.Fatalf("updates = %#v, want %#v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("updates = %#v, want %#v", got, want)
		}
	}
}

func TestParseYayQuaOutputRejectsUnexpectedLines(t *testing.T) {
	got := parseYayQuaOutput("foo 1.0-1 => 1.1-1\nmissing-arrow 1.0-1 1.1-1\nok 1 -> 2\n")
	want := []UpdateItem{{Name: "ok", OldVersion: "1", NewVersion: "2", Source: "aur"}}
	if len(got) != len(want) || got[0] != want[0] {
		t.Fatalf("updates = %#v, want %#v", got, want)
	}
}

func TestNoCustomVersionComparator(t *testing.T) {
	for _, symbol := range []string{"vercmp", "rpmvercmp"} {
		if packageSourceContains(t, symbol+"(") {
			t.Fatalf("custom %s implementation should not be owned by qs-go", symbol)
		}
	}
}

func packageSourceContains(t *testing.T, needle string) bool {
	t.Helper()
	raw, err := os.ReadFile("pacman.go")
	if err != nil {
		t.Fatalf("read pacman.go: %v", err)
	}
	return strings.Contains(string(raw), needle)
}
