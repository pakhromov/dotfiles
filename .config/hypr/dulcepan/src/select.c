#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

#include "dulcepan.h"

#define RESIZE_INNER_SIZE 4
#define RESIZE_OUTER_SIZE 12
#define RESIZE_CORNER_SIZE 24
#define RESIZE_THRESHOLD (RESIZE_OUTER_SIZE + RESIZE_CORNER_SIZE)

static void set_selected_output(struct dp_selection *selection, struct dp_output *output) {
	if (selection->output == output) {
		return;
	}
	struct dp_output *prev = selection->output;
	selection->output = output;
	if (prev != NULL) {
		dp_output_redraw(prev);
	}
}

static inline bool has_last_partial(struct dp_selection *selection) {
	return selection->last_partial.output != NULL;
}

static inline void reset_last_partial(struct dp_selection *selection) {
	selection->last_partial.output = NULL;
}

static bool has_partial(struct dp_selection *selection) {
	struct dp_output *output = selection->output;
	if (output == NULL) {
		return false;
	}

	return selection->x != 0 || selection->y != 0 || selection->width != output->effective_width ||
			selection->height != output->effective_height;
}

static void update_action(
		struct dp_selection *selection, struct dp_output *output, double x, double y) {
	if (output == selection->output) {
		double sx = x - selection->x;
		double sy = y - selection->y;

		if (sx >= RESIZE_INNER_SIZE && sy >= RESIZE_INNER_SIZE &&
				sx < selection->width - RESIZE_INNER_SIZE &&
				sy <= selection->height - RESIZE_INNER_SIZE) {
			selection->action = DP_SELECTION_ACTION_MOVING;
			return;
		} else if (sx >= -RESIZE_OUTER_SIZE && sy >= -RESIZE_OUTER_SIZE &&
				sx < selection->width + RESIZE_OUTER_SIZE &&
				sy < selection->height + RESIZE_OUTER_SIZE) {
			int edges = DP_EDGE_NONE;

			if (sx >= selection->width - RESIZE_THRESHOLD && sx >= selection->width / 2) {
				edges |= DP_EDGE_RIGHT;
			} else if (sx < RESIZE_THRESHOLD) {
				edges |= DP_EDGE_LEFT;
			}
			if (sy >= selection->height - RESIZE_THRESHOLD && sy >= selection->height / 2) {
				edges |= DP_EDGE_BOTTOM;
			} else if (sy < RESIZE_THRESHOLD) {
				edges |= DP_EDGE_TOP;
			}

			if (edges != DP_EDGE_NONE) {
				selection->action = DP_SELECTION_ACTION_RESIZING;
				selection->resize_edges = edges;
				return;
			}
		}
	}

	selection->action = DP_SELECTION_ACTION_NONE;
}

static void do_resize(struct dp_selection *selection, double x, double y) {
	double ptr_x = x - selection->ptr_off_x, ptr_y = y - selection->ptr_off_y;
	if (ptr_x < 0) {
		ptr_x = 0;
	} else if (ptr_x > selection->output->effective_width) {
		ptr_x = selection->output->effective_width;
	}
	if (ptr_y < 0) {
		ptr_y = 0;
	} else if (ptr_y > selection->output->effective_height) {
		ptr_y = selection->output->effective_height;
	}

	double width = selection->width, height = selection->height;

retry_horiz:
	if ((selection->resize_edges & DP_EDGE_LEFT) != 0) {
		width = selection->resize_x - ptr_x;
		if (width < 0) {
			selection->resize_edges = (selection->resize_edges & ~DP_EDGE_LEFT) | DP_EDGE_RIGHT;
			goto retry_horiz;
		}
		selection->x = selection->resize_x - width;
	} else if ((selection->resize_edges & DP_EDGE_RIGHT) != 0) {
		width = ptr_x - selection->resize_x;
		if (width < 0) {
			selection->resize_edges = (selection->resize_edges & ~DP_EDGE_RIGHT) | DP_EDGE_LEFT;
			goto retry_horiz;
		}
		selection->x = selection->resize_x;
	}

retry_verti:
	if ((selection->resize_edges & DP_EDGE_TOP) != 0) {
		height = selection->resize_y - ptr_y;
		if (height < 0) {
			selection->resize_edges = (selection->resize_edges & ~DP_EDGE_TOP) | DP_EDGE_BOTTOM;
			goto retry_verti;
		}
		selection->y = selection->resize_y - height;
	} else if ((selection->resize_edges & DP_EDGE_BOTTOM) != 0) {
		height = ptr_y - selection->resize_y;
		if (height < 0) {
			selection->resize_edges = (selection->resize_edges & ~DP_EDGE_BOTTOM) | DP_EDGE_TOP;
			goto retry_verti;
		}
		selection->y = selection->resize_y;
	}

	if (width == selection->width && height == selection->height) {
		return;
	}

	selection->width = width;
	selection->height = height;
	dp_output_redraw(selection->output);
}

