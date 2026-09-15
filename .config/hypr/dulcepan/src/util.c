#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "dulcepan.h"

static void vlog_prefixed(const char *prefix, const char *fmt, va_list args) {
	fprintf(stderr, "[%s] ", prefix);
	vfprintf(stderr, fmt, args);
	fprintf(stderr, "\n");
}

void dp_log_error(const char *fmt, ...) {
	va_list args;
	va_start(args, fmt);
	vlog_prefixed("error", fmt, args);
	va_end(args);
}

void dp_log_fatal(const char *fmt, ...) {
	va_list args;
	va_start(args, fmt);
	vlog_prefixed("FATAL", fmt, args);
	va_end(args);
	exit(1);
}

void *dp_zalloc(size_t size) {
	if (size == 0) {
		return NULL;
	}

	void *ptr = calloc(1, size);
	if (ptr == NULL) {
		dp_log_fatal("Failed to allocate %zu bytes", size);
	}
	return ptr;
}

char *dp_strdup(const char *str) {
	char *ptr = strdup(str);
	if (ptr == NULL) {
		dp_log_fatal("Failed to duplicate %s", str);
	}
	return ptr;
}

const char *dp_ext_from_path(const char *path) {
	size_t len = strlen(path);
	for (size_t i = len; i-- > 0;) {
		if (path[i] == '.') {
			return path + i + 1;
		} else if (path[i] == '/') {
			break;
		}
	}
	return path + len;
}

enum dp_file_format dp_ext_to_format(const char *ext) {
	if (strcasecmp(ext, "ppm") == 0) {
		return DP_FILE_PPM;
	} else if (strcasecmp(ext, "png") == 0) {
		return DP_FILE_PNG;
	}
	return DP_FILE_UNKNOWN;
}

void dp_matrix_compute_linear(cairo_matrix_t *matrix, double angle) {
	double c = cos(angle), s = sin(angle);
	double f = 1.0 / (fabs(c) + fabs(s));

	cairo_matrix_init_translate(matrix, 0.5, 0.5);
	cairo_matrix_scale(matrix, f, 1);

	cairo_matrix_t tmp;
	cairo_matrix_init(&tmp, c, s, -s, c, 0, 0);
	cairo_matrix_multiply(matrix, &tmp, matrix);

	cairo_matrix_translate(matrix, -0.5, -0.5);
}
