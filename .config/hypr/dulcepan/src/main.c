#include <getopt.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client-core.h>
#include <wayland-client-protocol.h>
#include <xkbcommon/xkbcommon.h>

#include "cursor-shape-v1-protocol.h"
#include "dulcepan.h"
#include "ext-image-capture-source-v1-protocol.h"
#include "ext-image-copy-capture-v1-protocol.h"
#include "viewporter-protocol.h"
#include "wlr-layer-shell-unstable-v1-protocol.h"

static void registry_handle_global(void *data, struct wl_registry *registry, uint32_t name,
		const char *interface, uint32_t version) {
	struct dp_state *state = data;
	if (strcmp(interface, wl_compositor_interface.name) == 0) {
		if (version >= 2) {
			state->compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 2);
		}
	} else if (strcmp(interface, wl_subcompositor_interface.name) == 0) {
		state->subcompositor = wl_registry_bind(registry, name, &wl_subcompositor_interface, 1);
	} else if (strcmp(interface, wp_viewporter_interface.name) == 0) {
		state->viewporter = wl_registry_bind(registry, name, &wp_viewporter_interface, 1);
	} else if (strcmp(interface, wl_shm_interface.name) == 0) {
		state->shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
	} else if (strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0) {
		state->layer_shell = wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, 1);
	} else if (strcmp(interface, ext_output_image_capture_source_manager_v1_interface.name) == 0) {
		state->output_image_capture_source_manager = wl_registry_bind(
				registry, name, &ext_output_image_capture_source_manager_v1_interface, 1);
	} else if (strcmp(interface, ext_image_copy_capture_manager_v1_interface.name) == 0) {
		state->image_copy_capture_manager =
				wl_registry_bind(registry, name, &ext_image_copy_capture_manager_v1_interface, 1);
	} else if (strcmp(interface, wp_cursor_shape_manager_v1_interface.name) == 0) {
		state->cursor_shape_manager =
				wl_registry_bind(registry, name, &wp_cursor_shape_manager_v1_interface, 1);
	} else if (strcmp(interface, wl_output_interface.name) == 0) {
		if (state->initialized) {
			dp_log_fatal("An output was added after initialization");
		} else if (version < 4) {
			dp_log_fatal("An output has too low version (%d)", version);
		}
		struct wl_output *global = wl_registry_bind(registry, name, &wl_output_interface, 4);
		dp_output_create(state, name, global);
	} else if (strcmp(interface, wl_seat_interface.name) == 0) {
		struct wl_seat *global = wl_registry_bind(registry, name, &wl_seat_interface, 1);
		dp_seat_create(state, name, global);
	}
}

static void registry_handle_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
	struct dp_state *state = data;

	struct dp_output *output;
	wl_list_for_each (output, &state->outputs, link) {
		if (output->global_name == name) {
			dp_log_fatal("An output was removed");
		}
	}

	struct dp_seat *seat;
	wl_list_for_each (seat, &state->seats, link) {
		if (seat->global_name == name) {
			dp_seat_destroy(seat);
			return;
		}
	}
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_handle_global,
	.global_remove = registry_handle_global_remove,
};

static void run(struct dp_state *state) {
	struct wl_registry *registry = wl_display_get_registry(state->display);
	wl_registry_add_listener(registry, &registry_listener, state);

	// Collect globals
	wl_display_roundtrip(state->display);

	if (state->compositor == NULL) {
		dp_log_fatal("The compositor has no wl_compositor");
	} else if (state->subcompositor == NULL) {
		dp_log_fatal("The compositor has no wl_subcompositor");
	} else if (state->viewporter == NULL) {
		dp_log_fatal("The compositor has no wp_viewporter");
	} else if (state->shm == NULL) {
		dp_log_fatal("The compositor has no wl_shm");
	} else if (state->layer_shell == NULL) {
		dp_log_fatal("The compositor has no zwlr_layer_shell_v1");
	} else if (state->output_image_capture_source_manager == NULL) {
		dp_log_fatal("The compositor has no ext_output_image_capture_source_manager_v1");
	} else if (state->image_copy_capture_manager == NULL) {
		dp_log_fatal("The compositor has no ext_image_copy_capture_manager_v1");
	}

	if (wl_list_empty(&state->outputs)) {
		dp_log_fatal("No outputs found");
	} else if (wl_list_empty(&state->seats)) {
		dp_log_fatal("No seats found");
	}

	state->initialized = true;

	struct dp_output *output;
	wl_list_for_each (output, &state->outputs, link) {
		while (!output->initialized && wl_display_dispatch(state->display) != -1) {
			// Wait for output to fully initialize
		}
	}

	if (state->config.persistence) {
		dp_persistent_load(state);
	}

	wl_list_for_each (output, &state->outputs, link) {
		dp_output_redraw(output);
	}

	while (wl_display_dispatch(state->display) != -1 && state->status == DP_STATUS_RUNNING) {
		// Wait
	}

	if (state->status == DP_STATUS_SAVED) {
		// Hide everything before saving
		wl_list_for_each (output, &state->outputs, link) {
			dp_output_hide_surface(output);
		}
		wl_display_flush(state->display);

		dp_save(state);
	}

	if (state->config.persistence) {
		dp_persistent_save(state);
	}

	struct dp_seat *seat, *seat_tmp;
	wl_list_for_each_safe (seat, seat_tmp, &state->seats, link) {
		dp_seat_destroy(seat);
	}

	struct dp_output *output_tmp;
	wl_list_for_each_safe (output, output_tmp, &state->outputs, link) {
		dp_output_destroy(output);
	}

	wl_compositor_destroy(state->compositor);
	wl_subcompositor_destroy(state->subcompositor);
	wp_viewporter_destroy(state->viewporter);
	wl_shm_destroy(state->shm);
	zwlr_layer_shell_v1_destroy(state->layer_shell);

	ext_output_image_capture_source_manager_v1_destroy(state->output_image_capture_source_manager);
	ext_image_copy_capture_manager_v1_destroy(state->image_copy_capture_manager);

	if (state->cursor_shape_manager) {
		wp_cursor_shape_manager_v1_destroy(state->cursor_shape_manager);
	}

	wl_registry_destroy(registry);
}

