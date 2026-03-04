package main

// #include <stdlib.h>
import "C"

import (
	"context"
	"encoding/json"
	"strconv"
	"time"
	"unsafe"

	"unified-lyrics-api/unifiedlyrics"
)

var sharedClient = unifiedlyrics.New()

type okResponse struct {
	Error    bool                         `json:"error"`
	Source   string                       `json:"source"`
	SyncType string                       `json:"syncType"`
	Metadata unifiedlyrics.ResultMetadata `json:"metadata"`
	Lines    interface{}                  `json:"lines"`
}

type errResponse struct {
	Error   bool   `json:"error"`
	Message string `json:"message"`
}

//export UnifiedLyrics_GetLyricsJson
func UnifiedLyrics_GetLyricsJson(spdc *C.char,
	spotifyTrackRef *C.char,
	trackName *C.char,
	artistName *C.char,
	albumName *C.char,
	durationSeconds *C.char) *C.char {
	dur := 0
	if ds := C.GoString(durationSeconds); ds != "" {
		if v, err := strconv.Atoi(ds); err == nil && v > 0 {
			dur = v
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	res, err := sharedClient.Fetch(ctx, unifiedlyrics.Request{
		SPDC:            C.GoString(spdc),
		SpotifyTrackRef: C.GoString(spotifyTrackRef),
		TrackName:       C.GoString(trackName),
		ArtistName:      C.GoString(artistName),
		AlbumName:       C.GoString(albumName),
		DurationSeconds: dur,
	})
	if err != nil {
		b, _ := json.Marshal(errResponse{Error: true, Message: err.Error()})
		return C.CString(string(b))
	}

	b, _ := json.Marshal(okResponse{
		Error:    false,
		Source:   res.Source,
		SyncType: res.SyncType,
		Metadata: res.Metadata,
		Lines:    res.Lines,
	})
	return C.CString(string(b))
}

//export UnifiedLyrics_FreeString
func UnifiedLyrics_FreeString(s *C.char) {
	C.free(unsafe.Pointer(s))
}

func main() {}
