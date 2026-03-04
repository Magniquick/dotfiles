# unified-lyrics-api

Unified native lyrics module that wraps Spotify and LRCLIB behind one Go interface.

Fallback order:

1. Spotify synced
2. LRCLIB synced
3. Spotify normal
4. LRCLIB normal

Caching behavior:

- The unified client caches only the final selected result from the fallback chain.
- Intermediate candidates are not cached.

## QML module

```qml
import unifiedlyrics 1.0

UnifiedLyricsClient {
  id: lyrics
}
```

Invokable:

- `refreshFromEnv(envFile, spotifyTrackRef, trackName, artistName, albumName, durationSeconds): bool`

Properties:

- `busy`
- `loaded`
- `status`
- `error`
- `source` (`spotify_synced`, `lrclib_synced`, `spotify_normal`, `lrclib_normal`)
- `metadata` (object, includes `provider` as `spotify` or `lrclib`)
- `syncType` (`LINE_SYNCED` or `UNSYNCED`)
- `lines` (array of `{ startTimeMs, words }`)
