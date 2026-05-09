package todoist

import (
	"testing"
	"time"

	apiSync "github.com/CnTeng/todoist-api-go/sync"
)

func TestTaskDueKeepsFloatingTodoistTime(t *testing.T) {
	originalLocal := time.Local
	t.Cleanup(func() { time.Local = originalLocal })
	t.Setenv("TZ", "Asia/Kolkata")
	time.Local, _ = time.LoadLocation("Asia/Kolkata")

	due := time.Date(2026, 4, 26, 9, 30, 0, 0, time.UTC)
	gotUnix, gotHuman, gotToday := taskDue(&apiSync.Task{
		Due: &apiSync.Due{Date: &due},
	}, "2026-04-26")

	if !gotToday {
		t.Fatalf("expected floating due date to be treated as today")
	}
	if gotUnix == nil {
		t.Fatalf("expected due timestamp")
	}
	if gotHuman == nil {
		t.Fatalf("expected human due label")
	}
	if *gotHuman != "Today 9:30 AM" {
		t.Fatalf("expected floating time to stay at 9:30 AM, got %q", *gotHuman)
	}
}

func TestTaskDueDateOnlyDoesNotRenderLocalOffsetTime(t *testing.T) {
	originalLocal := time.Local
	t.Cleanup(func() { time.Local = originalLocal })
	t.Setenv("TZ", "Asia/Kolkata")
	time.Local, _ = time.LoadLocation("Asia/Kolkata")

	due := time.Date(2026, 4, 26, 0, 0, 0, 0, time.UTC)
	_, gotHuman, gotToday := taskDue(&apiSync.Task{
		Due: &apiSync.Due{Date: &due},
	}, "2026-04-26")

	if !gotToday {
		t.Fatalf("expected date-only due date to be treated as today")
	}
	if gotHuman == nil {
		t.Fatalf("expected human due label")
	}
	if *gotHuman != "Today" {
		t.Fatalf("expected date-only due label to omit shifted time, got %q", *gotHuman)
	}
}
