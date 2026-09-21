#include <assert.h>
#include <linux/input-event-codes.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client-protocol.h>
#include <xkbcommon/xkbcommon.h>

#include "cursor-shape-v1-protocol.h"
#include "dulcepan.h"

static void keyboard_handle_keymap(void *data, struct wl_keyboard *wl_keyboard,
		enum wl_keyboard_keymap_format format, int32_t fd, uint32_t size) {
	struct dp_seat *seat = data;

	void *keymap_buffer;
	size_t keymap_len;

	xkb_keymap_unref(seat->xkb_keymap);
	xkb_state_unref(seat->xkb_state);

	switch (format) {
	case WL_KEYBOARD_KEYMAP_FORMAT_NO_KEYMAP:
		seat->xkb_keymap = xkb_keymap_new_from_names(
				seat->state->xkb_context, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS);
		break;
	case WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1:
		keymap_len = size - 1;
		keymap_buffer = mmap(NULL, keymap_len, PROT_READ, MAP_PRIVATE, fd, 0);
		if (keymap_buffer == MAP_FAILED) {
			dp_log_fatal("mmap() for a keymap failed");
		}
		seat->xkb_keymap = xkb_keymap_new_from_buffer(seat->state->xkb_context, keymap_buffer,
				keymap_len, XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS);
		munmap(keymap_buffer, keymap_len);
		close(fd);
		break;
	}

	seat->xkb_state = xkb_state_new(seat->xkb_keymap);
}

static void keyboard_handle_enter(void *data, struct wl_keyboard *wl_keyboard, uint32_t serial,
		struct wl_surface *surface, struct wl_array *keys) {
	// Ignored
}

static void keyboard_handle_leave(
		void *data, struct wl_keyboard *wl_keyboard, uint32_t serial, struct wl_surface *surface) {
	// Ignored
}

static bool match_keybinding(struct dp_keybinding *kb, uint32_t sym) {
	for (size_t i = 0; i < kb->n_syms; i++) {
		if (sym == kb->syms[i]) {
			return true;
		}
	}
	return false;
}

static void keyboard_handle_key(void *data, struct wl_keyboard *wl_keyboard, uint32_t serial,
		uint32_t time_msec, uint32_t keycode, enum wl_keyboard_key_state key_state) {
	struct dp_seat *seat = data;
	if (key_state != WL_KEYBOARD_KEY_STATE_PRESSED) {
		return;
	}

	xkb_keysym_t keysym = xkb_state_key_get_one_sym(seat->xkb_state, keycode + 8);

	struct dp_state *state = seat->state;
	struct dp_config *config = &state->config;

	if (match_keybinding(&config->quit_kb, keysym)) {
		state->status = DP_STATUS_QUIT;
	} else if (match_keybinding(&config->save_kb, keysym)) {
		state->status = DP_STATUS_SAVED;
	}
}

static void keyboard_handle_modifiers(void *data, struct wl_keyboard *wl_keyboard, uint32_t serial,
		uint32_t depressed, uint32_t latched, uint32_t locked, uint32_t group) {
	struct dp_seat *seat = data;
	xkb_state_update_mask(seat->xkb_state, depressed, latched, locked, 0, 0, group);
}

static const struct wl_keyboard_listener keyboard_listener = {
	.keymap = keyboard_handle_keymap,
	.enter = keyboard_handle_enter,
	.leave = keyboard_handle_leave,
	.key = keyboard_handle_key,
	.modifiers = keyboard_handle_modifiers,
};

static enum wp_cursor_shape_device_v1_shape get_cursor_shape(struct dp_selection *selection) {
	switch (selection->action) {
	case DP_SELECTION_ACTION_NONE:
		break;
	case DP_SELECTION_ACTION_RESIZING:
		if (selection->width == 0 || selection->height == 0) {
			break;
		}
		switch (selection->resize_edges) {
		case DP_EDGE_TOP:
			return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_N_RESIZE;
		case DP_EDGE_TOP | DP_EDGE_LEFT:
			return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NW_RESIZE;
		case DP_EDGE_TOP | DP_EDGE_RIGHT:
			return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_NE_RESIZE;
		case DP_EDGE_BOTTOM:
			return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_S_RESIZE;
		case DP_EDGE_BOTTOM | DP_EDGE_LEFT:
			return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_SW_RESIZE;
		case DP_EDGE_BOTTOM | DP_EDGE_RIGHT:
			return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_SE_RESIZE;
		case DP_EDGE_LEFT:
			return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_W_RESIZE;
		case DP_EDGE_RIGHT:
			return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_E_RESIZE;
		}
		break;
	case DP_SELECTION_ACTION_MOVING:
		// XXX: this might have rounding issues but whatever
		if (selection->x == 0 && selection->y == 0 &&
				selection->width == selection->output->effective_width &&
				selection->height == selection->output->effective_height) {
			// Moving is impossible
			break;
		}
		return selection->action_active ? WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_GRABBING
										: WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_GRAB;
	}
	// The default cursor
	return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_CROSSHAIR;
}

static void update_cursor(struct dp_seat *seat) {
	if (seat->cursor_shape_device != NULL) {
		wp_cursor_shape_device_v1_set_shape(seat->cursor_shape_device, seat->pointer_serial,
				get_cursor_shape(&seat->state->selection));
	}
}

