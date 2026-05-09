// Package pacman checks for Arch Linux package updates via checkupdates + yay.
package pacman

import (
	"context"
	"encoding/json"
	"os/exec"
	"strings"
	"time"
)

// UpdateItem represents a single pending update.
type UpdateItem struct {
	Name       string `json:"name"`
	OldVersion string `json:"old_version"`
	NewVersion string `json:"new_version"`
	Source     string `json:"source"` // "pacman" | "aur"
}

// Output is the JSON payload returned by Refresh.
type Output struct {
	Updates         []UpdateItem `json:"updates"`
	UpdatesCount    int          `json:"updates_count"`
	AurUpdatesCount int          `json:"aur_updates_count"`
	ItemsCount      int          `json:"items_count"`
	UpdatesText     string       `json:"updates_text"`
	AurUpdatesText  string       `json:"aur_updates_text"`
	LastChecked     string       `json:"last_checked"`
	HasUpdates      bool         `json:"has_updates"`
	Error           string       `json:"error,omitempty"`
}

// Refresh runs checkupdates (and optionally AUR) and returns JSON.
func Refresh(noAur bool) string {
	updates, err := runCheckupdates()
	var errs []string
	if err != nil {
		errs = append(errs, "checkupdates: "+err.Error())
	}

	var aurUpdates []UpdateItem
	if !noAur {
		aur, err2 := checkAUR()
		if err2 != nil {
			errs = append(errs, "AUR: "+err2.Error())
		} else {
			aurUpdates = aur
		}
	}

	all := append(updates, aurUpdates...)

	pacCount := len(updates)
	aurCount := len(aurUpdates)
	total := len(all)

	var updatesText, aurText string
	if pacCount > 0 {
		names := make([]string, 0, pacCount)
		for _, u := range updates {
			names = append(names, u.Name)
		}
		updatesText = strings.Join(names, "\n")
	}
	if aurCount > 0 {
		names := make([]string, 0, aurCount)
		for _, u := range aurUpdates {
			names = append(names, u.Name)
		}
		aurText = strings.Join(names, "\n")
	}

	out := Output{
		Updates:         all,
		UpdatesCount:    pacCount,
		AurUpdatesCount: aurCount,
		ItemsCount:      total,
		UpdatesText:     updatesText,
		AurUpdatesText:  aurText,
		LastChecked:     time.Now().Format("15:04"),
		HasUpdates:      total > 0,
	}
	if len(errs) > 0 {
		out.Error = strings.Join(errs, "; ")
	}

	b, _ := json.Marshal(out)
	return string(b)
}

// Sync runs `pacman -Sy` to refresh package databases (requires sudo/polkit).
func Sync() string {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	_, err := exec.CommandContext(ctx, "sudo", "-n", "pacman", "-Sy", "--noconfirm").Output()
	if err != nil {
		b, _ := json.Marshal(map[string]string{"error": err.Error()})
		return string(b)
	}
	b, _ := json.Marshal(map[string]bool{"ok": true})
	return string(b)
}

// --- checkupdates ---

func runCheckupdates() ([]UpdateItem, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	out, err := exec.CommandContext(ctx, "checkupdates").Output()
	// checkupdates exits 2 when there are no updates (not an error).
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok && ee.ExitCode() == 2 {
			return nil, nil
		}
		return nil, err
	}
	return parseCheckupdatesOutput(string(out)), nil
}

func parseCheckupdatesOutput(output string) []UpdateItem {
	var items []UpdateItem
	for _, line := range strings.Split(strings.TrimSpace(output), "\n") {
		if line == "" {
			continue
		}
		item, ok := parseCheckupdatesLine(line)
		if !ok {
			continue
		}
		items = append(items, item)
	}
	return items
}

func parseCheckupdatesLine(line string) (UpdateItem, bool) {
	fields := strings.Fields(line)
	if len(fields) != 4 || fields[2] != "->" {
		return UpdateItem{}, false
	}
	return UpdateItem{
		Name:       fields[0],
		OldVersion: fields[1],
		NewVersion: fields[3],
		Source:     "pacman",
	}, true
}

func checkAUR() ([]UpdateItem, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	out, err := exec.CommandContext(ctx, "yay", "-Qua").Output()
	if err != nil {
		return nil, err
	}
	return parseYayQuaOutput(string(out)), nil
}

func parseYayQuaOutput(output string) []UpdateItem {
	var items []UpdateItem
	for _, line := range strings.Split(strings.TrimSpace(output), "\n") {
		fields := strings.Fields(line)
		if len(fields) != 4 || fields[2] != "->" {
			continue
		}
		items = append(items, UpdateItem{
			Name:       fields[0],
			OldVersion: fields[1],
			NewVersion: fields[3],
			Source:     "aur",
		})
	}
	return items
}
