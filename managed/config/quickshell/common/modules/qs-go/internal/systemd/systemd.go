// Package systemd reports failed system and user units from structured systemctl JSON.
package systemd

import (
	"context"
	"encoding/json"
	"os/exec"
	"strings"
	"time"
)

// FailedUnit is the narrow unit shape exposed to QML.
type FailedUnit struct {
	Unit        string `json:"unit"`
	Load        string `json:"load"`
	Active      string `json:"active"`
	Sub         string `json:"sub"`
	Description string `json:"description"`
}

// Output is the JSON payload returned by Refresh.
type Output struct {
	SystemFailedCount int          `json:"system_failed_count"`
	UserFailedCount   int          `json:"user_failed_count"`
	FailedCount       int          `json:"failed_count"`
	SystemFailedUnits []FailedUnit `json:"system_failed_units"`
	UserFailedUnits   []FailedUnit `json:"user_failed_units"`
	LastChecked       string       `json:"last_checked"`
	Error             string       `json:"error"`
}

// Refresh returns the current failed-unit snapshot for both systemd scopes.
func Refresh() string {
	systemUnits, systemErr := listFailedUnits(false)
	userUnits, userErr := listFailedUnits(true)

	var errs []string
	if systemErr != nil {
		errs = append(errs, "system: "+systemErr.Error())
	}
	if userErr != nil {
		errs = append(errs, "user: "+userErr.Error())
	}

	out := buildOutput(systemUnits, userUnits, time.Now().Format("03:04 PM"), errs)
	raw, _ := json.Marshal(out)
	return string(raw)
}

func buildOutput(systemUnits, userUnits []FailedUnit, lastChecked string, errs []string) Output {
	return Output{
		SystemFailedCount: len(systemUnits),
		UserFailedCount:   len(userUnits),
		FailedCount:       len(systemUnits) + len(userUnits),
		SystemFailedUnits: systemUnits,
		UserFailedUnits:   userUnits,
		LastChecked:       lastChecked,
		Error:             strings.Join(errs, "; "),
	}
}

func listFailedUnits(user bool) ([]FailedUnit, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	args := []string{"list-units", "--failed", "--no-pager", "--output=json"}
	if user {
		args = append([]string{"--user"}, args...)
	}

	out, err := exec.CommandContext(ctx, "systemctl", args...).CombinedOutput()
	if err != nil {
		detail := strings.TrimSpace(string(out))
		if detail == "" {
			return nil, err
		}
		return nil, commandError{err: err, detail: detail}
	}
	return parseFailedUnitsJSON(out)
}

type commandError struct {
	err    error
	detail string
}

func (e commandError) Error() string {
	return e.err.Error() + ": " + e.detail
}

func parseFailedUnitsJSON(raw []byte) ([]FailedUnit, error) {
	var parsed []FailedUnit
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return nil, err
	}

	units := make([]FailedUnit, 0, len(parsed))
	for _, unit := range parsed {
		if unit.Unit == "" {
			continue
		}
		units = append(units, unit)
	}
	return units, nil
}
