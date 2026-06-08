// Package ical returns calendar events for the QML calendar surface.
package ical

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strings"
	"time"

	calendarapi "google.golang.org/api/calendar/v3"
	"google.golang.org/api/option"

	"qs-go/internal/appconfig"
	"qs-go/internal/googleauth"
	"qs-go/internal/secrets"
)

var calendarServiceOptions []option.ClientOption

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
	GeneratedAt string                `json:"generatedAt"`
	Status      string                `json:"status"`
	Error       string                `json:"error,omitempty"`
	EventsByDay map[string][]EventOut `json:"eventsByDay"`
}

type parsedEvent struct {
	event            EventOut
	startDate        time.Time
	endDateExclusive time.Time
}

// Refresh fetches configured Google Calendar API sources and returns the QML payload JSON.
func Refresh(days int) string {
	if days <= 0 {
		days = 180
	}
	cfg, err := appconfig.Current()
	if err != nil {
		return outputError(fmt.Sprintf("load config: %v", err))
	}
	sources := calendarSources(cfg)
	if len(sources) == 0 {
		return outputError("Missing calendar.accounts entries with calendar_ids in leftpanel/config.toml")
	}

	resolver := secrets.NewResolver()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	rangeStart, rangeEnd := eventRange(days)
	var allEvents []parsedEvent
	var errs []string
	successCount := 0
	for _, source := range sources {
		account, ok := emailAccountByID(cfg, source.Account)
		if !ok {
			errs = append(errs, fmt.Sprintf("calendar account %s is not configured as an email account", source.Account))
			continue
		}
		httpClient, err := googleauth.NewHTTPClient(ctx, googleauth.AccountFromResolver(source.Account, account.Address, resolver), []string{
			calendarapi.CalendarCalendarlistReadonlyScope,
			calendarapi.CalendarEventsReadonlyScope,
		})
		if err != nil {
			errs = append(errs, fmt.Sprintf("%s: %v", source.Account, err))
			continue
		}
		options := append([]option.ClientOption{option.WithHTTPClient(httpClient)}, calendarServiceOptions...)
		service, err := calendarapi.NewService(ctx, options...)
		if err != nil {
			errs = append(errs, fmt.Sprintf("%s: %v", source.Account, err))
			continue
		}
		accountSuccess := false
		for _, calendarID := range source.CalendarIDs {
			events, err := fetchCalendarEvents(ctx, service, calendarID, rangeStart, rangeEnd)
			if err != nil {
				errs = append(errs, fmt.Sprintf("%s/%s: %v", source.Account, calendarID, err))
				continue
			}
			accountSuccess = true
			allEvents = append(allEvents, events...)
		}
		if accountSuccess {
			successCount++
		}
	}

	status := "fetched"
	if successCount == 0 && len(errs) > 0 {
		status = "error"
	} else if successCount > 0 && len(errs) > 0 {
		status = "partial_success"
	}
	out := Output{
		GeneratedAt: time.Now().Format(time.RFC3339),
		Status:      status,
		EventsByDay: organizeEvents(allEvents, days),
	}
	if len(errs) > 0 {
		out.Error = strings.Join(errs, "; ")
	}
	return marshalOutput(out)
}

func calendarSources(cfg appconfig.Config) []appconfig.CalendarAccountConfig {
	var out []appconfig.CalendarAccountConfig
	for _, source := range cfg.Calendar.Accounts {
		if strings.TrimSpace(source.Account) == "" || len(source.CalendarIDs) == 0 {
			continue
		}
		out = append(out, source)
	}
	return out
}

func emailAccountByID(cfg appconfig.Config, id string) (appconfig.EmailAccountConfig, bool) {
	for _, account := range cfg.Email.Accounts {
		if strings.EqualFold(strings.TrimSpace(account.ID), strings.TrimSpace(id)) {
			return account, true
		}
	}
	return appconfig.EmailAccountConfig{}, false
}