static void do_move(struct dp_selection *selection, double x, double y) {
	double new_x = x - selection->ptr_off_x, new_y = y - selection->ptr_off_y;

	if (new_x < 0) {
		new_x = 0;
	} else if (new_x > selection->output->effective_width - selection->width) {
		new_x = selection->output->effective_width - selection->width;
	}
	if (new_y < 0) {
		new_y = 0;
	} else if (new_y > selection->output->effective_height - selection->height) {
		new_y = selection->output->effective_height - selection->height;
	}

	if (new_x == selection->x && new_y == selection->y) {
		return;
	}

	selection->x = new_x;
	selection->y = new_y;
	dp_output_redraw(selection->output);
}

static void init_resize(struct dp_selection *selection, double x, double y) {
	if ((selection->resize_edges & DP_EDGE_RIGHT) != 0) {
		selection->ptr_off_x = x - selection->x - selection->width;
		selection->resize_x = selection->x;
	} else {
		selection->ptr_off_x = x - selection->x;
		selection->resize_x = selection->x + selection->width;
	}
	if ((selection->resize_edges & DP_EDGE_BOTTOM) != 0) {
		selection->ptr_off_y = y - selection->y - selection->height;
		selection->resize_y = selection->y;
	} else {
		selection->ptr_off_y = y - selection->y;
		selection->resize_y = selection->y + selection->height;
	}
}

void dp_select_start_interactive(struct dp_selection *selection, struct dp_output *output, double x,
		double y, bool modify_existing) {
	update_action(selection, output, x, y);
	selection->action_active = true;

	reset_last_partial(selection);

	if (modify_existing) {
		switch (selection->action) {
		case DP_SELECTION_ACTION_NONE:
			break;
		case DP_SELECTION_ACTION_RESIZING:
			init_resize(selection, x, y);
			return;
		case DP_SELECTION_ACTION_MOVING:
			selection->ptr_off_x = x - selection->x;
			selection->ptr_off_y = y - selection->y;
			return;
		}
	}

	// Start a new selection

	set_selected_output(selection, output);
	selection->x = x;
	selection->y = y;
	selection->width = 0;
	selection->height = 0;

	selection->action = DP_SELECTION_ACTION_RESIZING;
	selection->resize_edges = DP_EDGE_BOTTOM | DP_EDGE_RIGHT;

	init_resize(selection, x, y);

	dp_output_redraw(output);
}

void dp_select_stop_interactive(struct dp_selection *selection) {
	selection->action_active = false;
}

void dp_select_notify_pointer_position(
		struct dp_selection *selection, struct dp_output *output, double x, double y) {
	if (selection->action_active) {
		switch (selection->action) {
		case DP_SELECTION_ACTION_NONE:
			abort(); // Unreachable
		case DP_SELECTION_ACTION_RESIZING:
			do_resize(selection, x, y);
			break;
		case DP_SELECTION_ACTION_MOVING:
			do_move(selection, x, y);
			break;
		}
	} else {
		update_action(selection, output, x, y);
	}
}

void dp_select_toggle_whole(struct dp_selection *selection, struct dp_output *output) {
	if (selection->output == output && has_last_partial(selection)) {
		// Toggle the selection back to the last partial one
		set_selected_output(selection, selection->last_partial.output);

		selection->x = selection->last_partial.x;
		selection->y = selection->last_partial.y;
		selection->width = selection->last_partial.width;
		selection->height = selection->last_partial.height;

		reset_last_partial(selection);
	} else {
		// Don't save another whole output selection as partial
		if (has_partial(selection) && !has_last_partial(selection)) {
			selection->last_partial.output = selection->output;

			selection->last_partial.x = selection->x;
			selection->last_partial.y = selection->y;
			selection->last_partial.width = selection->width;
			selection->last_partial.height = selection->height;
		}

		set_selected_output(selection, output);

		selection->x = 0;
		selection->y = 0;
		selection->width = output->effective_width;
		selection->height = output->effective_height;
	}

	dp_output_redraw(selection->output);
}
