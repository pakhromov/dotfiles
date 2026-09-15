#include <errno.h>
#include <pixman.h>
#include <spng.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wayland-client-core.h>
#include <wayland-client-protocol.h>

#include "dulcepan.h"

static pixman_format_code_t shm_to_pixman(enum wl_shm_format shm_format) {
	struct {
		enum wl_shm_format shm;
		pixman_format_code_t pixman;
	} formats[] = {
#if DP_BIG_ENDIAN
		{WL_SHM_FORMAT_ARGB8888, PIXMAN_b8g8r8a8},
		{WL_SHM_FORMAT_XRGB8888, PIXMAN_b8g8r8x8},
		{WL_SHM_FORMAT_ABGR8888, PIXMAN_r8g8b8a8},
		{WL_SHM_FORMAT_XBGR8888, PIXMAN_r8g8b8x8},
		{WL_SHM_FORMAT_BGRA8888, PIXMAN_a8r8g8b8},
		{WL_SHM_FORMAT_BGRX8888, PIXMAN_x8r8g8b8},
		{WL_SHM_FORMAT_RGBA8888, PIXMAN_a8b8g8r8},
		{WL_SHM_FORMAT_RGBX8888, PIXMAN_x8b8g8r8},
#else
		{WL_SHM_FORMAT_RGB332, PIXMAN_r3g3b2},
		{WL_SHM_FORMAT_BGR233, PIXMAN_b2g3r3},
		{WL_SHM_FORMAT_ARGB4444, PIXMAN_a4r4g4b4},
		{WL_SHM_FORMAT_XRGB4444, PIXMAN_x4r4g4b4},
		{WL_SHM_FORMAT_ABGR4444, PIXMAN_a4b4g4r4},
		{WL_SHM_FORMAT_XBGR4444, PIXMAN_x4b4g4r4},
		{WL_SHM_FORMAT_ARGB1555, PIXMAN_a1r5g5b5},
		{WL_SHM_FORMAT_XRGB1555, PIXMAN_x1r5g5b5},
		{WL_SHM_FORMAT_ABGR1555, PIXMAN_a1b5g5r5},
		{WL_SHM_FORMAT_XBGR1555, PIXMAN_x1b5g5r5},
		{WL_SHM_FORMAT_RGB565, PIXMAN_r5g6b5},
		{WL_SHM_FORMAT_BGR565, PIXMAN_b5g6r5},
		{WL_SHM_FORMAT_RGB888, PIXMAN_r8g8b8},
		{WL_SHM_FORMAT_BGR888, PIXMAN_b8g8r8},
		{WL_SHM_FORMAT_ARGB8888, PIXMAN_a8r8g8b8},
		{WL_SHM_FORMAT_XRGB8888, PIXMAN_x8r8g8b8},
		{WL_SHM_FORMAT_ABGR8888, PIXMAN_a8b8g8r8},
		{WL_SHM_FORMAT_XBGR8888, PIXMAN_x8b8g8r8},
		{WL_SHM_FORMAT_BGRA8888, PIXMAN_b8g8r8a8},
		{WL_SHM_FORMAT_BGRX8888, PIXMAN_b8g8r8x8},
		{WL_SHM_FORMAT_RGBA8888, PIXMAN_r8g8b8a8},
		{WL_SHM_FORMAT_RGBX8888, PIXMAN_r8g8b8x8},
		{WL_SHM_FORMAT_ARGB2101010, PIXMAN_a2r10g10b10},
		{WL_SHM_FORMAT_ABGR2101010, PIXMAN_a2b10g10r10},
		{WL_SHM_FORMAT_XRGB2101010, PIXMAN_x2r10g10b10},
		{WL_SHM_FORMAT_XBGR2101010, PIXMAN_x2b10g10r10},
#endif
	};
	for (size_t i = 0; i < sizeof(formats) / sizeof(*formats); i++) {
		if (formats[i].shm == shm_format) {
			return formats[i].pixman;
		}
	}
	return 0;
}

