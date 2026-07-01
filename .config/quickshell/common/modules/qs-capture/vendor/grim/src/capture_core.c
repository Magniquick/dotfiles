#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <pixman.h>

#include "buffer.h"
#include "capture_core.h"
#include "grim.h"
#include "output-layout.h"
#include "render.h"
#include "write_png.h"

#include "ext-foreign-toplevel-list-v1-protocol.h"
#include "ext-image-capture-source-v1-protocol.h"
#include "ext-image-copy-capture-v1-protocol.h"
#include "wlr-screencopy-unstable-v1-protocol.h"
#include "xdg-output-unstable-v1-protocol.h"

static void set_errorf(struct grim_state *state, const char *fmt, ...) {
    if (state->error_message)
        return;
    va_list args;
    va_start(args, fmt);
    char *message = NULL;
    if (vasprintf(&message, fmt, args) == -1)
        message = strdup("Unknown capture error");
    va_end(args);
    state->failed = true;
    state->error_message = message;
}

static void screencopy_frame_handle_buffer(void *data,
        struct zwlr_screencopy_frame_v1 *frame, uint32_t format, uint32_t width,
        uint32_t height, uint32_t stride) {
    struct grim_capture *capture = data;
    capture->buffer = create_buffer(capture->state->shm, format, width, height, stride);
    if (!capture->buffer) {
        set_errorf(capture->state, "failed to create output buffer");
        return;
    }
    zwlr_screencopy_frame_v1_copy(frame, capture->buffer->wl_buffer);
}

static void screencopy_frame_handle_flags(void *data,
        struct zwlr_screencopy_frame_v1 *frame, uint32_t flags) {
    struct grim_capture *capture = data;
    capture->screencopy_frame_flags = flags;
}

static void screencopy_frame_handle_ready(void *data,
        struct zwlr_screencopy_frame_v1 *frame, uint32_t tv_sec_hi,
        uint32_t tv_sec_lo, uint32_t tv_nsec) {
    struct grim_capture *capture = data;
    ++capture->state->n_done;
}

static void screencopy_frame_handle_failed(void *data,
        struct zwlr_screencopy_frame_v1 *frame) {
    struct grim_capture *capture = data;
    set_errorf(capture->state, "failed to copy output %s", capture->source_label ? capture->source_label : "unknown");
}

static const struct zwlr_screencopy_frame_v1_listener screencopy_frame_listener = {
    .buffer = screencopy_frame_handle_buffer,
    .flags = screencopy_frame_handle_flags,
    .ready = screencopy_frame_handle_ready,
    .failed = screencopy_frame_handle_failed,
};

static void ext_image_copy_capture_frame_handle_transform(void *data,
        struct ext_image_copy_capture_frame_v1 *frame, uint32_t transform) {
    struct grim_capture *capture = data;
    capture->transform = transform;
}

static void ext_image_copy_capture_frame_handle_damage(void *data,
        struct ext_image_copy_capture_frame_v1 *frame, int32_t x, int32_t y,
        int32_t width, int32_t height) {
    (void)data;
    (void)frame;
    (void)x;
    (void)y;
    (void)width;
    (void)height;
}

static void ext_image_copy_capture_frame_handle_presentation_time(void *data,
        struct ext_image_copy_capture_frame_v1 *frame, uint32_t tv_sec_hi,
        uint32_t tv_sec_lo, uint32_t tv_nsec) {
    (void)data;
    (void)frame;
    (void)tv_sec_hi;
    (void)tv_sec_lo;
    (void)tv_nsec;
}

static void ext_image_copy_capture_frame_handle_ready(void *data,
        struct ext_image_copy_capture_frame_v1 *frame) {
    struct grim_capture *capture = data;
    ++capture->state->n_done;
}

static void ext_image_copy_capture_frame_handle_failed(void *data,
        struct ext_image_copy_capture_frame_v1 *frame, uint32_t reason) {
    struct grim_capture *capture = data;
    set_errorf(capture->state, "failed to copy source %s (reason %u)", capture->source_label ? capture->source_label : "unknown", reason);
}

