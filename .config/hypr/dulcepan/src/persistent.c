#include <errno.h>
#include <sfdo-basedir.h>
#include <stdlib.h>
#include <string.h>

#include "dulcepan.h"

#define STATE_SUBPATH "dulcepan"

// State format:
//
// <output name>
// <x> <y> <width> <height>

void dp_persistent_load(struct dp_state *state) {
	size_t dir_len;
	const char *dir = sfdo_basedir_get_cache_home(state->basedir_ctx, &dir_len);
	state->persistent_path = dp_zalloc(dir_len + sizeof(STATE_SUBPATH));
	memcpy(state->persistent_path, dir, dir_len);
	memcpy(state->persistent_path + dir_len, STATE_SUBPATH, sizeof(STATE_SUBPATH));

	FILE *fp = fopen(state->persistent_path, "r");
	if (fp == NULL) {
		if (errno != ENOENT) {
			dp_log_error("Failed to open %s: %s", state->persistent_path, strerror(errno));
		}
		return;
	}

	char name[32];
	double x, y, width, height;
	int n_read = 0;

	fgets(name, sizeof(name), fp);
	size_t name_len = strlen(name);
	if (name[name_len - 1] == '\n') {
		name[--name_len] = '\0';
	}
	n_read += fscanf(fp, "%lf %lf %lf %lf", &x, &y, &width, &height);

	bool ok = ferror(fp) == 0 && n_read == 4;
	fclose(fp);

	if (!ok) {
		dp_log_error("Persistent state: bad format");
		return;
	}

	struct dp_output *selection_output = NULL;

	struct dp_output *output;
	wl_list_for_each (output, &state->outputs, link) {
		if (strcmp(output->name, name) == 0) {
			selection_output = output;
			break;
		}
	}

	if (selection_output == NULL) {
		dp_log_error("Persistent state: failed to find cached output %s", name);
		return;
	}

	if (x < 0 || y < 0 || x + width > selection_output->effective_width ||
			y + height > selection_output->effective_height) {
		dp_log_error("Persistent state: invalid selection geometry", name);
		return;
	}

	struct dp_selection *selection = &state->selection;
	selection->output = selection_output;
	selection->x = x;
	selection->y = y;
	selection->width = width;
	selection->height = height;
}

void dp_persistent_save(struct dp_state *state) {
	struct dp_selection *selection = &state->selection;
	if (selection->output != NULL) {
		FILE *fp = fopen(state->persistent_path, "w");
		if (fp == NULL) {
			dp_log_error("Failed to open %s: %s", state->persistent_path, strerror(errno));
		} else {
			fprintf(fp,
					"%s\n"
					"%lf %lf %lf %lf\n",
					selection->output->name, selection->x, selection->y, selection->width,
					selection->height);
			fclose(fp);
		}
	}

	free(state->persistent_path);
}
