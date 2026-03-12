package spotify

import (
	"fmt"
	"strconv"
	"strings"
)

func msStringToInt64(ms string) (int64, error) {
	ms = strings.TrimSpace(ms)
	if ms == "" {
		return 0, fmt.Errorf("empty milliseconds value")
	}
	v, err := strconv.ParseInt(ms, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid milliseconds %q: %w", ms, err)
	}
	if v < 0 {
		return 0, fmt.Errorf("negative milliseconds %q", ms)
	}
	return v, nil
}