static const struct ext_image_copy_capture_frame_v1_listener ext_image_copy_capture_frame_listener = {
    .transform = ext_image_copy_capture_frame_handle_transform,
    .damage = ext_image_copy_capture_frame_handle_damage,
    .presentation_time = ext_image_copy_capture_frame_handle_presentation_time,
    .ready = ext_image_copy_capture_frame_handle_ready,
    .failed = ext_image_copy_capture_frame_handle_failed,
};

static void ext_image_copy_capture_session_handle_buffer_size(void *data,
        struct ext_image_copy_capture_session_v1 *session, uint32_t width, uint32_t height) {
    struct grim_capture *capture = data;
    capture->buffer_width = width;
    capture->buffer_height = height;
    if (!capture->output) {
        capture->logical_geometry.width = width;
        capture->logical_geometry.height = height;
    }
}

static void ext_image_copy_capture_session_handle_shm_format(void *data,
        struct ext_image_copy_capture_session_v1 *session, uint32_t format) {
    struct grim_capture *capture = data;
    if (capture->has_shm_format || !is_format_supported(format))
        return;
    capture->shm_format = format;
    capture->has_shm_format = true;
}

static void ext_image_copy_capture_session_handle_dmabuf_device(void *data,
        struct ext_image_copy_capture_session_v1 *session, struct wl_array *dev_id_array) {
    (void)data;
    (void)session;
    (void)dev_id_array;
}

static void ext_image_copy_capture_session_handle_dmabuf_format(void *data,
        struct ext_image_copy_capture_session_v1 *session, uint32_t format,
        struct wl_array *modifiers_array) {
    (void)data;
    (void)session;
    (void)format;
    (void)modifiers_array;
}

static void ext_image_copy_capture_session_handle_done(void *data,
        struct ext_image_copy_capture_session_v1 *session) {
    struct grim_capture *capture = data;
    if (capture->ext_image_copy_capture_frame)
        return;
    if (!capture->has_shm_format) {
        set_errorf(capture->state, "no supported shm format found");
        return;
    }

    int32_t stride = get_format_min_stride(capture->shm_format, capture->buffer_width);
    capture->buffer = create_buffer(capture->state->shm, capture->shm_format, capture->buffer_width, capture->buffer_height, stride);
    if (!capture->buffer) {
        set_errorf(capture->state, "failed to create shm buffer");
        return;
    }

    capture->ext_image_copy_capture_frame = ext_image_copy_capture_session_v1_create_frame(session);
    ext_image_copy_capture_frame_v1_add_listener(capture->ext_image_copy_capture_frame,
        &ext_image_copy_capture_frame_listener, capture);
    ext_image_copy_capture_frame_v1_attach_buffer(capture->ext_image_copy_capture_frame, capture->buffer->wl_buffer);
    ext_image_copy_capture_frame_v1_damage_buffer(capture->ext_image_copy_capture_frame, 0, 0, INT32_MAX, INT32_MAX);
    ext_image_copy_capture_frame_v1_capture(capture->ext_image_copy_capture_frame);
}

static void ext_image_copy_capture_session_handle_stopped(void *data,
        struct ext_image_copy_capture_session_v1 *session) {
    (void)data;
    (void)session;
}

static const struct ext_image_copy_capture_session_v1_listener ext_image_copy_capture_session_listener = {
    .buffer_size = ext_image_copy_capture_session_handle_buffer_size,
    .shm_format = ext_image_copy_capture_session_handle_shm_format,
    .dmabuf_device = ext_image_copy_capture_session_handle_dmabuf_device,
    .dmabuf_format = ext_image_copy_capture_session_handle_dmabuf_format,
    .done = ext_image_copy_capture_session_handle_done,
    .stopped = ext_image_copy_capture_session_handle_stopped,
};

static void foreign_toplevel_handle_closed(void *data,
        struct ext_foreign_toplevel_handle_v1 *toplevel_handle) {
    (void)data;
    (void)toplevel_handle;
}

static void foreign_toplevel_handle_done(void *data,
        struct ext_foreign_toplevel_handle_v1 *toplevel_handle) {
    (void)data;
    (void)toplevel_handle;
}

static void foreign_toplevel_handle_title(void *data,
        struct ext_foreign_toplevel_handle_v1 *toplevel_handle, const char *title) {
    (void)data;
    (void)toplevel_handle;
    (void)title;
}

