package systemd

import (
	"encoding/json"
	"testing"
)

func TestParseFailedUnitsNormalizesSystemctlJSON(t *testing.T) {
	got, err := parseFailedUnitsJSON([]byte(`[
		{
			"unit": "alpha.service",
			"load": "loaded",
			"active": "failed",
			"sub": "failed",
			"description": "Alpha worker"
		},
		{
			"unit": "",
			"load": "loaded",
			"active": "failed",
			"sub": "failed",
			"description": "ignored because unit is empty"
		},
		{
			"unit": "beta.timer",
			"load": null,
			"active": "failed",
			"sub": "failed"
		}
	]`))
	if err != nil {
		t.Fatalf("parse failed units: %v", err)
	}

	want := []FailedUnit{
		{
			Unit:        "alpha.service",
			Load:        "loaded",
			Active:      "failed",
			Sub:         "failed",
			Description: "Alpha worker",
		},
		{
			Unit:   "beta.timer",
			Active: "failed",
			Sub:    "failed",
		},
	}

	if len(got) != len(want) {
		t.Fatalf("units = %#v, want %#v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("units = %#v, want %#v", got, want)
		}
	}
}

func TestRefreshOutputShapeCountsBothScopes(t *testing.T) {
	state := buildOutput([]FailedUnit{
		{Unit: "system-a.service"},
		{Unit: "system-b.service"},
	}, []FailedUnit{
		{Unit: "user-a.service"},
	}, "15:04", []string{"system: boom"})

	if state.SystemFailedCount != 2 || state.UserFailedCount != 1 || state.FailedCount != 3 {
		t.Fatalf("unexpected counts: %#v", state)
	}
	if state.LastChecked != "15:04" {
		t.Fatalf("last checked = %q, want 15:04", state.LastChecked)
	}
	if state.Error != "system: boom" {
		t.Fatalf("error = %q, want system: boom", state.Error)
	}

	raw, err := json.Marshal(state)
	if err != nil {
		t.Fatalf("marshal state: %v", err)
	}
	var asMap map[string]any
	if err := json.Unmarshal(raw, &asMap); err != nil {
		t.Fatalf("unmarshal state: %v", err)
	}
	for _, key := range []string{"system_failed_count", "user_failed_count", "failed_count", "system_failed_units", "user_failed_units", "last_checked", "error"} {
		if _, ok := asMap[key]; !ok {
			t.Fatalf("missing json key %q in %s", key, raw)
		}
	}
}
