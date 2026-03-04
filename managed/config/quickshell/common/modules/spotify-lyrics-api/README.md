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
c, err := spotifylyrics.NewWithCacheDir(os.Getenv("SP_DC"), "/custom/cache/root")
```

Main methods:

- `TrackIDFromURL(input string) (string, error)`
- `(*Client).EnsureToken(ctx)`
- `(*Client).GetLyrics(ctx, trackID)`
- `(*Client).GetLyricsFromURL(ctx, trackURL)`

Useful options on `New(...)`:

- `NewWithCacheDir(spdc, cacheDir)` to set one cache root for token/secret/lyrics caches.
- `WithCachePath(path)`, `WithSecretCachePath(path)`, `WithLyricsCacheDir(dir)` for legacy key scoping overrides.
- `WithLyricsCacheTTL(ttl)` / `WithLyricsCacheEnabled(bool)`.
- `WithTokenTimeout(d)` and user-agent overrides.

## Cache key model

The cache uses unified, versioned logical keys:

- Token: `lyrics:v1:token:spdc_sha256:<sha256(trim(spdc))>:default`
- Secret dict: `lyrics:v1:secret_dict:global:url_sha256:<sha256(secretDictURL)>`
- Lyrics: `lyrics:v1:lyrics:global:track:<lower(trim(trackID))>`

Why token includes `spdc_sha256`:
- Spotify access tokens are obtained from `sp_dc` and are session/account scoped.
- Lyrics cache is intentionally not scoped by `sp_dc` to maximize reuse by track ID.

## Secret dict

`secretDict.json` is an upstream Spotify-related version map used to derive token request parameters.

- It is fetched from the configured `secretDictURL`.
- We cache it with `ETag` to support conditional requests (`If-None-Match`).
- It is global (not tied to `SP_DC`), so its key does not include `spdc_sha256`.

Response shape (from `GetLyrics*`):

- `LyricsResponse.Lyrics.SyncType`
- `LyricsResponse.Lyrics.Lines[]` with fields:
  - `startTimeMs`, `endTimeMs`, `words`, `syllables`

## Usage

This package is consumed by `common/modules/unified-lyrics-api` as the Spotify backend in a transparent fallback chain.
