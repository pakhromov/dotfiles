#include <assert.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>
#include <wayland-client-protocol.h>

#include "dulcepan.h"
#include "ext-image-capture-source-v1-protocol.h"
#include "ext-image-copy-capture-v1-protocol.h"
#include "viewporter-protocol.h"
#include "wlr-layer-shell-unstable-v1-protocol.h"

// Initialiation flow:
// - Wait for the output configuration, compute transformed size
// - Create a source, a session, and a frame
// - Create and prepare surfaces
// - Wait for the session information, capture the frame
// - Wait for the frame
// - Commit the main surface, wait for a configure event
// - Save effective size, put the frame buffer on the main surface
// - The output is initialized

static void layer_surface_handle_configure(void *data, struct zwlr_layer_surface_v1 *layer_surface,
		uint32_t serial, uint32_t width, uint32_t height) {
	struct dp_output *output = data;

	if (!output->captured) {
		// Ignore configures that came too early
		return;
	}

	// Thanks layer-shell
	int i_width = (int)width, i_height = (int)height;

	zwlr_layer_surface_v1_ack_configure(layer_surface, serial);

	if (output->initialized) {
		if (i_width != output->effective_width || i_height != output->effective_height) {
			dp_log_fatal("Output %s: layer surface size has changed: %dx%d => %dx%d", output->name,
					output->effective_width, output->effective_height, i_width, i_height);
		}

		wl_surface_commit(output->main_surface);
		return;
	}

	output->effective_width = (int)width;
	output->effective_height = (int)height;

	output->scale = (double)output->transformed_width / output->effective_width;

	wp_viewport_set_destination(
			output->main_viewport, output->effective_width, output->effective_height);
	wp_viewport_set_destination(
			output->select_viewport, output->effective_width, output->effective_height);

	wl_surface_attach(output->main_surface, output->frame_buffer, 0, 0);
	wl_surface_commit(output->main_surface);

	output->initialized = true;
}

static void layer_surface_handle_closed(void *data, struct zwlr_layer_surface_v1 *layer_surface) {
	struct dp_output *output = data;
	dp_log_fatal("Output %s: a layer surface was closed", output->name);
}

static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
	.configure = layer_surface_handle_configure,
	.closed = layer_surface_handle_closed,
};

static void session_handle_buffer_size(void *data,
		struct ext_image_copy_capture_session_v1 *session, uint32_t width, uint32_t height) {
	struct dp_output *output = data;
	if ((int32_t)width != output->width || (int32_t)height != output->height) {
		dp_log_fatal("Output/buffer size mismatch: mode=%" PRIi32 "x%" PRIi32 ", buffer=%" PRIu32
					 "x%" PRIu32,
				output->width, output->height, width, height);
	}
}

static void session_handle_shm_format(
		void *data, struct ext_image_copy_capture_session_v1 *session, uint32_t format) {
	struct dp_output *output = data;
	if (!output->has_frame_format && dp_format_supported(format)) {
		output->frame_format = format;
		output->has_frame_format = true;
	}
}

static void session_handle_dmabuf_device(
		void *data, struct ext_image_copy_capture_session_v1 *session, struct wl_array *device) {
	// Ignored
}

static void session_handle_dmabuf_format(void *data,
		struct ext_image_copy_capture_session_v1 *session, uint32_t format,
		struct wl_array *modifiers) {
	// Ignored
}

static void session_handle_done(void *data, struct ext_image_copy_capture_session_v1 *session) {
	struct dp_output *output = data;
	if (!output->has_frame_format) {
		dp_log_fatal("Output %s: no suitable SHM format", output->name);
	}

	output->frame_buffer = dp_buffer_create(output->state, output->width, output->height,
			output->width * 4, output->frame_format, &output->frame_data, &output->frame_size);

	ext_image_copy_capture_frame_v1_attach_buffer(output->frame, output->frame_buffer);
	ext_image_copy_capture_frame_v1_damage_buffer(output->frame, 0, 0, output->width, output->height);
	ext_image_copy_capture_frame_v1_capture(output->frame);
}

