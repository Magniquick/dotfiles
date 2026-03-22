package openai

import (
	"encoding/base64"
	"strings"
	"testing"

	"qs-go/internal/ai/shared"
)

func TestBuildContentPartsImageAttachment(t *testing.T) {
	img := []byte{0x89, 0x50, 0x4e, 0x47}
	attachments := []shared.Attachment{
		{
			MIME: "image/png",
			B64:  base64.StdEncoding.EncodeToString(img),
		},
	}
	parts, err := buildContentParts("hello", attachments)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(parts) != 2 {
		t.Fatalf("expected 2 parts, got %d", len(parts))
	}
	if parts[0]["type"] != "image_url" {
		t.Fatalf("expected first part image_url, got %#v", parts[0]["type"])
	}
	if parts[1]["type"] != "text" {
		t.Fatalf("expected second part text, got %#v", parts[1]["type"])
	}
}

func TestBuildContentPartsRejectNonImage(t *testing.T) {
	txt := []byte("hello")
	attachments := []shared.Attachment{
		{
			MIME: "text/plain",
			B64:  base64.StdEncoding.EncodeToString(txt),
		},
	}
	_, err := buildContentParts("hi", attachments)
	if err == nil {
		t.Fatal("expected error for non-image attachment")
	}
	if !strings.Contains(err.Error(), "image attachments only") {
		t.Fatalf("unexpected error: %v", err)
	}
}
