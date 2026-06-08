package testprovider

import (
	"strings"
	"testing"

	"qs-go/internal/ai/shared"
)

func TestProviderIgnoresPromptAndStreamsLatexAndCode(t *testing.T) {
	provider := Provider{}
	var chunks []string

	result, err := provider.Stream(t.Context(), shared.StreamRequest{
		ModelID:    "test/test",
		RawModelID: "test",
		Message:    "do something completely unrelated",
	}, func(token string) {
		chunks = append(chunks, token)
	})

	if err != nil {
		t.Fatalf("Stream returned error: %v", err)
	}
	got := strings.Join(chunks, "")
	if len(got) < 1200 {
		t.Fatalf("response was too short: got %d bytes", len(got))
	}
	if !strings.Contains(got, "$x^2$") {
		t.Fatalf("response did not contain latex, got %q", got)
	}
	if strings.Count(got, "$") < 12 {
		t.Fatalf("response did not contain enough inline latex markers, got %q", got)
	}
	if strings.Count(got, "\\[") < 3 || strings.Count(got, "\\]") < 3 {
		t.Fatalf("response did not contain enough display latex blocks, got %q", got)
	}
	if !strings.Contains(got, "```") || !strings.Contains(got, "console.log") {
		t.Fatalf("response did not contain a code fence, got %q", got)
	}
	if result.OutputTokens == 0 {
		t.Fatalf("expected output token estimate to be populated")
	}
}