static void write_png(FILE *fp, pixman_image_t *image, int width, int height, int level) {
	void *data = pixman_image_get_data(image);
	size_t size = (size_t)(width * height * 4);

	struct spng_ctx *spng_ctx = spng_ctx_new(SPNG_CTX_ENCODER);
	struct spng_ihdr ihdr = {
		.width = (uint32_t)width,
		.height = (uint32_t)height,
		.bit_depth = 8,
		.color_type = SPNG_COLOR_TYPE_TRUECOLOR_ALPHA,
	};

	spng_set_ihdr(spng_ctx, &ihdr);
	spng_set_png_file(spng_ctx, fp);
	spng_set_option(spng_ctx, SPNG_IMG_COMPRESSION_LEVEL, level);

	int err = spng_encode_image(spng_ctx, data, size, SPNG_FMT_PNG, SPNG_ENCODE_FINALIZE);
	if (err != 0) {
		dp_log_fatal("spng_encode_image() failed: %s", spng_strerror(err));
	}

	spng_ctx_free(spng_ctx);
}

static void write_ppm(FILE *fp, pixman_image_t *image, int width, int height) {
	uint32_t *data = pixman_image_get_data(image);
	size_t size = (size_t)(width * height);

	fprintf(fp, "P6\n%d %d\n255\n", width, height);
	for (size_t i = 0; i < size; i++) {
		uint32_t pixel = data[i];
		char bytes[3] = {
			(char)((pixel >> 0) & 0xff),
			(char)((pixel >> 8) & 0xff),
			(char)((pixel >> 16) & 0xff),
		};
		fwrite(bytes, 1, sizeof(bytes), fp);
	}
	fflush(fp);

	if (ferror(fp) != 0) {
		dp_log_fatal("Failed to write the output file\n");
	}
}

bool dp_format_supported(enum wl_shm_format format) {
	return shm_to_pixman(format) != 0;
}

void dp_save(struct dp_state *state) {
	struct dp_selection *selection = &state->selection;
	struct dp_output *output = selection->output;

	if (output == NULL || selection->width == 0 || selection->height == 0) {
		dp_log_fatal("The selection is empty");
	}

	pixman_format_code_t pixman_format = shm_to_pixman(output->frame_format);

	pixman_image_t *frame_image = pixman_image_create_bits(
			pixman_format, output->width, output->height, output->frame_data, output->width * 4);

	static const pixman_fixed_t cosines[] = {pixman_fixed_1, 0, -pixman_fixed_1, 0};

	pixman_fixed_t scale_x = (output->transform & WL_OUTPUT_TRANSFORM_FLIPPED) != 0
			? -pixman_fixed_1
			: pixman_fixed_1;
	pixman_fixed_t scale_y = pixman_fixed_1;

	struct pixman_transform frame_transform;
	pixman_transform_init_identity(&frame_transform);
	pixman_transform_translate(&frame_transform, NULL,
			-pixman_int_to_fixed(output->transformed_width) / 2,
			-pixman_int_to_fixed(output->transformed_height) / 2);
	pixman_transform_scale(&frame_transform, NULL, scale_x, scale_y);
	pixman_transform_rotate(&frame_transform, NULL, cosines[output->transform % 4],
			cosines[(output->transform + 1) % 4]);
	pixman_transform_translate(&frame_transform, NULL, pixman_int_to_fixed(output->width) / 2,
			pixman_int_to_fixed(output->height) / 2);

	pixman_image_set_transform(frame_image, &frame_transform);

	double scale = output->scale;

	int x = (int)round(selection->x * scale), y = (int)round(selection->y * scale);
	int width = (int)round((selection->x + selection->width) * scale) - x,
		height = (int)round((selection->y + selection->height) * scale) - y;

	pixman_image_t *out_image = pixman_image_create_bits(PIXMAN_a8b8g8r8, width, height, NULL, 0);
	pixman_image_composite32(
			PIXMAN_OP_SRC, frame_image, NULL, out_image, x, y, 0, 0, 0, 0, width, height);
	pixman_image_unref(frame_image);

	FILE *fp = NULL;
	if (state->output_path == NULL) {
		fp = stdout;
	} else {
		fp = fopen(state->output_path, "w");
		if (fp == NULL) {
			dp_log_fatal("Failed to open %s: %s", state->output_path, strerror(errno));
		}
	}

	switch (state->output_format) {
	case DP_FILE_UNKNOWN:
		abort(); // Unreachable
	case DP_FILE_PNG:
		write_png(fp, out_image, width, height, state->config.png_compression);
		break;
	case DP_FILE_PPM:
		write_ppm(fp, out_image, width, height);
		break;
	}

	pixman_image_unref(out_image);
	fclose(fp);
}