static void foreign_toplevel_handle_app_id(void *data,
        struct ext_foreign_toplevel_handle_v1 *toplevel_handle, const char *app_id) {
    (void)data;
    (void)toplevel_handle;
    (void)app_id;
}

static void foreign_toplevel_handle_identifier(void *data,
        struct ext_foreign_toplevel_handle_v1 *toplevel_handle, const char *identifier) {
    struct grim_toplevel *toplevel = data;
    free(toplevel->identifier);
    toplevel->identifier = strdup(identifier);
}

static const struct ext_foreign_toplevel_handle_v1_listener foreign_toplevel_listener = {
    .closed = foreign_toplevel_handle_closed,
    .done = foreign_toplevel_handle_done,
    .title = foreign_toplevel_handle_title,
    .app_id = foreign_toplevel_handle_app_id,
    .identifier = foreign_toplevel_handle_identifier,
};

static void foreign_toplevel_list_handle_toplevel(void *data,
        struct ext_foreign_toplevel_list_v1 *list,
        struct ext_foreign_toplevel_handle_v1 *toplevel_handle) {
    struct grim_state *state = data;
    struct grim_toplevel *toplevel = calloc(1, sizeof(*toplevel));
    wl_list_insert(&state->toplevels, &toplevel->link);
    toplevel->handle = toplevel_handle;
    ext_foreign_toplevel_handle_v1_add_listener(toplevel_handle, &foreign_toplevel_listener, toplevel);
}

static void foreign_toplevel_list_handle_finished(void *data,
        struct ext_foreign_toplevel_list_v1 *list) {
    (void)data;
    (void)list;
}

static const struct ext_foreign_toplevel_list_v1_listener foreign_toplevel_list_listener = {
    .toplevel = foreign_toplevel_list_handle_toplevel,
    .finished = foreign_toplevel_list_handle_finished,
};

static void xdg_output_handle_logical_position(void *data,
        struct zxdg_output_v1 *xdg_output, int32_t x, int32_t y) {
    struct grim_output *output = data;
    output->logical_geometry.x = x;
    output->logical_geometry.y = y;
}

static void xdg_output_handle_logical_size(void *data,
        struct zxdg_output_v1 *xdg_output, int32_t width, int32_t height) {
    struct grim_output *output = data;
    output->logical_geometry.width = width;
    output->logical_geometry.height = height;
}

static void xdg_output_handle_done(void *data,
        struct zxdg_output_v1 *xdg_output) {
    struct grim_output *output = data;
    int32_t width = output->mode_width;
    int32_t height = output->mode_height;
    apply_output_transform(output->transform, &width, &height);
    output->logical_scale = (double)width / output->logical_geometry.width;
}

static void xdg_output_handle_name(void *data,
        struct zxdg_output_v1 *xdg_output, const char *name) {
    struct grim_output *output = data;
    if (!output->name)
        output->name = strdup(name);
}

static void xdg_output_handle_description(void *data,
        struct zxdg_output_v1 *xdg_output, const char *description) {
    (void)data;
    (void)xdg_output;
    (void)description;
}

static const struct zxdg_output_v1_listener xdg_output_listener = {
    .logical_position = xdg_output_handle_logical_position,
    .logical_size = xdg_output_handle_logical_size,
    .done = xdg_output_handle_done,
    .name = xdg_output_handle_name,
    .description = xdg_output_handle_description,
};

static void output_handle_geometry(void *data, struct wl_output *wl_output,
        int32_t x, int32_t y, int32_t physical_width, int32_t physical_height,
        int32_t subpixel, const char *make, const char *model,
        int32_t transform) {
    struct grim_output *output = data;
    output->fallback_x = x;
    output->fallback_y = y;
    output->transform = transform;
}

static void output_handle_mode(void *data, struct wl_output *wl_output,
        uint32_t flags, int32_t width, int32_t height, int32_t refresh) {
    struct grim_output *output = data;
    if ((flags & WL_OUTPUT_MODE_CURRENT) != 0) {
        output->mode_width = width;
        output->mode_height = height;
    }
}

static void output_handle_done(void *data, struct wl_output *wl_output) {
    (void)data;
    (void)wl_output;
}

static void output_handle_scale(void *data, struct wl_output *wl_output,
        int32_t factor) {
    struct grim_output *output = data;
    output->scale = factor;
}

