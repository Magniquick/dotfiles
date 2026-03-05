package ai

import (
	"encoding/base64"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

type binaryAttachment struct {
	MIME string
	Data []byte
}

func decodeAttachmentBinary(a Attachment) (binaryAttachment, bool) {
	mimeType := strings.TrimSpace(a.MIME)
	if b64 := strings.TrimSpace(a.B64); b64 != "" {
		raw, err := base64.StdEncoding.DecodeString(b64)
		if err != nil || len(raw) == 0 {
			return binaryAttachment{}, false
		}
		if mimeType == "" {
			mimeType = sniffMIME(raw, "application/octet-stream")
		}
		return binaryAttachment{MIME: mimeType, Data: raw}, true
	}

	path := strings.TrimSpace(a.Path)
	if path == "" {
		return binaryAttachment{}, false
	}
	raw, err := os.ReadFile(path)
	if err != nil || len(raw) == 0 {
		return binaryAttachment{}, false
	}

	if mimeType == "" {
		if ext := strings.ToLower(filepath.Ext(path)); ext != "" {
			mimeType = mime.TypeByExtension(ext)
		}
		if mimeType == "" {
			mimeType = sniffMIME(raw, "application/octet-stream")
		}
	}
	return binaryAttachment{MIME: mimeType, Data: raw}, true
}

func sniffMIME(data []byte, fallback string) string {
	detected := http.DetectContentType(data)
	if detected == "application/octet-stream" && fallback != "" {
		return fallback
	}
	return detected
}
