// Command lyrics-lookup queries the unified lyrics provider stack.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/zalando/go-keyring"

	"unified-lyrics-api/unifiedlyrics"
)

func main() {
	var cacheDir string
	var spotifyRef string
	var track string
	var artist string
	var album string
	var lengthMicros string
	var limit int
	var noCache bool

	flag.StringVar(&cacheDir, "cache-dir", "", "lyrics cache directory")
	flag.BoolVar(&noCache, "no-cache", false, "disable lyric cache reads and writes")
	flag.StringVar(&spotifyRef, "spotify-ref", "", "spotify track URL/URI/id")
	flag.StringVar(&track, "track", "", "track name")
	flag.StringVar(&artist, "artist", "", "artist name")
	flag.StringVar(&album, "album", "", "album name")
	flag.StringVar(&lengthMicros, "length-us", "", "track duration in microseconds")
	flag.IntVar(&limit, "limit", 8, "number of lyric lines to print")
	flag.Parse()

	if strings.TrimSpace(spotifyRef) == "" && (strings.TrimSpace(track) == "" || strings.TrimSpace(artist) == "") {
		fmt.Fprintln(os.Stderr, "spotify-ref or track+artist is required")
		os.Exit(2)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	res, err := unifiedlyrics.New(cacheDir, unifiedlyrics.WithNoCache(noCache)).Fetch(ctx, unifiedlyrics.Request{
		SPDC:            readSecret("SP_DC"),
		SpotifyTrackRef: strings.TrimSpace(spotifyRef),
		TrackName:       strings.TrimSpace(track),
		ArtistName:      strings.TrimSpace(artist),
		AlbumName:       strings.TrimSpace(album),
		LengthMicros:    strings.TrimSpace(lengthMicros),
	})
	if err != nil {
		fmt.Fprintln(os.Stderr, "lookup failed:", err)
		os.Exit(1)
	}

	fmt.Printf(
		"source=%s provider=%s syncType=%s lines=%d\n",
		res.Source,
		res.Metadata.Provider,
		res.SyncType,
		len(res.Lines),
	)
	maxLines := limit
	if maxLines < 0 || maxLines > len(res.Lines) {
		maxLines = len(res.Lines)
	}
	for i := 0; i < maxLines; i++ {
		line := res.Lines[i]
		timing := strings.TrimSpace(line.StartTimeMs)
		if end := strings.TrimSpace(line.EndTimeMs); end != "" {
			timing += "-" + end
		}
		if timing == "" {
			timing = strconv.Itoa(i + 1)
		}
		if len(line.Segments) > 0 {
			fmt.Printf("%s [%d segments] %s\n", timing, len(line.Segments), strings.TrimSpace(line.Words))
		} else {
			fmt.Printf("%s %s\n", timing, strings.TrimSpace(line.Words))
		}
	}
}

func readSecret(key string) string {
	value, err := keyring.Get("quickshell", key)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(value)
}
