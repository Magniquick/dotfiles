package ical

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"golang.org/x/oauth2"
	calendarapi "google.golang.org/api/calendar/v3"
	"google.golang.org/api/option"

	"qs-go/internal/appconfig"
	"qs-go/internal/googleauth"
	"qs-go/internal/secrets"
)

func TestRefreshUsesConfiguredGoogleCalendarSources(t *testing.T) {
	tokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			t.Fatal(err)
		}
		if r.Form.Get("refresh_token") != "refresh-token" {
			t.Fatalf("refresh_token = %q", r.Form.Get("refresh_token"))
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"access_token":"fresh-access","expires_in":3600,"token_type":"Bearer"}`))
	}))
	defer tokenServer.Close()
	restoreEndpoint := useGoogleOAuthEndpointForTest(t, tokenServer.URL)
	defer restoreEndpoint()

	calendarServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer fresh-access" {
			t.Fatalf("Authorization = %q", r.Header.Get("Authorization"))
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
			"items": [
				{
					"id": "event-1",
					"iCalUID": "event-1@example",
					"summary": "Exam",
					"status": "confirmed",
					"start": {"date": "2026-06-10"},
					"end": {"date": "2026-06-11"}
				}
			]
		}`))
	}))
	defer calendarServer.Close()
	restoreCalendarBase := useCalendarBaseForTest(t, calendarServer.URL+"/")
	defer restoreCalendarBase()

	cleanupConfig := appconfig.UseConfigForTest(appconfig.Config{
		Model: appconfig.ModelConfig{Default: "local/gpt-5.4-mini"},
		Email: appconfig.EmailConfig{Accounts: []appconfig.EmailAccountConfig{{
			ID:       "iit",
			Provider: "gmail",
			Address:  "24f2003934@ds.study.iitm.ac.in",
		}}},
		Calendar: appconfig.CalendarConfig{Accounts: []appconfig.CalendarAccountConfig{{
			Account:     "iit",
			CalendarIDs: []string{"primary"},
		}}},
	})
	defer cleanupConfig()
	store := secrets.NewMapStore(map[string]string{
		"GOOGLE_IIT_TOKEN_JSON": mustTokenJSON(t, oauth2.Token{
			AccessToken:  "expired-access",
			RefreshToken: "refresh-token",
			TokenType:    "Bearer",
			Expiry:       time.Now().Add(-time.Hour),
		}),
		"GOOGLE_IIT_CLIENT_ID":     "client-id",
		"GOOGLE_IIT_CLIENT_SECRET": "client-secret",
	})
	cleanupSecrets := secrets.UseResolverForTest(store)
	defer cleanupSecrets()

	var out Output
	if err := json.Unmarshal([]byte(Refresh(30)), &out); err != nil {
		t.Fatalf("invalid output json: %v", err)
	}
	if out.Status != "fetched" {
		t.Fatalf("status = %q, error=%q", out.Status, out.Error)
	}
	if len(out.EventsByDay["2026-06-10"]) != 1 {
		t.Fatalf("expected event on 2026-06-10, got %#v", out.EventsByDay)
	}
	if out.EventsByDay["2026-06-10"][0].Title != "Exam" {
		t.Fatalf("unexpected event: %#v", out.EventsByDay["2026-06-10"][0])
	}
}

func TestRefreshErrorsWithoutConfiguredSources(t *testing.T) {
	cleanupConfig := appconfig.UseConfigForTest(appconfig.Config{})
	defer cleanupConfig()

	var out Output
	if err := json.Unmarshal([]byte(Refresh(30)), &out); err != nil {
		t.Fatalf("invalid output json: %v", err)
	}
	if out.Status != "error" || out.Error == "" {
		t.Fatalf("expected config error, got %#v", out)
	}
}

func TestEventFromAPISkipsWorkingLocation(t *testing.T) {
	_, ok := eventFromAPI(&calendarapi.Event{
		EventType: "workingLocation",
		Summary:   "Home",
		Start:     &calendarapi.EventDateTime{Date: "2026-06-08"},
		End:       &calendarapi.EventDateTime{Date: "2026-06-09"},
	})
	if ok {
		t.Fatalf("working location event should be skipped")
	}
}

func useGoogleOAuthEndpointForTest(t *testing.T, tokenURL string) func() {
	t.Helper()
	previous := googleauth.Endpoint
	googleauth.Endpoint = oauth2.Endpoint{
		AuthURL:  previous.AuthURL,
		TokenURL: tokenURL,
	}
	return func() {
		googleauth.Endpoint = previous
	}
}

func useCalendarBaseForTest(t *testing.T, url string) func() {
	t.Helper()
	previous := calendarServiceOptions
	calendarServiceOptions = []option.ClientOption{option.WithEndpoint(url)}
	return func() {
		calendarServiceOptions = previous
	}
}

func mustTokenJSON(t *testing.T, token oauth2.Token) string {
	t.Helper()
	raw, err := json.Marshal(token)
	if err != nil {
		t.Fatalf("marshal token: %v", err)
	}
	return string(raw)
}
