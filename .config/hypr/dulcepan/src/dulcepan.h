#ifndef DULCEPAN_H
#define DULCEPAN_H

#include <cairo.h>
#include <sfdo-basedir.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdnoreturn.h>
#include <wayland-client-protocol.h>
#include <wayland-util.h>
#include <xkbcommon/xkbcommon.h>

#define DP_PI 3.14159265358979323846
// sqrt(2) / 2
#define DP_SQRT2_2 0.7071067811865476

// Per-output
#define DP_SWAPCHAIN_LEN 2

enum dp_status {
	DP_STATUS_RUNNING,
	DP_STATUS_SAVED,
	DP_STATUS_QUIT,
};

struct dp_buffer {
	struct wl_buffer *wl_buffer;
	cairo_t *cairo;
	cairo_surface_t *cairo_surface;
	void *data;
	size_t size;
	bool used;
};

struct dp_output {
	struct dp_state *state;

	uint32_t global_name;
	struct wl_output *wl_output;

	char *name;

	struct wl_surface *main_surface;
	struct zwlr_layer_surface_v1 *main_layer_surface;
	struct wp_viewport *main_viewport;

	struct wl_surface *select_surface;
	struct wl_subsurface *select_subsurface;
	struct wp_viewport *select_viewport;

	int width, height;
	int32_t transform;
	bool has_geom;
	int transformed_width, transformed_height;

	int effective_width, effective_height;
	bool initialized;

	double scale;

	struct wl_callback *redraw_callback;
	bool needs_redraw;

	struct ext_image_capture_source_v1 *source;
	struct ext_image_copy_capture_session_v1 *session;

	struct ext_image_copy_capture_frame_v1 *frame;
	enum wl_shm_format frame_format;
	bool has_frame_format;

	struct wl_buffer *frame_buffer;
	void *frame_data;
	size_t frame_size;

	bool captured;

	// wl_buffer is NULL if uninitialized
	struct dp_buffer swapchain[DP_SWAPCHAIN_LEN];

	struct wl_list link;
};

struct dp_seat {
	struct dp_state *state;

	uint32_t global_name;
	struct wl_seat *wl_seat;

	struct wl_keyboard *keyboard;
	struct wl_pointer *pointer;

	struct xkb_keymap *xkb_keymap;
	struct xkb_state *xkb_state;

	uint32_t pointer_serial;
	struct wp_cursor_shape_device_v1 *cursor_shape_device;

	// The output the pointer is on
	struct dp_output *ptr_output;
	// In buffer space
	double ptr_x, ptr_y;

	struct wl_list link;
};

enum dp_selection_action {
	DP_SELECTION_ACTION_NONE,
	DP_SELECTION_ACTION_RESIZING,
	DP_SELECTION_ACTION_MOVING,
};

enum dp_resize_edges {
	DP_EDGE_NONE = 0,

	DP_EDGE_TOP = 1 << 0,
	DP_EDGE_BOTTOM = 1 << 1,
	DP_EDGE_LEFT = 1 << 2,
	DP_EDGE_RIGHT = 1 << 3,
};

struct dp_selection {
	struct dp_output *output; // May be NULL
	double x, y, width, height;

	enum dp_selection_action action;
	bool action_active;
	// Pointer offset to apply during movement
	double ptr_off_x, ptr_off_y;
	int resize_edges;
	// Resize anchor
	double resize_x, resize_y;

	// Used for toggling
	struct {
		// If not NULL, the current output has been selected via the dedicated
		// action rather than by persistent state loading or manual resizing
		struct dp_output *output;
		double x, y, width, height;
	} last_partial;
};

enum dp_file_format {
	DP_FILE_UNKNOWN = 0,

	DP_FILE_PNG,
	DP_FILE_PPM,
};

enum dp_border_gradient {
	DP_BORDER_GRADIENT_NONE,
	DP_BORDER_GRADIENT_LINEAR,
	DP_BORDER_GRADIENT_LOOP,
};

struct dp_keybinding {
	xkb_keysym_t *syms;
	size_t n_syms;
};

struct dp_config {
	// RGBA, not premultiplied
	float unselected_color[4];
	float selected_color[4];
	float border_color[4];
	float border_secondary_color[4];

	struct dp_keybinding quit_kb;
	struct dp_keybinding save_kb;

	int border_size; // 0 if disabled
	enum dp_border_gradient border_gradient;
	double gradient_angle; // In radians
	int loop_step;
	int animation_duration; // In milliseconds

	int png_compression;
	bool quick_select;
	bool persistence;
};

struct dp_state {
	enum dp_status status;

	struct wl_display *display;
	struct wl_registry *registry;

	struct wl_compositor *compositor;
	struct wl_subcompositor *subcompositor;
	struct wp_viewporter *viewporter;
	struct wl_shm *shm;
	struct zwlr_layer_shell_v1 *layer_shell;

	struct ext_output_image_capture_source_manager_v1 *output_image_capture_source_manager;
	struct ext_image_copy_capture_manager_v1 *image_copy_capture_manager;

	// Optional
	struct wp_cursor_shape_manager_v1 *cursor_shape_manager;

	bool initialized;

	struct xkb_context *xkb_context;

	struct sfdo_basedir_ctx *basedir_ctx;

	char *persistent_path;

	struct wl_list outputs;
	struct wl_list seats;

	struct dp_selection selection;

	struct dp_config config;
	const char *output_path; // May be NULL
	enum dp_file_format output_format;

	bool show_cursors;

	cairo_pattern_t *border_pattern;
	cairo_matrix_t precomputed_linear_matrix;
	double loop_step_scale;
	double time_multiplier;
};

void dp_config_load(struct dp_state *state, const char *user_path);
void dp_config_finish(struct dp_state *state);

// When done, data must be unmapped
struct wl_buffer *dp_buffer_create(struct dp_state *state, int32_t width, int32_t height,
		int32_t stride, uint32_t format, void **data, size_t *size);

void dp_output_create(struct dp_state *state, uint32_t name, struct wl_output *wl_output);
void dp_output_destroy(struct dp_output *output);

void dp_output_redraw(struct dp_output *output);

void dp_output_hide_surface(struct dp_output *output);

void dp_seat_create(struct dp_state *state, uint32_t name, struct wl_seat *wl_seat);
void dp_seat_destroy(struct dp_seat *seat);

void dp_select_start_interactive(struct dp_selection *selection, struct dp_output *output, double x,
		double y, bool modify_existing);
void dp_select_stop_interactive(struct dp_selection *selection);

void dp_select_notify_pointer_position(
		struct dp_selection *selection, struct dp_output *output, double x, double y);

void dp_select_toggle_whole(struct dp_selection *selection, struct dp_output *output);

bool dp_format_supported(enum wl_shm_format format);

void dp_save(struct dp_state *state);

void dp_log_error(const char *fmt, ...);
noreturn void dp_log_fatal(const char *fmt, ...);

void *dp_zalloc(size_t size);
char *dp_strdup(const char *str);

void dp_matrix_compute_linear(cairo_matrix_t *matrix, double angle);

const char *dp_ext_from_path(const char *path);
enum dp_file_format dp_ext_to_format(const char *ext);

void dp_persistent_load(struct dp_state *state);
void dp_persistent_save(struct dp_state *state);

#endif