static void help(const char *prog) {
	fprintf(stderr,
			"Usage: %s [options]\n"
			"\n"
			"  -h           Show this help message and quit.\n"
			"  -C           Show cursors in the screenshot.\n"
			"  -c <path>    Specify the configuration file path.\n"
			"  -f <format>  Specify the output file format.\n"
			"  -o <path>    Specify the output file path.\n"
			"\n"
			"If the output file path is not specified, the resuling image will be printed to\n"
			"the standard output, which is expected to not be a terminal. If the output file\n"
			"format is not specified, it is guessed from the output file path if it's\n"
			"specified, and assumed to be PNG otherwise.\n"
			"\n"
			"Supported formats: png, ppm.\n"
			"\n"
			"Use the left or right mouse button to select a part of the output. A selection\n"
			"can also be moved and resized with the left mouse button. Clicking the middle\n"
			"mouse button toggles the selection of the entire output.\n",
			prog);
}

int main(int argc, char **argv) {
	struct dp_state state = {0};

	const char *config_path = NULL;

	int opt;
	while ((opt = getopt(argc, argv, "hCc:f:o:")) != -1) {
		switch (opt) {
		case 'h':
			help(argv[0]);
			return 0;
		case 'C':
			state.show_cursors = true;
			break;
		case 'c':
			config_path = optarg;
			break;
		case 'f':
			state.output_format = dp_ext_to_format(optarg);
			if (state.output_format == DP_FILE_UNKNOWN) {
				dp_log_fatal("Unknown format %s", optarg);
			}
			break;
		case 'o':
			state.output_path = optarg;
			break;
		default: // '?'
			help(argv[0]);
			return 1;
		}
	}

	if (state.output_path == NULL && isatty(STDOUT_FILENO)) {
		fprintf(stderr,
				"Refusing to run as the standard output is a terminal and there's no output file\n"
				"path specified.\n\n");
		help(argv[0]);
		exit(1);
	}

	if (state.output_format == DP_FILE_UNKNOWN) {
		if (state.output_path != NULL) {
			const char *ext = dp_ext_from_path(state.output_path);
			state.output_format = dp_ext_to_format(ext);
			if (state.output_format == DP_FILE_UNKNOWN) {
				dp_log_fatal("Unknown format of %s", state.output_path);
			}
		} else {
			// Default format
			state.output_format = DP_FILE_PNG;
		}
	}

	state.basedir_ctx = sfdo_basedir_ctx_create();

	dp_config_load(&state, config_path);

	wl_list_init(&state.outputs);
	wl_list_init(&state.seats);

	state.display = wl_display_connect(NULL);
	if (state.display == NULL) {
		dp_log_fatal("Failed to connect to a Wayland compositor");
	}

	state.xkb_context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);

	struct dp_config *config = &state.config;
	if (config->border_gradient != DP_BORDER_GRADIENT_NONE) {
		state.border_pattern = cairo_pattern_create_linear(0, 0, 1, 0);
		cairo_pattern_add_color_stop_rgba(state.border_pattern, 0, config->border_color[0],
				config->border_color[1], config->border_color[2], config->border_color[3]);
		cairo_pattern_add_color_stop_rgba(state.border_pattern, 1,
				config->border_secondary_color[0], config->border_secondary_color[1],
				config->border_secondary_color[2], config->border_secondary_color[3]);

		switch (config->border_gradient) {
		case DP_BORDER_GRADIENT_NONE:
			abort(); // Unreachable
		case DP_BORDER_GRADIENT_LINEAR:
			if (config->animation_duration != 0) {
				state.time_multiplier = DP_PI * 2.0 / config->animation_duration;
			} else {
				dp_matrix_compute_linear(&state.precomputed_linear_matrix, config->gradient_angle);
			}
			break;
		case DP_BORDER_GRADIENT_LOOP:
			cairo_pattern_set_extend(state.border_pattern, CAIRO_EXTEND_REFLECT);
			state.loop_step_scale = 1.0 / config->loop_step;
			if (config->animation_duration != 0) {
				state.time_multiplier = 2.0 / config->animation_duration;
			}
			break;
		}
	}

	run(&state);

	dp_config_finish(&state);

	cairo_pattern_destroy(state.border_pattern);

	xkb_context_unref(state.xkb_context);

	wl_display_disconnect(state.display);

	sfdo_basedir_ctx_destroy(state.basedir_ctx);

	if (state.status == DP_STATUS_QUIT) {
		return 1;
	}

	return 0;
}
