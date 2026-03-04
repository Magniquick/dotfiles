# spotify-lyrics-api

Go package for fetching Spotify lyrics from Web Player endpoints.

Warning: this approach may violate Spotify TOS. Use at your own risk.

## Requirements

- `SP_DC` cookie value from a logged-in Spotify Web session.
- Go toolchain.

## Package (`spotifylyrics`)

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

## Usage

This package is consumed by `common/modules/unified-lyrics-api` as the Spotify backend in a transparent fallback chain.
