# unified-lyrics-api

Unified native lyrics module that wraps multiple lyrics providers behind one Go interface.

Fallback order:

1. `WORD_SYNCED`
2. `LINE_SYNCED`
3. `UNSYNCED`

Provider order for tie-breaks:

1. Spotify
2. NetEase
3. LRCLIB

Caching behavior:

- The unified client does not keep an in-memory cache.
- Cache root is configured at construction time in Go (`unifiedlyrics.New(cacheDir)`), and the C API reads it from `UNIFIED_LYRICS_CACHE_DIR`.
- Cache storage is owned by `unified-lyrics-api` and uses a unified namespace under the cache root.

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
- `source` (for example `spotify_synced`, `netease_word`, `lrclib_normal`)
- `metadata` (object, includes `provider`)
- `syncType` (`WORD_SYNCED`, `LINE_SYNCED`, or `UNSYNCED`)
- `lines` (array of `{ startTimeMs, endTimeMs, words, segments }`)

Final lyrics cache key identity uses a tuple:
- `title␞artist␞album␞length_us` (U+241E separator, empty string for missing fields)
