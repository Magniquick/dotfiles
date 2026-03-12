package lyricsprovider

import (
	"regexp"
	"sort"
	"strconv"
	"strings"
)

var lrcTagRe = regexp.MustCompile(`\[(\d{1,2}:\d{2}(?:\.\d{1,3})?)\]`)

func ParseSyncedLRC(text string) []Line {
	text = strings.TrimSpace(text)
	if text == "" {
		return nil
	}

	out := make([]Line, 0, 64)
	rows := strings.Split(text, "\n")
	for _, row := range rows {
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

	sort.Slice(out, func(i, j int) bool {
		li, _ := strconv.Atoi(out[i].StartTimeMs)
		lj, _ := strconv.Atoi(out[j].StartTimeMs)
		return li < lj
	})

	return out
}

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

func ParseLRCTimeToMs(tag string) int {
	parts := strings.Split(tag, ":")
	if len(parts) != 2 {
		return -1
	}
	min, err := strconv.Atoi(parts[0])
	if err != nil || min < 0 {
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
	return (min*60+sec)*1000 + ms
}
