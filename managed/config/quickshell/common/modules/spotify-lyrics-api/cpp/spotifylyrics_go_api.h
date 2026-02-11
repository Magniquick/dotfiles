#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Returns a malloc-allocated UTF-8 JSON string. Free with SpotifyLyrics_FreeString().
char *SpotifyLyrics_GetLyricsJson(const char *spdc, const char *trackIdOrUrl);
void SpotifyLyrics_FreeString(char *s);

#ifdef __cplusplus
} // extern "C"
#endif

