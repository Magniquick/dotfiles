package ical

import (
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"

	"qs-go/internal/secrets"
)

func TestRefreshUsesSecretResolverCalendarURL(t *testing.T) {
	var hits int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		atomic.AddInt32(&hits, 1)
		_, _ = w.Write([]byte("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n"))
	}))
	defer server.Close()

	cleanup := secrets.UseResolverForTest(secrets.NewMapResolver(map[string]string{
		"CALENDAR_ICAL_URL": server.URL,
	}))
	defer cleanup()
	resetTestState(t)

	_ = Refresh(1)

	if atomic.LoadInt32(&hits) != 1 {
		t.Fatalf("expected secret calendar URL to be fetched, got %d hits", hits)
	}
}

func resetTestState(t *testing.T) {
	t.Helper()
	globalState.mu.Lock()
	defer globalState.mu.Unlock()
	globalState.metaByURL = make(map[string]CacheMeta)
	globalState.icsByURL = make(map[string]string)
}
