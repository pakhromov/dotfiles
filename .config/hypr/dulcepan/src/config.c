#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "dulcepan.h"

#define CONFIG_SUBPATH "dulcepan.cfg"

static inline void bytes_to_color(uint8_t bytes[static 4], float out[static 4]) {
	for (size_t i = 0; i < 4; i++) {
		out[i] = (float)bytes[i] / UINT8_MAX;
	}
}

static void keybinding_init(struct dp_keybinding *kb, xkb_keysym_t *syms, size_t n_syms) {
	*kb = (struct dp_keybinding){
		.syms = dp_zalloc(sizeof(*kb->syms) * n_syms),
		.n_syms = n_syms,
	};
	for (size_t i = 0; i < n_syms; i++) {
		xkb_keysym_t sym = syms[i];
		kb->syms[i] = sym;
	}
}

static void keybinding_finish(struct dp_keybinding *kb) {
	free(kb->syms);
}

static void load_color(char *value, int line_idx, float out[static 4]) {
	size_t len = strlen(value);

	uint8_t bytes[4] = {0, 0, 0, 0};
	if (len == 6) {
		bytes[3] = UINT8_MAX;
	} else if (len != 8) {
		goto bad;
	}

	for (size_t i = 0; i < len; i++) {
		uint8_t digit;
		if (value[i] >= '0' && value[i] <= '9') {
			digit = (uint8_t)(value[i] - '0');
		} else if (value[i] >= 'A' && value[i] <= 'F') {
			digit = (uint8_t)(value[i] - 'A' + 10);
		} else if (value[i] >= 'a' && value[i] <= 'f') {
			digit = (uint8_t)(value[i] - 'a' + 10);
		} else {
			goto bad;
		}
		bytes[i / 2] = (uint8_t)(bytes[i / 2] * 16 + digit);
	}

	bytes_to_color(bytes, out);
	return;

bad:
	dp_log_fatal("Config: invalid color %s on line %d", value, line_idx);
}

static void load_int(char *value, int line_idx, int min, int max, int *out) {
	const char *p = value;
	int mul = 1;
	if (*p == '-') {
		++p;
		mul = -1;
	}

	*out = 0;
	for (; *p != '\0'; p++) {
		if ((*p < '0' && *p > 9) || *out >= INT_MAX / 10) {
			dp_log_fatal("Config: invalid number %s on line %d", value, line_idx);
		}
		*out = *out * 10 - '0' + *p;
	}
	*out *= mul;

	if (*out < min || *out > max) {
		dp_log_fatal("Config: number %s on line %d is out of range", value, line_idx);
	}
}

static void load_bool(char *value, int line_idx, bool *out) {
	if (strcmp(value, "true") == 0) {
		*out = true;
	} else if (strcmp(value, "false") == 0) {
		*out = false;
	} else {
		dp_log_fatal("Config: invalid boolean value %s on line %d", value, line_idx);
	}
}

static void load_key(char *value, int line_idx, struct dp_keybinding *out) {
	size_t n_syms = 0;
	xkb_keysym_t syms[32];

	char *save_ptr = NULL;
	for (char *name; (name = strtok_r(value, ",", &save_ptr)) != NULL; value = NULL) {
		if (n_syms == sizeof(syms) / sizeof(*syms)) {
			// chill out
			dp_log_fatal("Config: too many keys on line %d", line_idx);
		}
		xkb_keysym_t sym = xkb_keysym_from_name(name, XKB_KEYSYM_CASE_INSENSITIVE);
		if (sym == XKB_KEY_NoSymbol) {
			dp_log_fatal("Config: unknown key \"%s\" on line %d", name, line_idx);
		}
		syms[n_syms++] = sym;
	}

	keybinding_finish(out);
	keybinding_init(out, syms, n_syms);
}

