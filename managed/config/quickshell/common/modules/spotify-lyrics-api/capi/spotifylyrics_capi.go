package main

// #include <stdlib.h>
import "C"

import (
	"context"
	"encoding/json"
	"strings"
	"time"
	"unsafe"

	"spotify-lyrics-api/spotifylyrics"
)

type okResponse struct {
	Error    bool        `json:"error"`
	SyncType string      `json:"syncType"`
	Lines    interface{} `json:"lines"`
}

type errResponse struct {
	Error   bool   `json:"error"`
	Message string `json:"message"`
}

// SpotifyLyrics_GetLyricsJson returns a JSON payload matching the old CLI output:
// - {"error":false,"syncType":"...","lines":[...]} on success
// - {"error":true,"message":"..."} on error
//
// The returned string must be freed with SpotifyLyrics_FreeString().
//
//export SpotifyLyrics_GetLyricsJson
func SpotifyLyrics_GetLyricsJson(spdc *C.char, trackIdOrUrl *C.char) *C.char {
	spdcStr := C.GoString(spdc)
	trackStr := C.GoString(trackIdOrUrl)

	c, err := spotifylyrics.New(spdcStr)
	if err != nil {
		b, _ := json.Marshal(errResponse{Error: true, Message: err.Error()})
		return C.CString(string(b))
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	var lr *spotifylyrics.LyricsResponse
	if strings.HasPrefix(trackStr, "http://") || strings.HasPrefix(trackStr, "https://") || strings.Contains(trackStr, "spotify:") {
		lr, err = c.GetLyricsFromURL(ctx, trackStr)
	} else {
		lr, err = c.GetLyrics(ctx, trackStr)
	}
	if err != nil {
		b, _ := json.Marshal(errResponse{Error: true, Message: err.Error()})
		return C.CString(string(b))
	}

	b, _ := json.Marshal(okResponse{
		Error:    false,
		SyncType: lr.Lyrics.SyncType,
		Lines:    lr.Lyrics.Lines,
	})
	return C.CString(string(b))
}

//export SpotifyLyrics_FreeString
func SpotifyLyrics_FreeString(s *C.char) {
	C.free(unsafe.Pointer(s))
}

func main() {}
