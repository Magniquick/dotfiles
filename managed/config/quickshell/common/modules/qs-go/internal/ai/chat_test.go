package ai

import (
	"context"
	"testing"
	"time"

	"qs-go/internal/ai/shared"
)

type captureProvider struct {
	req shared.StreamRequest
}

func (p *captureProvider) Metadata() shared.ProviderMetadata {
	return shared.ProviderMetadata{ID: "capture", Label: "Capture"}
}

func (p *captureProvider) Stream(_ context.Context, req shared.StreamRequest, _ func(string)) (shared.StreamResult, error) {
	p.req = req
	return shared.StreamResult{}, nil
}

type toolCallProvider struct{}

func (p toolCallProvider) Metadata() shared.ProviderMetadata {
	return shared.ProviderMetadata{ID: "toolcall", Label: "Tool Call"}
}

func (p toolCallProvider) Stream(_ context.Context, req shared.StreamRequest, _ func(string)) (shared.StreamResult, error) {
	if len(req.History) > 0 {
		return shared.StreamResult{}, nil
	}
	return shared.StreamResult{
		ToolCalls: []shared.ToolCall{{
			ID:        "call_missing",
			Name:      "missing_tool",
			Arguments: map[string]any{"q": "x"},
		}},
	}, nil
}

func TestStreamWithToolsUsesBuiltinsForLocalEvenWithoutCatalogCaps(t *testing.T) {
	prov := &captureProvider{}
	_, err := streamWithTools(context.Background(), prov, shared.StreamRequest{
		ModelID:    "local/gpt-5.4-mini",
		RawModelID: "gpt-5.4-mini",
		Provider:   "local",
		Message:    "list files",
	}, `[]`, func(string) {}, nil, nil, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	found := false
	for _, tool := range prov.req.Tools {
		if tool.Name == "shell_command" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected builtin tools for local provider, got %#v", prov.req.Tools)
	}
}

func TestStreamWithToolsEmitsToolLifecycleEvents(t *testing.T) {
	events := []toolUIEvent{}
	_, err := streamWithTools(context.Background(), toolCallProvider{}, shared.StreamRequest{
		ModelID:    "local/gpt-5.4-mini",
		RawModelID: "gpt-5.4-mini",
		Provider:   "local",
		Message:    "call tool",
	}, `[]`, func(string) {}, func(event toolUIEvent) {
		events = append(events, event)
	}, nil, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(events) != 2 {
		t.Fatalf("expected start and error events, got %#v", events)
	}
	if events[0].Phase != "tool_start" || events[0].Status != "running" || events[0].ToolCallID != "call_missing" {
		t.Fatalf("unexpected start event: %#v", events[0])
	}
	if events[1].Phase != "tool_error" || events[1].Status != "error" || !events[1].IsError {
		t.Fatalf("unexpected done event: %#v", events[1])
	}
}

func TestStreamMetricsTTFTExcludesToolWallTime(t *testing.T) {
	now := time.Unix(0, 0)
	tracker := newStreamMetricTracker(func() time.Time {
		return now
	})

	tracker.beginProviderRound()
	now = now.Add(120 * time.Millisecond)

	// Time spent between provider rounds is tool execution, not model TTFT.
	now = now.Add(5 * time.Second)
	tracker.beginProviderRound()
	now = now.Add(95 * time.Millisecond)
	tracker.observeToken("hello")

	if tracker.chunkCount != 1 {
		t.Fatalf("expected one streamed text chunk, got %d", tracker.chunkCount)
	}
	if tracker.ttfMS != 95 {
		t.Fatalf("expected TTFT from second provider round, got %.0fms", tracker.ttfMS)
	}
}
