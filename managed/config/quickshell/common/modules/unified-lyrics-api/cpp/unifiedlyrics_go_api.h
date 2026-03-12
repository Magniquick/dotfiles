#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  char *startTimeMs;
  char *endTimeMs;
  char *text;
} UnifiedLyricsSegment;

typedef struct {
  char *startTimeMs;
  char *endTimeMs;
  char *words;
  UnifiedLyricsSegment *segments;
  size_t segmentCount;
} UnifiedLyricsLine;

typedef struct {
  _Bool error;
  char *message;
  char *source;
  char *syncType;
  char *provider;
  UnifiedLyricsLine *lines;
  size_t lineCount;
} UnifiedLyricsResult;

UnifiedLyricsResult *UnifiedLyrics_GetLyrics(const char *spdc,
                                             const char *spotifyTrackRef,
                                             const char *trackName,
                                             const char *artistName,
                                             const char *albumName,
                                             const char *lengthMicros);
void UnifiedLyrics_FreeResult(UnifiedLyricsResult *result);

#ifdef __cplusplus
}
#endif
