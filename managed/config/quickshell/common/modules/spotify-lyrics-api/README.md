# spotify-lyrics-api

Local module for fetching Spotify lyrics from Web Player endpoints.

Warning: this approach may violate Spotify TOS. Use at your own risk.

## Requirements

- `SP_DC` cookie value from a logged-in Spotify Web session.
- Go toolchain (for building the C shared library).
- Qt6 (`Core`, `Qml`, `Concurrent`) for the QML plugin.

## What It Exposes

### 1. Go package (`spotifylyrics`)

Main constructor:

```go
c, err := spotifylyrics.New(os.Getenv("SP_DC"))
```

Main methods:

- `TrackIDFromURL(input string) (string, error)`
- `(*Client).EnsureToken(ctx)`
- `(*Client).GetLyrics(ctx, trackID)`
- `(*Client).GetLyricsFromURL(ctx, trackURL)`

Useful options on `New(...)`:

- `WithCachePath(path)` for token cache file.
- `WithSecretCachePath(path)` for secret dictionary cache file.
- `WithLyricsCacheDir(dir)` / `WithLyricsCacheTTL(ttl)` / `WithLyricsCacheEnabled(bool)`.
- `WithTokenTimeout(d)` and user-agent overrides.

Response shape (from `GetLyrics*`):

- `LyricsResponse.Lyrics.SyncType`
- `LyricsResponse.Lyrics.Lines[]` with fields:
  - `startTimeMs`, `endTimeMs`, `words`, `syllables`

### 2. C ABI (used by Qt/C++)

From `capi/spotifylyrics_capi.go`:

- `SpotifyLyrics_GetLyricsJson(spdc, trackIdOrUrl) -> char*`
- `SpotifyLyrics_FreeString(char*)`

Return JSON:

- Success: `{"error":false,"syncType":"...","lines":[...]}`
- Failure: `{"error":true,"message":"..."}`

### 3. QML module (`import spotifylyrics 1.0`)

Type: `SpotifyLyricsClient`

Invokable:

- `refreshFromEnv(envFile, trackIdOrUrl): bool`

Properties:

- `busy: bool`
- `loaded: bool`
- `status: string`
- `error: string`
- `syncType: string`
- `trackId: string`
- `lines: var` (array of `{ startTimeMs, words }` maps for QML)

## Build

```bash
cd common/modules/spotify-lyrics-api
cmake -S . -B build
cmake --build build
```

QML import output is in `build/qml/spotifylyrics`.

## QML Usage Example

```qml
import QtQuick
import spotifylyrics 1.0

Item {
  property string envFile: Qt.resolvedUrl("../bar/.env")
  property string trackRef: "https://open.spotify.com/track/5f8eCNwTlr0RJopE9vQ6mB"

  SpotifyLyricsClient {
    id: lyrics
  }

  Component.onCompleted: lyrics.refreshFromEnv(envFile, trackRef)

  // lyrics.lines is an array of maps: { startTimeMs, words }
}
```
