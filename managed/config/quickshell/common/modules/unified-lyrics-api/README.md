# unified-lyrics-api

Unified native lyrics module that wraps Spotify and LRCLIB behind one Go interface.

Fallback order:

1. Spotify synced
2. LRCLIB synced
3. Spotify normal
4. LRCLIB normal

Caching behavior:

- The unified client does not keep an in-memory cache.
- Spotify cache root is configured at construction time in Go (`unifiedlyrics.New(cacheDir)`), and the C API reads it from `UNIFIED_LYRICS_SPOTIFY_CACHE_DIR`.

## QML module

```qml
import unifiedlyrics 1.0

UnifiedLyricsClient {
  id: lyrics
}
```

Invokable:

- `refreshFromEnv(envFile, spotifyTrackRef, trackName, artistName, albumName, lengthMicros): bool`

Properties:

- `busy`
- `loaded`
- `status`
- `error`
- `source` (`spotify_synced`, `lrclib_synced`, `spotify_normal`, `lrclib_normal`)
- `metadata` (object, includes `provider` as `spotify` or `lrclib`)
- `syncType` (`LINE_SYNCED` or `UNSYNCED`)
- `lines` (array of `{ startTimeMs, words }`)

Final lyrics cache key identity uses a tuple:
- `title␞artist␞album␞length_us` (U+241E separator, empty string for missing fields)
