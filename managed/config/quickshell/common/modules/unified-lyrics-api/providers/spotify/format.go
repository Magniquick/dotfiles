package spotify

import (
	"fmt"
	"strings"
)

func FormatMS(milliseconds int64) string {
	thSecs := milliseconds / 1000
	minutes := thSecs / 60
	seconds := thSecs % 60
	hundredths := (milliseconds % 1000) / 10
	return fmt.Sprintf("%02d:%02d.%02d", minutes, seconds, hundredths)
}

func FormatSRT(milliseconds int64) string {
	hours := milliseconds / 3600000
	minutes := (milliseconds % 3600000) / 60000
	seconds := (milliseconds % 60000) / 1000
	ms := milliseconds % 1000
	return fmt.Sprintf("%02d:%02d:%02d,%03d", hours, minutes, seconds, ms)
}

func LinesToLRC(lines []Line) ([]LRCLine, error) {
	out := make([]LRCLine, 0, len(lines))
	for _, ln := range lines {
		ms, err := msStringToInt64(ln.StartTimeMs)
		if err != nil {
			return nil, err
		}
		out = append(out, LRCLine{
			TimeTag: FormatMS(ms),
			Words:   ln.Words,
		})
	}
	return out, nil
}

func LinesToSRT(lines []Line) ([]SRTLine, error) {
	if len(lines) < 2 {
		return []SRTLine{}, nil
	}
	out := make([]SRTLine, 0, len(lines)-1)
	for i := 1; i < len(lines); i++ {
		startMs, err := msStringToInt64(lines[i-1].StartTimeMs)
		if err != nil {
			return nil, err
		}
		endMs, err := msStringToInt64(lines[i].StartTimeMs)
		if err != nil {
			return nil, err
		}
		out = append(out, SRTLine{
			Index:     i,
			StartTime: FormatSRT(startMs),
			EndTime:   FormatSRT(endMs),
			Words:     lines[i-1].Words,
		})
	}
	return out, nil
}

func LinesToRaw(lines []Line) string {
	var b strings.Builder
	for _, ln := range lines {
		b.WriteString(ln.Words)
		b.WriteByte('\n')
	}
	return b.String()
}