static void output_handle_name(void *data, struct wl_output *wl_output,
        const char *name) {
    struct grim_output *output = data;
    free(output->name);
    output->name = strdup(name);
}

static void output_handle_description(void *data, struct wl_output *wl_output,
        const char *description) {
    (void)data;
    (void)wl_output;
    (void)description;
}

static const struct wl_output_listener output_listener = {
    .geometry = output_handle_geometry,
    .mode = output_handle_mode,
    .done = output_handle_done,
    .scale = output_handle_scale,
    .name = output_handle_name,
    .description = output_handle_description,
};

static void handle_global(void *data, struct wl_registry *registry,
        uint32_t name, const char *interface, uint32_t version) {
    struct grim_state *state = data;

    if (strcmp(interface, wl_shm_interface.name) == 0) {
        state->shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    } else if (strcmp(interface, zxdg_output_manager_v1_interface.name) == 0) {
        uint32_t bind_version = version > 2 ? 2 : version;
        state->xdg_output_manager = wl_registry_bind(registry, name, &zxdg_output_manager_v1_interface, bind_version);
    } else if (strcmp(interface, wl_output_interface.name) == 0) {
        uint32_t bind_version = version >= 4 ? 4 : 3;
        struct grim_output *output = calloc(1, sizeof(*output));
        output->state = state;
        output->scale = 1;
        output->wl_output = wl_registry_bind(registry, name, &wl_output_interface, bind_version);
        wl_output_add_listener(output->wl_output, &output_listener, output);
        wl_list_insert(&state->outputs, &output->link);
    } else if (strcmp(interface, ext_output_image_capture_source_manager_v1_interface.name) == 0) {
        state->ext_output_image_capture_source_manager = wl_registry_bind(registry, name, &ext_output_image_capture_source_manager_v1_interface, 1);
    } else if (strcmp(interface, ext_foreign_toplevel_image_capture_source_manager_v1_interface.name) == 0) {
        state->ext_foreign_toplevel_image_capture_source_manager = wl_registry_bind(registry, name, &ext_foreign_toplevel_image_capture_source_manager_v1_interface, 1);
    } else if (strcmp(interface, ext_image_copy_capture_manager_v1_interface.name) == 0) {
        state->ext_image_copy_capture_manager = wl_registry_bind(registry, name, &ext_image_copy_capture_manager_v1_interface, 1);
    } else if (strcmp(interface, zwlr_screencopy_manager_v1_interface.name) == 0) {
        state->screencopy_manager = wl_registry_bind(registry, name, &zwlr_screencopy_manager_v1_interface, 1);
    } else if (strcmp(interface, ext_foreign_toplevel_list_v1_interface.name) == 0) {
        state->foreign_toplevel_list = wl_registry_bind(registry, name, &ext_foreign_toplevel_list_v1_interface, 1);
        ext_foreign_toplevel_list_v1_add_listener(state->foreign_toplevel_list, &foreign_toplevel_list_listener, state);
    }
}

static void handle_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = handle_global,
    .global_remove = handle_global_remove,
};

