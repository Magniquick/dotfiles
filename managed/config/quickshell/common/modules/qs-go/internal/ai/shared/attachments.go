// Package shared defines common provider request, response, and tool payload types.
package shared

import (
	"encoding/base64"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// BinaryAttachment contains decoded attachment bytes and their MIME type.
type BinaryAttachment struct {
	MIME string
	Data []byte
}

// DecodeAttachmentBinary resolves a base64 or local-path attachment into bytes.
func DecodeAttachmentBinary(a Attachment) (BinaryAttachment, bool) {
	mimeType := strings.TrimSpace(a.MIME)
	if b64 := strings.TrimSpace(a.B64); b64 != "" {
		raw, err := base64.StdEncoding.DecodeString(b64)
		if err != nil || len(raw) == 0 {
			return BinaryAttachment{}, false
		}
		if mimeType == "" {
			mimeType = SniffMIME(raw, "application/octet-stream")
		}
		return BinaryAttachment{MIME: mimeType, Data: raw}, true
	}

	path := strings.TrimSpace(a.Path)
	if path == "" {
		return BinaryAttachment{}, false
	}
	//nolint:gosec // attachment paths come from the local UI/user request and are read-only.
	raw, err := os.ReadFile(path)
	if err != nil || len(raw) == 0 {
		return BinaryAttachment{}, false
	}

	if mimeType == "" {
		if ext := strings.ToLower(filepath.Ext(path)); ext != "" {
			mimeType = mime.TypeByExtension(ext)
		}
		if mimeType == "" {
			mimeType = SniffMIME(raw, "application/octet-stream")
		}
	}
	return BinaryAttachment{MIME: mimeType, Data: raw}, true
}

// SniffMIME detects content type, preserving a fallback for generic binary data.
func SniffMIME(data []byte, fallback string) string {
	detected := http.DetectContentType(data)
	if detected == "application/octet-stream" && fallback != "" {
		return fallback
	}
	return detected
}
