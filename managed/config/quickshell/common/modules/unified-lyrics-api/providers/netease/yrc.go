package netease

import (
	"regexp"
	"strconv"
	"strings"

	"unified-lyrics-api/internal/lyricsprovider"
)

var (
	yrcLineRe = regexp.MustCompile(`^\[(\d+),(\d+)\](.*)$`)
	yrcWordRe = regexp.MustCompile(`(?:\[\d+,\d+\])?\((\d+),(\d+),\d+\)([^()]*)`)
)

func parseYRC(text string) []lyricsprovider.Line {
	text = strings.TrimSpace(text)
	if text == "" {
		return nil
	}

	out := make([]lyricsprovider.Line, 0, 64)
	for _, raw := range strings.Split(text, "\n") {
		raw = strings.TrimSpace(raw)
		if raw == "" {
			continue
		}
		match := yrcLineRe.FindStringSubmatch(raw)
		if len(match) != 4 {
			continue
		}

		start, errStart := strconv.Atoi(match[1])
		duration, errDuration := strconv.Atoi(match[2])
		if errStart != nil || errDuration != nil || start < 0 || duration < 0 {
			continue
		}

		content := match[3]
		segments := make([]lyricsprovider.Segment, 0, 8)
		lineText := strings.Builder{}
		for _, wordMatch := range yrcWordRe.FindAllStringSubmatch(content, -1) {
			if len(wordMatch) != 4 {
				continue
			}
			wordStart, errWordStart := strconv.Atoi(wordMatch[1])
			wordDuration, errWordDuration := strconv.Atoi(wordMatch[2])
			if errWordStart != nil || errWordDuration != nil || wordDuration < 0 {
				continue
			}
			text := wordMatch[3]
			segments = append(segments, lyricsprovider.Segment{
				StartTimeMs: strconv.Itoa(wordStart),
				EndTimeMs:   strconv.Itoa(wordStart + wordDuration),
				Text:        text,
			})
			lineText.WriteString(text)
		}

		words := strings.TrimSpace(lineText.String())
		if words == "" {
			words = strings.TrimSpace(content)
		}
		if words == "" {
			words = "♪"
		}

		line := lyricsprovider.Line{
			StartTimeMs: strconv.Itoa(start),
			EndTimeMs:   strconv.Itoa(start + duration),
			Words:       words,
		}
		if len(segments) > 0 {
			line.Segments = segments
		}
		out = append(out, line)
	}

	return out
}
