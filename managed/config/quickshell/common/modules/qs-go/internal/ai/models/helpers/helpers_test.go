package helpers

import "testing"

func TestStaticCapabilities(t *testing.T) {
	caps, ok := Query("local/gpt-5.4-mini")
	if !ok {
		t.Fatal("expected local/gpt-5.4-mini metadata")
	}
	if !caps.SupportsImages || !caps.SupportsTools || !caps.SupportsMultimodal {
		t.Fatalf("unexpected local capabilities: %#v", caps)
	}
	if _, ok := Query("openai/text-embedding-3-large"); ok {
		t.Fatal("embedding model should not be included")
	}
}
