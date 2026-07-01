#ifndef QS_CAPTURE_BUFFER_H
#define QS_CAPTURE_BUFFER_H

#include <stddef.h>
#include <stdint.h>
#include <wayland-client.h>

struct grim_buffer {
    struct wl_buffer *wl_buffer;
    void *data;
    int32_t width, height, stride;
    size_t size;
    enum wl_shm_format format;
};

struct grim_buffer *create_buffer(struct wl_shm *shm, enum wl_shm_format format,
    int32_t width, int32_t height, int32_t stride);
void destroy_buffer(struct grim_buffer *buffer);

#endif
