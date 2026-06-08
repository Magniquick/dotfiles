package lyricsprovider

import (
	"cmp"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

var lrcTagRe = regexp.MustCompile(`\[(\d{1,2}:\d{2}(?:\.\d{1,3})?)\]`)

// ParseSyncedLRC parses timestamped LRC text into normalized lyric lines.
func ParseSyncedLRC(text string) []Line {
	text = strings.TrimSpace(text)
	if text == "" {
		return nil
	}

	out := make([]Line, 0, 64)
	for row := range strings.SplitSeq(text, "\n") {
		row = strings.TrimSpace(row)
		if row == "" {
			continue
		}

		tags := lrcTagRe.FindAllStringSubmatch(row, -1)
		if len(tags) == 0 {
			continue
		}
		words := strings.TrimSpace(lrcTagRe.ReplaceAllString(row, ""))
		if words == "" {
			words = "♪"
		}

		for _, tag := range tags {
			if len(tag) < 2 {
				continue
			}
			ms := ParseLRCTimeToMs(tag[1])
			if ms < 0 {
				continue
			}
			out = append(out, Line{
				StartTimeMs: strconv.Itoa(ms),
				Words:       words,
			})
		}
	}

	slices.SortFunc(out, func(a, b Line) int {
		ai, _ := strconv.Atoi(a.StartTimeMs)
		bi, _ := strconv.Atoi(b.StartTimeMs)
		return cmp.Compare(ai, bi)
	})

	return out
}

// ParsePlainText converts plain lyric text into unsynchronized lyric lines.
func ParsePlainText(text string) []Line {
	text = strings.TrimSpace(text)
	if text == "" {
		return nil
	}

	rows := strings.Split(text, "\n")
	out := make([]Line, 0, len(rows))
	for _, row := range rows {
		row = strings.TrimSpace(row)
		if row == "" {
			continue
		}
		out = append(out, Line{Words: row})
	}
	return out
}

// ParseLRCTimeToMs converts an LRC timestamp tag into milliseconds.
func ParseLRCTimeToMs(tag string) int {
	parts := strings.Split(tag, ":")
	if len(parts) != 2 {
		return -1
	}
	minutes, err := strconv.Atoi(parts[0])
	if err != nil || minutes < 0 {
		return -1
	}

	secFrac := parts[1]
	secParts := strings.SplitN(secFrac, ".", 2)
	sec, err := strconv.Atoi(secParts[0])
	if err != nil || sec < 0 || sec >= 60 {
		return -1
	}

	ms := 0
	if len(secParts) == 2 {
		f := secParts[1]
		if len(f) > 3 {
			f = f[:3]
		}
		for len(f) < 3 {
			f += "0"
		}
		if v, err := strconv.Atoi(f); err == nil {
			ms = v
		}
	}
	return (minutes*60+sec)*1000 + ms
}
