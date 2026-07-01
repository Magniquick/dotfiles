#ifndef QS_CAPTURE_CORE_H
#define QS_CAPTURE_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct qs_capture_toplevel_request {
    const char *identifier;
    const char *file_path;
} qs_capture_toplevel_request;

int qs_capture_capture_output(const char *output_name, const char *file_path, bool with_cursor, char **error);
int qs_capture_capture_region(int32_t x, int32_t y, int32_t width, int32_t height, double scale, const char *file_path, bool with_cursor, char **error);
int qs_capture_capture_toplevel(const char *identifier, const char *file_path, bool with_cursor, char **error);
int qs_capture_capture_toplevel_batch(const qs_capture_toplevel_request *requests, size_t request_count, bool with_cursor, size_t *completed_count, char **error);
void qs_capture_free_error(char *error);

#endif
