#ifndef QS_CAPTURE_RENDER_H
#define QS_CAPTURE_RENDER_H

#include <pixman.h>
#include <stdbool.h>

#include "buffer.h"
#include "grim.h"

bool is_format_supported(enum wl_shm_format fmt);
uint32_t get_format_min_stride(enum wl_shm_format fmt, uint32_t width);
pixman_image_t *render(struct grim_state *state, struct grim_box *geometry,
    double scale);
pixman_image_t *create_image_from_buffer(struct grim_buffer *buffer);

#endif