static void cleanup_state(struct grim_state *state) {
    struct grim_capture *capture, *capture_tmp;
    wl_list_for_each_safe(capture, capture_tmp, &state->captures, link) {
        wl_list_remove(&capture->link);
        if (capture->ext_image_copy_capture_frame)
            ext_image_copy_capture_frame_v1_destroy(capture->ext_image_copy_capture_frame);
        if (capture->ext_image_copy_capture_session)
            ext_image_copy_capture_session_v1_destroy(capture->ext_image_copy_capture_session);
        if (capture->screencopy_frame)
            zwlr_screencopy_frame_v1_destroy(capture->screencopy_frame);
        destroy_buffer(capture->buffer);
        free(capture->file_path);
        free(capture->source_label);
        free(capture);
    }

    struct grim_output *output, *output_tmp;
    wl_list_for_each_safe(output, output_tmp, &state->outputs, link) {
        wl_list_remove(&output->link);
        free(output->name);
        if (output->xdg_output)
            zxdg_output_v1_destroy(output->xdg_output);
        if (output->wl_output)
            wl_output_release(output->wl_output);
        free(output);
    }

    struct grim_toplevel *toplevel, *toplevel_tmp;
    wl_list_for_each_safe(toplevel, toplevel_tmp, &state->toplevels, link) {
        wl_list_remove(&toplevel->link);
        free(toplevel->identifier);
        if (toplevel->handle)
            ext_foreign_toplevel_handle_v1_destroy(toplevel->handle);
        free(toplevel);
    }

    if (state->foreign_toplevel_list)
        ext_foreign_toplevel_list_v1_destroy(state->foreign_toplevel_list);
    if (state->ext_output_image_capture_source_manager)
        ext_output_image_capture_source_manager_v1_destroy(state->ext_output_image_capture_source_manager);
    if (state->ext_foreign_toplevel_image_capture_source_manager)
        ext_foreign_toplevel_image_capture_source_manager_v1_destroy(state->ext_foreign_toplevel_image_capture_source_manager);
    if (state->ext_image_copy_capture_manager)
        ext_image_copy_capture_manager_v1_destroy(state->ext_image_copy_capture_manager);
    if (state->screencopy_manager)
        zwlr_screencopy_manager_v1_destroy(state->screencopy_manager);
    if (state->xdg_output_manager)
        zxdg_output_manager_v1_destroy(state->xdg_output_manager);
    if (state->shm)
        wl_shm_destroy(state->shm);
    if (state->registry)
        wl_registry_destroy(state->registry);
    if (state->display)
        wl_display_disconnect(state->display);
}

static int init_state(struct grim_state *state, bool need_toplevels) {
    memset(state, 0, sizeof(*state));
    wl_list_init(&state->outputs);
    wl_list_init(&state->toplevels);
    wl_list_init(&state->captures);

    state->display = wl_display_connect(NULL);
    if (!state->display) {
        set_errorf(state, "failed to connect to wayland display");
        return -1;
    }

    state->registry = wl_display_get_registry(state->display);
    wl_registry_add_listener(state->registry, &registry_listener, state);
    if (wl_display_roundtrip(state->display) < 0) {
        set_errorf(state, "wl_display_roundtrip failed during registry setup");
        return -1;
    }

    if (!state->shm) {
        set_errorf(state, "compositor doesn't support wl_shm");
        return -1;
    }

    if (state->xdg_output_manager) {
        struct grim_output *output;
        wl_list_for_each(output, &state->outputs, link) {
            output->xdg_output = zxdg_output_manager_v1_get_xdg_output(state->xdg_output_manager, output->wl_output);
            zxdg_output_v1_add_listener(output->xdg_output, &xdg_output_listener, output);
        }
    }

    if (wl_display_roundtrip(state->display) < 0) {
        set_errorf(state, "wl_display_roundtrip failed during output discovery");
        return -1;
    }

    if (!state->xdg_output_manager) {
        struct grim_output *output;
        wl_list_for_each(output, &state->outputs, link) {
            guess_output_logical_geometry(output);
        }
    }

    if (need_toplevels && !state->ext_foreign_toplevel_image_capture_source_manager) {
        set_errorf(state, "compositor doesn't support foreign toplevel capture");
        return -1;
    }
    if (need_toplevels && !state->ext_image_copy_capture_manager) {
        set_errorf(state, "compositor doesn't support ext-image-copy-capture");
        return -1;
    }
    if (!need_toplevels && !state->screencopy_manager && !(state->ext_output_image_capture_source_manager && state->ext_image_copy_capture_manager)) {
        set_errorf(state, "compositor doesn't support output capture");
        return -1;
    }

    return 0;
}

static struct grim_output *find_output_by_name(struct grim_state *state, const char *name) {
    struct grim_output *output;
    wl_list_for_each(output, &state->outputs, link) {
        if (output->name && strcmp(output->name, name) == 0)
            return output;
    }
    return NULL;
}

static struct grim_toplevel *find_toplevel(struct grim_state *state, const char *identifier) {
    struct grim_toplevel *toplevel;
    wl_list_for_each(toplevel, &state->toplevels, link) {
        if (toplevel->identifier && strcmp(toplevel->identifier, identifier) == 0)
            return toplevel;
    }
    return NULL;
}

