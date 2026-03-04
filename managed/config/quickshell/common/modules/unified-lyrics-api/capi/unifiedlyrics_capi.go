package main

/*
#include <stdbool.h>
#include <stdlib.h>

typedef struct {
	char *startTimeMs;
	char *words;
} UnifiedLyricsLine;

typedef struct {
	bool error;
	char *message;
	char *source;
	char *syncType;
	char *provider;
	UnifiedLyricsLine *lines;
	size_t lineCount;
} UnifiedLyricsResult;
*/
import "C"

import (
	"context"
	"os"
	"time"
	"unsafe"

	"unified-lyrics-api/unifiedlyrics"
)

var sharedClient = unifiedlyrics.New(os.Getenv("UNIFIED_LYRICS_SPOTIFY_CACHE_DIR"))

func cString(s string) *C.char {
	if s == "" {
		return nil
	}
	return C.CString(s)
}

func allocResult() *C.UnifiedLyricsResult {
	return (*C.UnifiedLyricsResult)(C.calloc(1, C.size_t(unsafe.Sizeof(C.UnifiedLyricsResult{}))))
}

func setErrorResult(out *C.UnifiedLyricsResult, msg string) {
	if out == nil {
		return
	}
	out.error = C.bool(true)
	out.message = cString(msg)
}

func freeLines(lines *C.UnifiedLyricsLine, count C.size_t) {
	if lines == nil {
		return
	}
	arr := unsafe.Slice(lines, int(count))
	for i := range arr {
		if arr[i].startTimeMs != nil {
			C.free(unsafe.Pointer(arr[i].startTimeMs))
		}
		if arr[i].words != nil {
			C.free(unsafe.Pointer(arr[i].words))
		}
	}
	C.free(unsafe.Pointer(lines))
}

//export UnifiedLyrics_GetLyrics
func UnifiedLyrics_GetLyrics(spdc *C.char,
	spotifyTrackRef *C.char,
	trackName *C.char,
	artistName *C.char,
	albumName *C.char,
	lengthMicros *C.char) *C.UnifiedLyricsResult {
	out := allocResult()
	if out == nil {
		return nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	res, err := sharedClient.Fetch(ctx, unifiedlyrics.Request{
		SPDC:            C.GoString(spdc),
		SpotifyTrackRef: C.GoString(spotifyTrackRef),
		TrackName:       C.GoString(trackName),
		ArtistName:      C.GoString(artistName),
		AlbumName:       C.GoString(albumName),
		LengthMicros:    C.GoString(lengthMicros),
	})
	if err != nil {
		setErrorResult(out, err.Error())
		return out
	}

	out.error = C.bool(false)
	out.source = cString(res.Source)
	out.syncType = cString(res.SyncType)
	out.provider = cString(res.Metadata.Provider)

	if len(res.Lines) == 0 {
		return out
	}

	lineSize := C.size_t(unsafe.Sizeof(C.UnifiedLyricsLine{}))
	lines := (*C.UnifiedLyricsLine)(C.calloc(C.size_t(len(res.Lines)), lineSize))
	if lines == nil {
		setErrorResult(out, "failed to allocate lyrics lines")
		return out
	}

	arr := unsafe.Slice(lines, len(res.Lines))
	for i := range res.Lines {
		arr[i].startTimeMs = cString(res.Lines[i].StartTimeMs)
		arr[i].words = cString(res.Lines[i].Words)
	}
	out.lines = lines
	out.lineCount = C.size_t(len(res.Lines))
	return out
}

//export UnifiedLyrics_FreeResult
func UnifiedLyrics_FreeResult(out *C.UnifiedLyricsResult) {
	if out == nil {
		return
	}
	if out.message != nil {
		C.free(unsafe.Pointer(out.message))
	}
	if out.source != nil {
		C.free(unsafe.Pointer(out.source))
	}
	if out.syncType != nil {
		C.free(unsafe.Pointer(out.syncType))
	}
	if out.provider != nil {
		C.free(unsafe.Pointer(out.provider))
	}
	freeLines(out.lines, out.lineCount)
	C.free(unsafe.Pointer(out))
}

func main() {}