func fetchCalendarEvents(ctx context.Context, service *calendarapi.Service, calendarID string, rangeStart, rangeEnd time.Time) ([]parsedEvent, error) {
	var events []parsedEvent
	pageToken := ""
	for {
		call := service.Events.List(calendarID).
			Context(ctx).
			SingleEvents(true).
			OrderBy("startTime").
			TimeMin(rangeStart.Format(time.RFC3339)).
			TimeMax(rangeEnd.Format(time.RFC3339)).
			MaxResults(2500)
		if pageToken != "" {
			call = call.PageToken(pageToken)
		}
		response, err := call.Do()
		if err != nil {
			return events, err
		}
		for _, item := range response.Items {
			event, ok := eventFromAPI(item)
			if ok {
				events = append(events, event)
			}
		}
		pageToken = response.NextPageToken
		if pageToken == "" {
			break
		}
	}
	return events, nil
}

func eventFromAPI(item *calendarapi.Event) (parsedEvent, bool) {
	if item == nil || strings.EqualFold(item.Status, "cancelled") {
		return parsedEvent{}, false
	}
	if strings.EqualFold(item.EventType, "workingLocation") {
		return parsedEvent{}, false
	}
	start, startAllDay, ok := eventDateTime(item.Start)
	if !ok {
		return parsedEvent{}, false
	}
	end, endAllDay, ok := eventDateTime(item.End)
	if !ok || !end.After(start) {
		if startAllDay {
			end = start.AddDate(0, 0, 1)
		} else {
			end = start.Add(time.Hour)
		}
	}
	allDay := startAllDay || endAllDay
	endExclusive := end
	if !allDay {
		endExclusive = time.Date(end.Year(), end.Month(), end.Day()+1, 0, 0, 0, 0, end.Location())
	}
	title := strings.TrimSpace(item.Summary)
	if title == "" {
		title = "Untitled"
	}
	uid := strings.TrimSpace(item.ICalUID)
	if uid == "" {
		uid = strings.TrimSpace(item.Id)
	}
	if uid == "" {
		uid = fmt.Sprintf("%s-%d", title, start.Unix())
	}
	return parsedEvent{
		event: EventOut{
			UID:    uid,
			Title:  title,
			Start:  start.Format(time.RFC3339),
			End:    end.Format(time.RFC3339),
			AllDay: allDay,
		},
		startDate:        start,
		endDateExclusive: endExclusive,
	}, true
}

func eventDateTime(value *calendarapi.EventDateTime) (time.Time, bool, bool) {
	if value == nil {
		return time.Time{}, false, false
	}
	if strings.TrimSpace(value.Date) != "" {
		parsed, err := time.ParseInLocation("2006-01-02", value.Date, time.Local)
		if err != nil {
			return time.Time{}, false, false
		}
		return parsed, true, true
	}
	raw := strings.TrimSpace(value.DateTime)
	if raw == "" {
		return time.Time{}, false, false
	}
	parsed, err := time.Parse(time.RFC3339, raw)
	if err != nil {
		return time.Time{}, false, false
	}
	return parsed.In(time.Local), false, true
}

func eventRange(days int) (time.Time, time.Time) {
	now := time.Now()
	rangeStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.Local)
	return rangeStart, rangeStart.AddDate(0, 0, days)
}

func organizeEvents(events []parsedEvent, days int) map[string][]EventOut {
	rangeStart, rangeEnd := eventRange(days)
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
	for key := range result {
		day := result[key]
		slices.SortFunc(day, func(a, b EventOut) int {
			at, _ := time.Parse(time.RFC3339, a.Start)
			bt, _ := time.Parse(time.RFC3339, b.Start)
			return at.Compare(bt)
		})
		result[key] = day
	}
	return result
}

func outputError(message string) string {
	return marshalOutput(Output{
		GeneratedAt: time.Now().Format(time.RFC3339),
		Status:      "error",
		Error:       message,
		EventsByDay: map[string][]EventOut{},
	})
}

func marshalOutput(out Output) string {
	raw, err := json.Marshal(out)
	if err != nil {
		return "{}"
	}
	return string(raw)
}