static struct grim_capture *create_output_capture(struct grim_state *state, struct grim_output *output, bool with_cursor) {
    struct grim_capture *capture = calloc(1, sizeof(*capture));
    capture->state = state;
    capture->output = output;
    capture->transform = output->transform;
    capture->logical_geometry = output->logical_geometry;
    capture->source_label = output->name ? strdup(output->name) : strdup("output");
    wl_list_insert(&state->captures, &capture->link);

    if (state->ext_output_image_capture_source_manager) {
        uint32_t options = with_cursor ? EXT_IMAGE_COPY_CAPTURE_MANAGER_V1_OPTIONS_PAINT_CURSORS : 0;
        struct ext_image_capture_source_v1 *source =
            ext_output_image_capture_source_manager_v1_create_source(state->ext_output_image_capture_source_manager, output->wl_output);
        capture->ext_image_copy_capture_session =
            ext_image_copy_capture_manager_v1_create_session(state->ext_image_copy_capture_manager, source, options);
        ext_image_copy_capture_session_v1_add_listener(capture->ext_image_copy_capture_session,
            &ext_image_copy_capture_session_listener, capture);
        ext_image_capture_source_v1_destroy(source);
    } else {
        capture->screencopy_frame = zwlr_screencopy_manager_v1_capture_output(state->screencopy_manager, with_cursor, output->wl_output);
        zwlr_screencopy_frame_v1_add_listener(capture->screencopy_frame, &screencopy_frame_listener, capture);
    }
    return capture;
}

static struct grim_capture *create_toplevel_capture(struct grim_state *state, struct grim_toplevel *toplevel, const char *file_path, bool with_cursor) {
    struct grim_capture *capture = calloc(1, sizeof(*capture));
    capture->state = state;
    capture->file_path = strdup(file_path);
    capture->source_label = strdup(toplevel->identifier ? toplevel->identifier : "toplevel");
    wl_list_insert(&state->captures, &capture->link);

    uint32_t options = with_cursor ? EXT_IMAGE_COPY_CAPTURE_MANAGER_V1_OPTIONS_PAINT_CURSORS : 0;
    struct ext_image_capture_source_v1 *source =
        ext_foreign_toplevel_image_capture_source_manager_v1_create_source(state->ext_foreign_toplevel_image_capture_source_manager, toplevel->handle);
    capture->ext_image_copy_capture_session =
        ext_image_copy_capture_manager_v1_create_session(state->ext_image_copy_capture_manager, source, options);
    ext_image_copy_capture_session_v1_add_listener(capture->ext_image_copy_capture_session,
        &ext_image_copy_capture_session_listener, capture);
    ext_image_capture_source_v1_destroy(source);
    return capture;
}

static int dispatch_until_done(struct grim_state *state) {
    const size_t n_pending = wl_list_length(&state->captures);
    while (!state->failed && state->n_done < n_pending) {
        if (wl_display_dispatch(state->display) == -1) {
            set_errorf(state, "wayland dispatch failed");
            return -1;
        }
    }
    return state->failed ? -1 : 0;
}

static int write_image_to_png(pixman_image_t *image, const char *file_path, char **error) {
    FILE *file = fopen(file_path, "wb");
    if (!file) {
        if (error)
            asprintf(error, "Failed to open %s: %s", file_path, strerror(errno));
        return -1;
    }
    int rc = write_to_png_stream(image, file, 6);
    fclose(file);
    if (rc != 0) {
        if (error)
            asprintf(error, "Failed to write png %s", file_path);
        return -1;
    }
    return 0;
}

static int write_capture_png(struct grim_capture *capture, char **error) {
    pixman_image_t *image = create_image_from_buffer(capture->buffer);
    if (!image) {
        if (error)
            asprintf(error, "Failed to convert capture buffer to image");
        return -1;
    }
    const int rc = write_image_to_png(image, capture->file_path, error);
    pixman_image_unref(image);
    return rc;
}