static void session_handle_stopped(void *data, struct ext_image_copy_capture_session_v1 *session) {
	// Ignored
}

static const struct ext_image_copy_capture_session_v1_listener session_listener = {
	.buffer_size = session_handle_buffer_size,
	.shm_format = session_handle_shm_format,
	.dmabuf_device = session_handle_dmabuf_device,
	.dmabuf_format = session_handle_dmabuf_format,
	.done = session_handle_done,
	.stopped = session_handle_stopped,
};

static void frame_handle_transform(
		void *data, struct ext_image_copy_capture_frame_v1 *frame, uint32_t transform) {
	// Ignored
}

static void frame_handle_damage(void *data, struct ext_image_copy_capture_frame_v1 *frame,
		int32_t x, int32_t y, int32_t width, int32_t height) {
	// Ignored
}

static void frame_handle_presentation_time(void *data,
		struct ext_image_copy_capture_frame_v1 *frame, uint32_t tv_sec_hi, uint32_t tv_sec_lo,
		uint32_t tv_nsec) {
	// Ignored
}

static void frame_handle_ready(void *data, struct ext_image_copy_capture_frame_v1 *frame) {
	struct dp_output *output = data;

	ext_image_copy_capture_frame_v1_destroy(output->frame);
	output->frame = NULL;

	output->captured = true;

	wl_surface_commit(output->main_surface);
}

static void frame_handle_failed(
		void *data, struct ext_image_copy_capture_frame_v1 *frame, uint32_t reason) {
	// Shouldn't happen?
	struct dp_output *output = data;
	dp_log_fatal("Output %s: failed to capture a frame, reason %" PRIu32, output->name, reason);
}

static const struct ext_image_copy_capture_frame_v1_listener frame_listener = {
	.transform = frame_handle_transform,
	.damage = frame_handle_damage,
	.presentation_time = frame_handle_presentation_time,
	.ready = frame_handle_ready,
	.failed = frame_handle_failed,
};

static void buffer_handle_release(void *data, struct wl_buffer *wl_buffer) {
	struct dp_buffer *buffer = data;
	buffer->used = false;
}

static const struct wl_buffer_listener buffer_listener = {
	.release = buffer_handle_release,
};

static void init_buffer(struct dp_output *output, struct dp_buffer *buffer) {
	int stride = output->transformed_width * 4;

	buffer->wl_buffer =
			dp_buffer_create(output->state, output->transformed_width, output->transformed_height,
					stride, WL_SHM_FORMAT_ARGB8888, &buffer->data, &buffer->size);
	buffer->cairo_surface = cairo_image_surface_create_for_data(buffer->data, CAIRO_FORMAT_ARGB32,
			output->transformed_width, output->transformed_height, stride);
	buffer->cairo = cairo_create(buffer->cairo_surface);

	wl_buffer_add_listener(buffer->wl_buffer, &buffer_listener, buffer);
}

static void output_handle_geometry(void *data, struct wl_output *wl_output, int32_t x, int32_t y,
		int32_t phys_width, int32_t phys_height, int32_t subpixel, const char *make,
		const char *model, int32_t transform) {
	struct dp_output *output = data;

	if (output->has_geom) {
		if (transform != output->transform) {
			dp_log_fatal("Output %s: transform has changed: %d (%#x) => %d (%#x)", output->name,
					output->transform, output->transform, transform, transform);
		}
	}

	output->transform = transform;
}

static void output_handle_mode(void *data, struct wl_output *wl_output, uint32_t flags,
		int32_t width, int32_t height, int32_t refresh) {
	if ((flags & WL_OUTPUT_MODE_CURRENT) == 0) {
		return;
	}

	struct dp_output *output = data;

	if (output->has_geom) {
		if (width != output->width || height != output->height) {
			dp_log_fatal("Output %s: mode has changed: %dx%d => %dx%d", output->name, output->width,
					output->height, width, height);
		}
	}

	output->width = width;
	output->height = height;
}

