// Package pacman checks for Arch Linux package updates via checkupdates + AUR API.
package pacman

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os/exec"
	"strings"
	"time"
	"unicode"
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
	Updates        []UpdateItem `json:"updates"`
	UpdatesCount   int          `json:"updates_count"`
	AurUpdatesCount int         `json:"aur_updates_count"`
	ItemsCount     int          `json:"items_count"`
	UpdatesText    string       `json:"updates_text"`
	AurUpdatesText string       `json:"aur_updates_text"`
	LastChecked    string       `json:"last_checked"`
	HasUpdates     bool         `json:"has_updates"`
	Error          string       `json:"error,omitempty"`
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
	_, err := exec.Command("sudo", "-n", "pacman", "-Sy", "--noconfirm").Output()
	if err != nil {
		b, _ := json.Marshal(map[string]string{"error": err.Error()})
		return string(b)
	}
	b, _ := json.Marshal(map[string]bool{"ok": true})
	return string(b)
}

// --- checkupdates ---

func runCheckupdates() ([]UpdateItem, error) {
	out, err := exec.Command("checkupdates").Output()
	// checkupdates exits 2 when there are no updates (not an error).
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok && ee.ExitCode() == 2 {
			return nil, nil
		}
		return nil, err
	}
	var items []UpdateItem
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if line == "" {
			continue
		}
		// Format: "pkgname old_ver -> new_ver"
		fields := strings.Fields(line)
		if len(fields) < 4 {
			continue
		}
		items = append(items, UpdateItem{
			Name:       fields[0],
			OldVersion: fields[1],
			NewVersion: fields[3],
			Source:     "pacman",
		})
	}
	return items, nil
}

// --- AUR ---

type aurInfoResponse struct {
	Results []aurResult `json:"results"`
}

type aurResult struct {
	Name        string `json:"Name"`
	Version     string `json:"Version"`
}

func checkAUR() ([]UpdateItem, error) {
	// Get AUR-installed packages via `pacman -Qm`
	out, err := exec.Command("pacman", "-Qm").Output()
	if err != nil {
		return nil, err
	}
	type pkg struct{ name, version string }
	var pkgs []pkg
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) >= 2 {
			pkgs = append(pkgs, pkg{fields[0], fields[1]})
		}
	}
	if len(pkgs) == 0 {
		return nil, nil
	}

	// Query AUR info API
	names := make([]string, 0, len(pkgs))
	for _, p := range pkgs {
		names = append(names, "arg[]="+p.name)
	}
	url := "https://aur.archlinux.org/rpc/v5/info?" + strings.Join(names, "&")
	resp, err := httpGet(url)
	if err != nil {
		return nil, err
	}

	nameToAurVer := make(map[string]string, len(resp.Results))
	for _, r := range resp.Results {
		nameToAurVer[r.Name] = r.Version
	}

	var updates []UpdateItem
	for _, p := range pkgs {
		aurVer, ok := nameToAurVer[p.name]
		if !ok {
			continue
		}
		if vercmp(aurVer, p.version) > 0 {
			updates = append(updates, UpdateItem{
				Name:       p.name,
				OldVersion: p.version,
				NewVersion: aurVer,
				Source:     "aur",
			})
		}
	}
	return updates, nil
}

func httpGet(url string) (*aurInfoResponse, error) {
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("AUR API returned HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	var result aurInfoResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// --- vercmp: pacman-style RPM version comparison ---
// Returns -1, 0, or 1.

func vercmp(a, b string) int {
	epochA, verA := splitEpoch(a)
	epochB, verB := splitEpoch(b)
	if epochA != epochB {
		if epochA < epochB {
			return -1
		}
		return 1
	}

	verPartA, relA := splitRelease(verA)
	verPartB, relB := splitRelease(verB)

	if c := rpmvercmp(verPartA, verPartB); c != 0 {
		return c
	}

	if relA == "" && relB == "" {
		return 0
	}
	return rpmvercmp(relA, relB)
}

func splitEpoch(v string) (int, string) {
	if idx := strings.Index(v, ":"); idx >= 0 {
		var e int
		fmt.Sscanf(v[:idx], "%d", &e)
		return e, v[idx+1:]
	}
	return 0, v
}

func splitRelease(v string) (ver, rel string) {
	if idx := strings.LastIndex(v, "-"); idx >= 0 {
		return v[:idx], v[idx+1:]
	}
	return v, ""
}

// rpmvercmp compares two version strings using RPM algorithm.
func rpmvercmp(a, b string) int {
	if a == b {
		return 0
	}
	for {
		// Skip non-alphanumeric
		for len(a) > 0 && !isAlnum(rune(a[0])) && a[0] != '~' {
			a = a[1:]
		}
		for len(b) > 0 && !isAlnum(rune(b[0])) && b[0] != '~' {
			b = b[1:]
		}

		// Tilde sorts before everything
		aTilde := len(a) > 0 && a[0] == '~'
		bTilde := len(b) > 0 && b[0] == '~'
		if aTilde || bTilde {
			if !aTilde {
				return 1
			}
			if !bTilde {
				return -1
			}
			a, b = a[1:], b[1:]
			continue
		}

		// If one is empty, the other is "newer" only if it has more content
		if a == "" && b == "" {
			return 0
		}
		if a == "" {
			return -1
		}
		if b == "" {
			return 1
		}

		isDigitA := unicode.IsDigit(rune(a[0]))
		isDigitB := unicode.IsDigit(rune(b[0]))

		// Different types: digit segment > alpha segment
		if isDigitA != isDigitB {
			if isDigitA {
				return 1
			}
			return -1
		}

		var segA, segB string
		if isDigitA {
			segA, a = takeWhile(a, unicode.IsDigit)
			segB, b = takeWhile(b, unicode.IsDigit)
			// Numeric comparison: strip leading zeros and compare lengths
			segA = strings.TrimLeft(segA, "0")
			segB = strings.TrimLeft(segB, "0")
			if len(segA) != len(segB) {
				if len(segA) < len(segB) {
					return -1
				}
				return 1
			}
		} else {
			segA, a = takeWhile(a, unicode.IsLetter)
			segB, b = takeWhile(b, unicode.IsLetter)
		}

		if c := strings.Compare(segA, segB); c != 0 {
			return c
		}
	}
}

func isAlnum(r rune) bool {
	return unicode.IsLetter(r) || unicode.IsDigit(r)
}

func takeWhile(s string, pred func(rune) bool) (taken, rest string) {
	i := 0
	for i < len(s) && pred(rune(s[i])) {
		i++
	}
	return s[:i], s[i:]
}