static void process_position(struct dp_seat *seat, wl_fixed_t x, wl_fixed_t y) {
	struct dp_output *output = seat->ptr_output;
	seat->ptr_x = wl_fixed_to_double(x);
	seat->ptr_y = wl_fixed_to_double(y);
	dp_select_notify_pointer_position(&seat->state->selection, output, seat->ptr_x, seat->ptr_y);
	update_cursor(seat);
}

static void pointer_handle_enter(void *data, struct wl_pointer *wl_pointer, uint32_t serial,
		struct wl_surface *surface, wl_fixed_t sx, wl_fixed_t sy) {
	struct dp_seat *seat = data;
	seat->ptr_output = wl_surface_get_user_data(surface);
	assert(seat->ptr_output != NULL);
	seat->pointer_serial = serial;
	process_position(seat, sx, sy);
}

static void pointer_handle_leave(
		void *data, struct wl_pointer *wl_pointer, uint32_t serial, struct wl_surface *surface) {
	struct dp_seat *seat = data;
	seat->ptr_output = NULL;
	seat->pointer_serial = serial;
}

static void pointer_handle_motion(void *data, struct wl_pointer *wl_pointer, uint32_t time_msec,
		wl_fixed_t sx, wl_fixed_t sy) {
	struct dp_seat *seat = data;
	if (seat->ptr_output == NULL) {
		return; // Shouldn't happen
	}
	process_position(seat, sx, sy);
}

static void pointer_handle_button(void *data, struct wl_pointer *wl_pointer, uint32_t serial,
		uint32_t time_msec, uint32_t button, enum wl_pointer_button_state button_state) {
	struct dp_seat *seat = data;
	struct dp_state *state = seat->state;

	seat->pointer_serial = serial;

	struct dp_selection *selection = &state->selection;
	if (button_state != WL_POINTER_BUTTON_STATE_PRESSED) {
		if (selection->width > 0 && selection->height > 0 && state->config.quick_select) {
			state->status = DP_STATUS_SAVED;
		}
		dp_select_stop_interactive(selection);
		update_cursor(seat);
		return;
	}

	if (seat->ptr_output == NULL) {
		return; // Shouldn't happen
	}

	switch (button) {
	case BTN_LEFT:
	case BTN_RIGHT:
		dp_select_start_interactive(
				selection, seat->ptr_output, seat->ptr_x, seat->ptr_y, button == BTN_LEFT);
		update_cursor(seat);
		break;
	case BTN_MIDDLE:
		dp_select_toggle_whole(selection, seat->ptr_output);

		// Update the interaction state manually
		dp_select_notify_pointer_position(selection, seat->ptr_output, seat->ptr_x, seat->ptr_y);
		update_cursor(seat);

		if (state->config.quick_select) {
			state->status = DP_STATUS_SAVED;
		}
		break;
	}
}

static void pointer_handle_axis(void *data, struct wl_pointer *wl_pointer, uint32_t time_msec,
		enum wl_pointer_axis axis, wl_fixed_t value) {
	// Ignored
}

static const struct wl_pointer_listener pointer_listener = {
	.enter = pointer_handle_enter,
	.leave = pointer_handle_leave,
	.motion = pointer_handle_motion,
	.button = pointer_handle_button,
	.axis = pointer_handle_axis,
};

static void seat_handle_capabilities(void *data, struct wl_seat *wl_seat, uint32_t caps) {
	struct dp_seat *seat = data;
	if ((caps & WL_SEAT_CAPABILITY_KEYBOARD) != 0 && seat->keyboard == NULL) {
		seat->keyboard = wl_seat_get_keyboard(wl_seat);
		wl_keyboard_add_listener(seat->keyboard, &keyboard_listener, seat);
	}
	if ((caps & WL_SEAT_CAPABILITY_POINTER) != 0 && seat->pointer == NULL) {
		seat->pointer = wl_seat_get_pointer(wl_seat);
		wl_pointer_add_listener(seat->pointer, &pointer_listener, seat);

		if (seat->state->cursor_shape_manager != NULL) {
			seat->cursor_shape_device = wp_cursor_shape_manager_v1_get_pointer(
					seat->state->cursor_shape_manager, seat->pointer);
		}
	}
}

static void seat_handle_name(void *data, struct wl_seat *wl_seat, const char *name) {
	// Ignored
}

static const struct wl_seat_listener seat_listener = {
	.capabilities = seat_handle_capabilities,
	.name = seat_handle_name,
};

void dp_seat_create(struct dp_state *state, uint32_t name, struct wl_seat *wl_seat) {
	struct dp_seat *seat = dp_zalloc(sizeof(*seat));
	seat->state = state;
	seat->global_name = name;
	seat->wl_seat = wl_seat;

	seat->xkb_keymap =
			xkb_keymap_new_from_names(seat->state->xkb_context, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS);
	seat->xkb_state = xkb_state_new(seat->xkb_keymap);

	wl_seat_add_listener(seat->wl_seat, &seat_listener, seat);

	wl_list_insert(&state->seats, &seat->link);
}

void dp_seat_destroy(struct dp_seat *seat) {
	wl_seat_release(seat->wl_seat);
	if (seat->keyboard != NULL) {
		wl_keyboard_release(seat->keyboard);
	}
	if (seat->pointer != NULL) {
		wl_pointer_release(seat->pointer);
	}
	if (seat->cursor_shape_device != NULL) {
		wp_cursor_shape_device_v1_destroy(seat->cursor_shape_device);
	}

	xkb_keymap_unref(seat->xkb_keymap);
	xkb_state_unref(seat->xkb_state);

	wl_list_remove(&seat->link);
	free(seat);
}
