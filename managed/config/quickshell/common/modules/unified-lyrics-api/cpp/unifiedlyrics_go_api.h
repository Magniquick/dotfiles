#pragma once

#ifdef __cplusplus
extern "C" {
#endif

char *UnifiedLyrics_GetLyricsJson(const char *spdc,
                                  const char *spotifyTrackRef,
                                  const char *trackName,
                                  const char *artistName,
                                  const char *albumName,
                                  const char *durationSeconds);
void UnifiedLyrics_FreeString(char *s);

#ifdef __cplusplus
}
#endif
