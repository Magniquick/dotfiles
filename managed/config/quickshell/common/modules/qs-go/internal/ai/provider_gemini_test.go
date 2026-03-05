package ai

import (
	"encoding/base64"
	"testing"
)

func TestBuildGeminiPayloadEncodesAttachment(t *testing.T) {
	png := []byte{0x89, 0x50, 0x4e, 0x47}
	payload, err := buildGeminiPayload(
		"system",
		nil,
		"hello",
		[]Attachment{
			{MIME: "image/png", B64: base64.StdEncoding.EncodeToString(png)},
		},
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	contents, ok := payload["contents"].([]map[string]any)
	if !ok || len(contents) != 1 {
		t.Fatalf("unexpected contents: %#v", payload["contents"])
	}

	parts, ok := contents[0]["parts"].([]map[string]any)
	if !ok || len(parts) < 2 {
		t.Fatalf("unexpected parts: %#v", contents[0]["parts"])
	}
	if _, ok := parts[0]["inlineData"]; !ok {
		t.Fatalf("expected first part inlineData, got %#v", parts[0])
	}
}
