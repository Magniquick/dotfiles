#include <limits.h>
#include <math.h>

#include "grim.h"
#include "output-layout.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

void get_capture_layout_extents(struct grim_state *state, struct grim_box *box) {
    int32_t x1 = INT_MAX, y1 = INT_MAX;
    int32_t x2 = INT_MIN, y2 = INT_MIN;

    struct grim_capture *capture;
    wl_list_for_each(capture, &state->captures, link) {
        if (capture->logical_geometry.x < x1)
            x1 = capture->logical_geometry.x;
        if (capture->logical_geometry.y < y1)
            y1 = capture->logical_geometry.y;
        if (capture->logical_geometry.x + capture->logical_geometry.width > x2)
            x2 = capture->logical_geometry.x + capture->logical_geometry.width;
        if (capture->logical_geometry.y + capture->logical_geometry.height > y2)
            y2 = capture->logical_geometry.y + capture->logical_geometry.height;
    }

    box->x = x1;
    box->y = y1;
    box->width = x2 - x1;
    box->height = y2 - y1;
}

void apply_output_transform(enum wl_output_transform transform, int32_t *width, int32_t *height) {
    if (transform & WL_OUTPUT_TRANSFORM_90) {
        int32_t tmp = *width;
        *width = *height;
        *height = tmp;
    }
}

double get_output_rotation(enum wl_output_transform transform) {
    switch (transform & ~WL_OUTPUT_TRANSFORM_FLIPPED) {
    case WL_OUTPUT_TRANSFORM_90:
        return M_PI / 2;
    case WL_OUTPUT_TRANSFORM_180:
        return M_PI;
    case WL_OUTPUT_TRANSFORM_270:
        return 3 * M_PI / 2;
    default:
        return 0;
    }
}

int get_output_flipped(enum wl_output_transform transform) {
    return transform & WL_OUTPUT_TRANSFORM_FLIPPED ? -1 : 1;
}

void guess_output_logical_geometry(struct grim_output *output) {
    output->logical_geometry.x = output->fallback_x;
    output->logical_geometry.y = output->fallback_y;
    output->logical_geometry.width = output->mode_width / output->scale;
    output->logical_geometry.height = output->mode_height / output->scale;
    apply_output_transform(output->transform,
        &output->logical_geometry.width,
        &output->logical_geometry.height);
    output->logical_scale = output->scale;
}