int qs_capture_capture_output(const char *output_name, const char *file_path, bool with_cursor, char **error) {
    struct grim_state state;
    struct grim_box *geometry = NULL;
    pixman_image_t *image = NULL;
    double scale = 1.0;
    int rc = -1;

    if (init_state(&state, false) != 0)
        goto cleanup;

    if (output_name && output_name[0] != '\0') {
        struct grim_output *selected = find_output_by_name(&state, output_name);
        if (!selected) {
            set_errorf(&state, "unknown output '%s'", output_name);
            goto cleanup;
        }
        geometry = calloc(1, sizeof(*geometry));
        *geometry = selected->logical_geometry;
    }

    struct grim_output *output;
    wl_list_for_each(output, &state.outputs, link) {
        if (geometry && !intersect_box(geometry, &output->logical_geometry))
            continue;
        if (output->logical_scale > scale)
            scale = output->logical_scale;
        create_output_capture(&state, output, with_cursor);
    }

    if (wl_list_empty(&state.captures)) {
        set_errorf(&state, "no outputs selected for capture");
        goto cleanup;
    }
    if (dispatch_until_done(&state) != 0)
        goto cleanup;
    if (!geometry) {
        geometry = calloc(1, sizeof(*geometry));
        get_capture_layout_extents(&state, geometry);
    }
    image = render(&state, geometry, scale);
    if (!image) {
        set_errorf(&state, "failed to render output image");
        goto cleanup;
    }
    if (write_image_to_png(image, file_path, error) != 0)
        goto cleanup;
    rc = 0;

cleanup:
    if (rc != 0 && error && !*error && state.error_message)
        *error = strdup(state.error_message);
    if (image)
        pixman_image_unref(image);
    free(geometry);
    free(state.error_message);
    cleanup_state(&state);
    return rc;
}

int qs_capture_capture_region(int32_t x, int32_t y, int32_t width, int32_t height, double scale, const char *file_path, bool with_cursor, char **error) {
    struct grim_state state;
    struct grim_box geometry = { .x = x, .y = y, .width = width, .height = height };
    pixman_image_t *image = NULL;
    int rc = -1;

    if (init_state(&state, false) != 0)
        goto cleanup;

    struct grim_output *output;
    wl_list_for_each(output, &state.outputs, link) {
        if (!intersect_box(&geometry, &output->logical_geometry))
            continue;
        create_output_capture(&state, output, with_cursor);
    }

    if (wl_list_empty(&state.captures)) {
        set_errorf(&state, "region does not intersect any outputs");
        goto cleanup;
    }
    if (dispatch_until_done(&state) != 0)
        goto cleanup;
    image = render(&state, &geometry, scale > 0 ? scale : 1.0);
    if (!image) {
        set_errorf(&state, "failed to render region image");
        goto cleanup;
    }
    if (write_image_to_png(image, file_path, error) != 0)
        goto cleanup;
    rc = 0;

cleanup:
    if (rc != 0 && error && !*error && state.error_message)
        *error = strdup(state.error_message);
    if (image)
        pixman_image_unref(image);
    free(state.error_message);
    cleanup_state(&state);
    return rc;
}

int qs_capture_capture_toplevel(const char *identifier, const char *file_path, bool with_cursor, char **error) {
    qs_capture_toplevel_request request = {
        .identifier = identifier,
        .file_path = file_path,
    };
    size_t completedCount = 0;
    return qs_capture_capture_toplevel_batch(&request, 1, with_cursor, &completedCount, error);
}

int qs_capture_capture_toplevel_batch(const qs_capture_toplevel_request *requests, size_t request_count, bool with_cursor, size_t *completed_count, char **error) {
    struct grim_state state;
    int rc = -1;
    if (completed_count)
        *completed_count = 0;

    if (init_state(&state, true) != 0)
        goto cleanup;

    for (size_t index = 0; index < request_count; index += 1) {
        const qs_capture_toplevel_request *request = &requests[index];
        struct grim_toplevel *toplevel = find_toplevel(&state, request->identifier);
        if (!toplevel) {
            set_errorf(&state, "cannot find toplevel '%s'", request->identifier);
            goto cleanup;
        }
        create_toplevel_capture(&state, toplevel, request->file_path, with_cursor);
    }

    if (dispatch_until_done(&state) != 0)
        goto cleanup;

    struct grim_capture *capture;
    wl_list_for_each(capture, &state.captures, link) {
        if (write_capture_png(capture, error) != 0)
            goto cleanup;
        if (completed_count)
            *completed_count += 1;
    }

    rc = 0;

cleanup:
    if (rc != 0 && error && !*error && state.error_message)
        *error = strdup(state.error_message);
    free(state.error_message);
    cleanup_state(&state);
    return rc;
}

void qs_capture_free_error(char *error) {
    free(error);
}