void dp_config_load(struct dp_state *state, const char *user_path) {
	struct dp_config *config = &state->config;

	*config = (struct dp_config){
		.border_size = 2,
		.border_gradient = DP_BORDER_GRADIENT_NONE,
		.gradient_angle = 45,
		.loop_step = 100,
		.animation_duration = 0,
		.png_compression = 6,
		.quick_select = false,
		.persistence = true,
	};

	bytes_to_color((uint8_t[]){0xff, 0xff, 0xff, 0x40}, config->unselected_color);
	bytes_to_color((uint8_t[]){0x00, 0x00, 0x00, 0x00}, config->selected_color);
	bytes_to_color((uint8_t[]){0xff, 0xff, 0xff, 0xff}, config->border_color);
	bytes_to_color((uint8_t[]){0x00, 0x00, 0x00, 0xff}, config->border_secondary_color);

	keybinding_init(&config->quit_kb, (xkb_keysym_t[]){XKB_KEY_Escape}, 1);
	keybinding_init(&config->save_kb, (xkb_keysym_t[]){XKB_KEY_space, XKB_KEY_Return}, 2);

	FILE *fp = NULL;
	if (user_path != NULL) {
		fp = fopen(user_path, "r");
		if (fp == NULL) {
			dp_log_fatal("Failed to open %s: %s", user_path, strerror(errno));
		}
	} else {
		size_t n_dirs;
		const struct sfdo_string *dirs = sfdo_basedir_get_config_dirs(state->basedir_ctx, &n_dirs);
		for (size_t i = 0; i < n_dirs && fp == NULL; i++) {
			const struct sfdo_string *dir = &dirs[i];
			size_t size = dir->len + sizeof(CONFIG_SUBPATH);
			char *path = dp_zalloc(size);
			memcpy(path, dir->data, dir->len);
			memcpy(path + dir->len, CONFIG_SUBPATH, sizeof(CONFIG_SUBPATH));
			fp = fopen(path, "r");
			if (fp == NULL) {
				if (errno != ENOENT) {
					dp_log_fatal("Failed to open %s: %s", path, strerror(errno));
				}
			}
			free(path);
		}
	}

	if (fp == NULL) {
		return;
	}

	int line_idx = 0;
	char *line = NULL;
	size_t line_cap = 0;
	ssize_t line_len;
	while ((line_len = getline(&line, &line_cap, fp)) != -1) {
		++line_idx;

		if (line[line_len - 1] == '\n') {
			line[--line_len] = '\0';
		}

		// One of:
		// [whitespace] [# comment]
		// [whitespace] <key> [whitespace] = [whitespace] <value> [whitespace] [# comment]

		ssize_t i = 0;
		while (isspace(line[line_len]) && i++ < line_len) {
			// Skip whitespace
		}
		if (line[i] == '\0' || line[i] == '#') {
			continue;
		}

		char *key = &line[i];
		while (!isspace(line[i]) && line[i] != '=' && line[i] != '#' && i++ < line_len) {
			// Read key
		}
		char *key_end = &line[i];

		while (isspace(line[i]) && i++ < line_len) {
			// Skip whitespace
		}
		if (line[i++] != '=') {
			dp_log_fatal("Config: invalid syntax on line %d", line_idx);
		}
		*key_end = '\0';
		while (isspace(line[i]) && i++ < line_len) {
			// Skip whitespace
		}

		char *value = &line[i];
		while (!isspace(line[i]) && line[i] != '#' && i++ < line_len) {
			// Read value
		}
		line[i] = '\0';

		if (strcmp(key, "unselected-color") == 0) {
			load_color(value, line_idx, config->unselected_color);
		} else if (strcmp(key, "selected-color") == 0) {
			load_color(value, line_idx, config->selected_color);
		} else if (strcmp(key, "border-color") == 0) {
			load_color(value, line_idx, config->border_color);
		} else if (strcmp(key, "border-secondary-color") == 0) {
			load_color(value, line_idx, config->border_secondary_color);
		} else if (strcmp(key, "border-size") == 0) {
			load_int(value, line_idx, 0, INT_MAX, &config->border_size);
		} else if (strcmp(key, "border-gradient") == 0) {
			if (strcmp(value, "none") == 0) {
				config->border_gradient = DP_BORDER_GRADIENT_NONE;
			} else if (strcmp(value, "linear") == 0) {
				config->border_gradient = DP_BORDER_GRADIENT_LINEAR;
			} else if (strcmp(value, "loop") == 0) {
				config->border_gradient = DP_BORDER_GRADIENT_LOOP;
			} else {
				dp_log_fatal("Config: invalid border-gradient %s on line %d", value, line_idx);
			}
		} else if (strcmp(key, "gradient-angle") == 0) {
			int deg;
			load_int(value, line_idx, INT_MIN, INT_MAX, &deg);
			config->gradient_angle = (double)deg * DP_PI / 180;
		} else if (strcmp(key, "loop-step") == 0) {
			load_int(value, line_idx, 1, INT_MAX, &config->loop_step);
		} else if (strcmp(key, "animation-duration") == 0) {
			load_int(value, line_idx, 0, INT_MAX, &config->animation_duration);
		} else if (strcmp(key, "png-compression") == 0) {
			load_int(value, line_idx, 0, 9, &config->png_compression);
		} else if (strcmp(key, "quick-select") == 0) {
			load_bool(value, line_idx, &config->quick_select);
		} else if (strcmp(key, "persistence") == 0) {
			load_bool(value, line_idx, &config->persistence);
		} else if (strcmp(key, "quit-key") == 0) {
			load_key(value, line_idx, &config->quit_kb);
		} else if (strcmp(key, "save-key") == 0) {
			load_key(value, line_idx, &config->save_kb);
		} else {
			dp_log_error("Config: unknown key %s on line %d", key, line_idx);
		}
	}
	free(line);

	fclose(fp);
}

void dp_config_finish(struct dp_state *state) {
	struct dp_config *config = &state->config;

	keybinding_finish(&config->quit_kb);
	keybinding_finish(&config->save_kb);
}
