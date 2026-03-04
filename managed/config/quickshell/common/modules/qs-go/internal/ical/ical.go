// Package ical fetches and parses iCalendar feeds with ETag-based caching.
package ical

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	ics "github.com/arran4/golang-ical"
	"github.com/joho/godotenv"
)

// CacheMeta stores HTTP caching headers per URL.
type CacheMeta struct {
	ETag         string `json:"etag"`
	LastModified string `json:"last_modified"`
}

// EventOut is a single calendar event in the output.
type EventOut struct {
	UID    string `json:"uid"`
	Title  string `json:"title"`
	Start  string `json:"start"`
	End    string `json:"end"`
	AllDay bool   `json:"all_day"`
}

// Output is the JSON payload returned by Refresh.
type Output struct {
	GeneratedAt  string                       `json:"generatedAt"`
	Status       string                       `json:"status"`
	Error        string                       `json:"error,omitempty"`
	EventsByDay  map[string][]EventOut        `json:"eventsByDay"`
}

// State persists between calls to avoid re-fetching unchanged calendars.
type State struct {
	mu       sync.Mutex
	metaByURL map[string]CacheMeta
	icsByURL  map[string]string
}

var globalState = &State{
	metaByURL: make(map[string]CacheMeta),
	icsByURL:  make(map[string]string),
}

// Refresh fetches/re-fetches calendars from CALENDAR_ICAL_URL env var and returns JSON.
func Refresh(envFile string, days int) string {
	globalState.mu.Lock()
	defer globalState.mu.Unlock()

	if envFile != "" {
		_ = godotenv.Overload(envFile)
	}

	urls := resolveURLs()
	if len(urls) == 0 {
		b, _ := json.Marshal(Output{
			GeneratedAt: time.Now().Format(time.RFC3339),
			Status:      "error",
			Error:       "Missing CALENDAR_ICAL_URL in .env",
			EventsByDay: map[string][]EventOut{},
		})
		return string(b)
	}

	client := &http.Client{Timeout: 20 * time.Second}
	var allEvents []parsedEvent
	var errs []string
	successCount := 0

	for _, url := range urls {
		status, fetchErr := fetchCalendar(client, url)
		if fetchErr != nil {
			errs = append(errs, fmt.Sprintf("fatal error fetching %s: %v", url, fetchErr))
			continue
		}
		if strings.HasPrefix(status, "error") {
			errs = append(errs, fmt.Sprintf("error fetching %s: %s", url, status))
		} else {
			successCount++
		}
		if body, ok := globalState.icsByURL[url]; ok {
			events, parseErr := parseCalendar(body)
			if parseErr != nil {
				errs = append(errs, fmt.Sprintf("error parsing %s: %v", url, parseErr))
			} else {
				allEvents = append(allEvents, events...)
			}
		}
	}

	aggStatus := "fetched"
	if successCount == 0 && len(errs) > 0 {
		aggStatus = "error"
	} else if successCount > 0 && len(errs) > 0 {
		aggStatus = "partial_success"
	}

	eventsByDay := organizeEvents(allEvents, days)

	out := Output{
		GeneratedAt: time.Now().Format(time.RFC3339),
		Status:      aggStatus,
		EventsByDay: eventsByDay,
	}
	if len(errs) > 0 {
		out.Error = strings.Join(errs, "; ")
	}

	b, _ := json.Marshal(out)
	return string(b)
}

func resolveURLs() []string {
	env := os.Getenv("CALENDAR_ICAL_URL")
	var urls []string
	for _, u := range strings.Split(env, ",") {
		if t := strings.TrimSpace(u); t != "" {
			urls = append(urls, t)
		}
	}
	return urls
}

// fetchCalendar downloads a calendar URL respecting ETag/Last-Modified.
// Returns status string and optional fatal error.
func fetchCalendar(client *http.Client, url string) (string, error) {
	meta := globalState.metaByURL[url]
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return "", err
	}
	if meta.ETag != "" {
		req.Header.Set("If-None-Match", meta.ETag)
	}
	if meta.LastModified != "" {
		req.Header.Set("If-Modified-Since", meta.LastModified)
	}

	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotModified {
		return "not_modified", nil
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		errMsg := fmt.Sprintf("HTTP %d", resp.StatusCode)
		if _, cached := globalState.icsByURL[url]; cached {
			return "error_cached: " + errMsg, nil
		}
		return "", fmt.Errorf("%s", errMsg)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	text := string(body)

	if !strings.Contains(text, "BEGIN:VCALENDAR") {
		msg := "invalid ICS response"
		if _, cached := globalState.icsByURL[url]; cached {
			return "error_cached: " + msg, nil
		}
		return "", fmt.Errorf("%s", msg)
	}

	text = strings.ReplaceAll(text, "\r\n", "\n")

	newMeta := CacheMeta{
		ETag:         resp.Header.Get("ETag"),
		LastModified: resp.Header.Get("Last-Modified"),
	}
	globalState.metaByURL[url] = newMeta
	globalState.icsByURL[url] = text
	return "fetched", nil
}

type parsedEvent struct {
	event          EventOut
	startDate      time.Time
	endDateExclusive time.Time
}