static void output_handle_done(void *data, struct wl_output *wl_output) {
	struct dp_output *output = data;

	if (output->has_geom) {
		return;
	}

	assert(output->name != NULL);

	assert(output->width > 0 && output->height > 0);
	if ((output->transform & WL_OUTPUT_TRANSFORM_90) != 0) {
		output->transformed_width = output->height;
		output->transformed_height = output->width;
	} else {
		output->transformed_width = output->width;
		output->transformed_height = output->height;
	}

	output->has_geom = true;

	struct dp_state *state = output->state;

	output->source = ext_output_image_capture_source_manager_v1_create_source(
			state->output_image_capture_source_manager, output->wl_output);

	output->session = ext_image_copy_capture_manager_v1_create_session(
			state->image_copy_capture_manager, output->source,
			state->show_cursors ? EXT_IMAGE_COPY_CAPTURE_MANAGER_V1_OPTIONS_PAINT_CURSORS : 0);
	ext_image_copy_capture_session_v1_add_listener(output->session, &session_listener, output);

	output->frame = ext_image_copy_capture_session_v1_create_frame(output->session);
	ext_image_copy_capture_frame_v1_add_listener(output->frame, &frame_listener, output);

	output->main_surface = wl_compositor_create_surface(state->compositor);
	output->main_layer_surface = zwlr_layer_shell_v1_get_layer_surface(state->layer_shell,
			output->main_surface, output->wl_output, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "dulcepan");
	output->main_viewport = wp_viewporter_get_viewport(state->viewporter, output->main_surface);

	wl_surface_set_buffer_transform(output->main_surface, output->transform);

	// The input region of the main surface is left at the default (infinite): some
	// compositors don't descend into subsurfaces when hit-testing layer surfaces, so the
	// pointer input is handled by the main surface instead of the select one.
	wl_surface_set_user_data(output->main_surface, output);

	zwlr_layer_surface_v1_add_listener(output->main_layer_surface, &layer_surface_listener, output);

	zwlr_layer_surface_v1_set_anchor(output->main_layer_surface,
			ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
					ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
	zwlr_layer_surface_v1_set_keyboard_interactivity(
			output->main_layer_surface, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE);
	zwlr_layer_surface_v1_set_exclusive_zone(output->main_layer_surface, -1);

	output->select_surface = wl_compositor_create_surface(state->compositor);
	output->select_subsurface = wl_subcompositor_get_subsurface(
			state->subcompositor, output->select_surface, output->main_surface);
	output->select_viewport = wp_viewporter_get_viewport(state->viewporter, output->select_surface);
	wl_subsurface_set_desync(output->select_subsurface);

	struct wl_region *empty_region = wl_compositor_create_region(state->compositor);
	wl_surface_set_input_region(output->select_surface, empty_region);
	wl_region_destroy(empty_region);

	wl_surface_set_user_data(output->select_surface, output);
}

static void output_handle_scale(void *data, struct wl_output *wl_output, int32_t scale) {
	// Ignored
}

static void output_handle_name(void *data, struct wl_output *wl_output, const char *name) {
	struct dp_output *output = data;
	assert(output->name == NULL);
	output->name = dp_strdup(name);
}

static void output_handle_description(void *data, struct wl_output *wl_output, const char *name) {
	// Ignored
}

static const struct wl_output_listener output_listener = {
	.geometry = output_handle_geometry,
	.mode = output_handle_mode,
	.done = output_handle_done,
	.scale = output_handle_scale,
	.name = output_handle_name,
	.description = output_handle_description,
};

static void redraw(struct dp_output *output);

static void redraw_callback_handle_done(
		void *data, struct wl_callback *callback, uint32_t callback_data) {
	struct dp_output *output = data;
	wl_callback_destroy(output->redraw_callback);
	output->redraw_callback = NULL;
	if (output->needs_redraw) {
		redraw(output);
	}
}

static const struct wl_callback_listener redraw_callback_listener = {
	.done = redraw_callback_handle_done,
};

static inline void set_cairo_color(cairo_t *cairo, float color[static 4]) {
	cairo_set_source_rgba(cairo, color[0], color[1], color[2], color[3]);
}

static inline uint32_t get_time_msec(void) {
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	return (uint32_t)(now.tv_sec * 1000 + now.tv_nsec / 1000000);
}

static void setup_linear_gradient(
		cairo_t *cairo, struct dp_state *state, double x, double y, double width, double height) {
	struct dp_config *config = &state->config;

	cairo_matrix_t matrix;

	if (config->animation_duration != 0) {
		double angle = (double)get_time_msec() * state->time_multiplier;
		dp_matrix_compute_linear(&matrix, angle);
	} else {
		matrix = state->precomputed_linear_matrix;
	}

	cairo_matrix_scale(&matrix, 1.0 / width, 1.0 / height);
	cairo_matrix_translate(&matrix, -x, -y);

	cairo_pattern_set_matrix(state->border_pattern, &matrix);
	cairo_set_source(cairo, state->border_pattern);
}

static void setup_loop_gradient(
		cairo_t *cairo, struct dp_state *state, double x, double y, double width, double height) {
	struct dp_selection *selection = &state->selection;
	struct dp_config *config = &state->config;

	double offset = (x + y + (width + height) / 2.0) * state->loop_step_scale;
	if (config->animation_duration != 0) {
		offset += (double)get_time_msec() * state->time_multiplier;
	}

	double scale = state->loop_step_scale / selection->output->scale;

	cairo_matrix_t matrix;
	cairo_matrix_init(&matrix, scale, 0, 0, scale, fmod(offset, 2.0), 0);

	// Rotate by 45°
	cairo_matrix_t rotation;
	cairo_matrix_init(&rotation, -DP_SQRT2_2, DP_SQRT2_2, -DP_SQRT2_2, -DP_SQRT2_2, 0, 0);
	cairo_matrix_multiply(&matrix, &rotation, &matrix);

	cairo_pattern_set_matrix(state->border_pattern, &matrix);
	cairo_set_source(cairo, state->border_pattern);
}

static void redraw(struct dp_output *output) {
	assert(output->redraw_callback == NULL);

	struct dp_buffer *buffer = NULL;
	for (size_t i = 0; i < DP_SWAPCHAIN_LEN; i++) {
		struct dp_buffer *iter = &output->swapchain[i];
		if (!iter->used) {
			buffer = iter;
			break;
		}
	}
	if (buffer == NULL) {
		dp_log_error("Output %s: no free buffers in a swapchain\n", output->name);
		return;
	} else if (buffer->wl_buffer == NULL) {
		init_buffer(output, buffer);
	}
	buffer->used = true;

	output->needs_redraw = false;

	struct dp_state *state = output->state;
	struct dp_selection *selection = &state->selection;
	struct dp_config *config = &state->config;

	cairo_set_operator(buffer->cairo, CAIRO_OPERATOR_SOURCE);

	set_cairo_color(buffer->cairo, config->unselected_color);
	cairo_paint(buffer->cairo);

	if (output == selection->output) {
		double scale = output->scale;
		double x = round(selection->x * scale), y = round(selection->y * scale);
		double width = round((selection->x + selection->width) * scale) - x,
			   height = round((selection->y + selection->height) * scale) - y;

		int border_size = config->border_size;
		if (border_size != 0 && width != 0 && height != 0) {
			double scaled_size = border_size * scale;
			cairo_set_line_width(buffer->cairo, scaled_size);
			double off = scaled_size / 2.0;
			cairo_rectangle(
					buffer->cairo, x - off, y - off, width + scaled_size, height + scaled_size);

			switch (config->border_gradient) {
			case DP_BORDER_GRADIENT_NONE:
				set_cairo_color(buffer->cairo, config->border_color);
				break;
			case DP_BORDER_GRADIENT_LINEAR:
				setup_linear_gradient(buffer->cairo, state, x, y, width, height);
				break;
			case DP_BORDER_GRADIENT_LOOP:
				setup_loop_gradient(buffer->cairo, state, x, y, width, height);
				break;
			}

			cairo_stroke(buffer->cairo);

			if (config->border_gradient != DP_BORDER_GRADIENT_NONE &&
					config->animation_duration != 0) {
				bool whole = selection->x == 0 && selection->y == 0 &&
						selection->width == output->effective_width &&
						selection->height == output->effective_height;
				if (!whole) {
					// The border is animated and visible
					output->needs_redraw = true;
				}
			}
		}

		cairo_rectangle(buffer->cairo, x, y, width, height);
		set_cairo_color(buffer->cairo, config->selected_color);
		cairo_fill(buffer->cairo);
	}

	wl_surface_attach(output->select_surface, buffer->wl_buffer, 0, 0);
	wl_surface_damage(
			output->select_surface, 0, 0, output->effective_width, output->effective_height);

	wl_surface_commit(output->select_surface);

	// Some compositors don't schedule an output frame for a desync subsurface commit on its
	// own, which would leave the frame callback undelivered and stall all redraws. Damage the
	// parent surface and request the frame callback on it: the parent is a layer surface, which
	// every compositor renders and sends frame callbacks for.
	wl_surface_damage(
			output->main_surface, 0, 0, output->effective_width, output->effective_height);

	output->redraw_callback = wl_surface_frame(output->main_surface);
	wl_callback_add_listener(output->redraw_callback, &redraw_callback_listener, output);

	wl_surface_commit(output->main_surface);
}

void dp_output_redraw(struct dp_output *output) {
	if (output->redraw_callback != NULL) {
		output->needs_redraw = true;
		return;
	}
	redraw(output);
}

void dp_output_hide_surface(struct dp_output *output) {
	wl_surface_attach(output->main_surface, NULL, 0, 0);
	wl_surface_commit(output->main_surface);
}

void dp_output_create(struct dp_state *state, uint32_t name, struct wl_output *wl_output) {
	struct dp_output *output = dp_zalloc(sizeof(*output));
	output->state = state;
	output->global_name = name;
	output->wl_output = wl_output;

	wl_output_add_listener(output->wl_output, &output_listener, output);

	wl_list_insert(&state->outputs, &output->link);
}

void dp_output_destroy(struct dp_output *output) {
	wl_output_release(output->wl_output);

	free(output->name);

	assert(output->frame == NULL);
	wl_buffer_destroy(output->frame_buffer);
	munmap(output->frame_data, output->frame_size);

	if (output->redraw_callback != NULL) {
		wl_callback_destroy(output->redraw_callback);
	}

	for (size_t i = 0; i < DP_SWAPCHAIN_LEN; i++) {
		struct dp_buffer *buffer = &output->swapchain[i];
		if (buffer->wl_buffer != NULL) {
			wl_buffer_destroy(buffer->wl_buffer);
			cairo_destroy(buffer->cairo);
			cairo_surface_destroy(buffer->cairo_surface);
			munmap(buffer->data, buffer->size);
		}
	}

	ext_image_copy_capture_session_v1_destroy(output->session);
	ext_image_capture_source_v1_destroy(output->source);

	wl_subsurface_destroy(output->select_subsurface);
	wp_viewport_destroy(output->select_viewport);
	wl_surface_destroy(output->select_surface);

	zwlr_layer_surface_v1_destroy(output->main_layer_surface);
	wp_viewport_destroy(output->main_viewport);
	wl_surface_destroy(output->main_surface);

	wl_list_remove(&output->link);
	free(output);
}
