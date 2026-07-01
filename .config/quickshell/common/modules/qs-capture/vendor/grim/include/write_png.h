#ifndef QS_CAPTURE_WRITE_PNG_H
#define QS_CAPTURE_WRITE_PNG_H

#include <pixman.h>
#include <stdio.h>

int write_to_png_stream(pixman_image_t *image, FILE *stream, int comp_level);

#endif