func parseCalendar(body string) ([]parsedEvent, error) {
	cal, err := ics.ParseCalendar(strings.NewReader(body))
	if err != nil {
		return nil, err
	}
	var events []parsedEvent
	for _, comp := range cal.Components {
		event, ok := comp.(*ics.VEvent)
		if !ok {
			continue
		}
		pe, err := parseEvent(event)
		if err != nil || pe == nil {
			continue
		}
		events = append(events, *pe)
	}
	return events, nil
}

func parseEvent(event *ics.VEvent) (*parsedEvent, error) {
	uid := ""
	if p := event.GetProperty(ics.ComponentPropertyUniqueId); p != nil {
		uid = p.Value
	}
	title := "Untitled"
	if p := event.GetProperty(ics.ComponentPropertySummary); p != nil && p.Value != "" {
		title = unescapeIcal(p.Value)
	}

	startDt, startAllDay, err := getEventTime(event, ics.ComponentPropertyDtStart)
	if err != nil {
		return nil, err
	}
	endDt, endAllDay, err := getEventTime(event, ics.ComponentPropertyDtEnd)
	if err != nil || endDt.IsZero() {
		if startAllDay {
			endDt = startDt.AddDate(0, 0, 1)
		} else {
			endDt = startDt.AddDate(0, 0, 1)
		}
		endAllDay = startAllDay
	}

	allDay := startAllDay || endAllDay

	if uid == "" {
		uid = fmt.Sprintf("%s-%d", title, startDt.Unix())
	}

	var endExclusive time.Time
	if allDay {
		endExclusive = endDt
	} else {
		if endDt.Hour() == 0 && endDt.Minute() == 0 && endDt.Second() == 0 && endDt.After(startDt) {
			endExclusive = endDt
		} else {
			endExclusive = endDt.AddDate(0, 0, 1)
			endExclusive = time.Date(endDt.Year(), endDt.Month(), endDt.Day()+1, 0, 0, 0, 0, endDt.Location())
		}
	}

	out := EventOut{
		UID:    uid,
		Title:  title,
		Start:  startDt.Format(time.RFC3339),
		End:    endDt.Format(time.RFC3339),
		AllDay: allDay,
	}
	return &parsedEvent{
		event:            out,
		startDate:        startDt,
		endDateExclusive: endExclusive,
	}, nil
}

func getEventTime(event *ics.VEvent, prop ics.ComponentProperty) (t time.Time, allDay bool, err error) {
	p := event.GetProperty(prop)
	if p == nil {
		return time.Time{}, false, nil
	}
	val := strings.TrimSpace(p.Value)
	if val == "" {
		return time.Time{}, false, nil
	}

	// Check VALUE=DATE parameter
	valueType := ""
	if params := p.ICalParameters; params != nil {
		if vt, ok := params["VALUE"]; ok && len(vt) > 0 {
			valueType = strings.ToUpper(vt[0])
		}
	}

	if valueType == "DATE" || (len(val) == 8 && !strings.Contains(val, "T")) {
		parsed, e := time.ParseInLocation("20060102", val, time.Local)
		if e != nil {
			return time.Time{}, false, e
		}
		return parsed, true, nil
	}

	// UTC suffix
	if strings.HasSuffix(val, "Z") {
		parsed, e := time.Parse("20060102T150405Z", val)
		if e != nil {
			return time.Time{}, false, e
		}
		return parsed.In(time.Local), false, nil
	}

	// TZID parameter
	tzid := ""
	if params := p.ICalParameters; params != nil {
		if tz, ok := params["TZID"]; ok && len(tz) > 0 {
			tzid = tz[0]
		}
	}

	loc := time.Local
	if tzid != "" {
		if l, e := time.LoadLocation(tzid); e == nil {
			loc = l
		}
	}

	parsed, e := time.ParseInLocation("20060102T150405", val, loc)
	if e != nil {
		return time.Time{}, false, e
	}
	return parsed, false, nil
}

func organizeEvents(events []parsedEvent, days int) map[string][]EventOut {
	now := time.Now()
	rangeStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.Local)
	rangeEnd := rangeStart.AddDate(0, 0, days)

	result := make(map[string][]EventOut)
	for _, pe := range events {
		d := time.Date(pe.startDate.Year(), pe.startDate.Month(), pe.startDate.Day(), 0, 0, 0, 0, time.Local)
		endD := time.Date(pe.endDateExclusive.Year(), pe.endDateExclusive.Month(), pe.endDateExclusive.Day(), 0, 0, 0, 0, time.Local)
		for !d.Before(rangeStart) || !d.After(rangeEnd) {
			if d.Before(rangeStart) {
				d = d.AddDate(0, 0, 1)
				continue
			}
			if d.After(rangeEnd) {
				break
			}
			key := d.Format("2006-01-02")
			result[key] = append(result[key], pe.event)
			d = d.AddDate(0, 0, 1)
			if !d.Before(endD) {
				break
			}
		}
	}

	// Sort events within each day
	for k := range result {
		day := result[k]
		sort.Slice(day, func(i, j int) bool {
			ti, _ := time.Parse(time.RFC3339, day[i].Start)
			tj, _ := time.Parse(time.RFC3339, day[j].Start)
			return ti.Before(tj)
		})
		result[k] = day
	}
	return result
}

func unescapeIcal(s string) string {
	s = strings.ReplaceAll(s, "\\\\", "\\")
	s = strings.ReplaceAll(s, "\\n", "\n")
	s = strings.ReplaceAll(s, "\\,", ",")
	s = strings.ReplaceAll(s, "\\;", ";")
	return s
}
