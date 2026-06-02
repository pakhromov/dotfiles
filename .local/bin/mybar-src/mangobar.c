#define _GNU_SOURCE
#include <errno.h>
#include <fcft/fcft.h>
#include <pixman.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <math.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <wayland-util.h>

/* ---- config ---- */
static const char *fontstr     = "ComicShannsLigaMod Nerd Font:size=16";
static const int   bar_height  = 24;
static const int   buffer_scale = 1;
#define clock_fg_color_hex    0x888888FF
#define clock_bg_color_hex    0x111111CC
#define updates_fg_color_hex  0x888888FF
#define updates_bg_color_hex  0x111111CC
static const int   corner_radius        = 6;
static const int   bottom_corner_radius = 9;
static const int   outline_size         = 1;
#define outline_color_hex          0x888888FF
#define battery_fg_color_hex  0x888888FF
#define battery_bg_color_hex  0x111111CC

#define UPDATES_ICON          "" //  
#define UPDATES_FETCH         "󰭽"

#define TIME_ICON_ONE 			"󱐿" //󱐿  󱑋
#define TIME_ICON_TWO 			"󱑀" //󱑀  󱑌
#define TIME_ICON_THREE 		"󱑁" //󱑁  󱑍
#define TIME_ICON_FOUR 			"󱑂" //󱑂  󱑎
#define TIME_ICON_FIVE 			"󱑃" //󱑃  󱑏
#define TIME_ICON_SIX 			"󱑄" //󱑄  󱑐
#define TIME_ICON_SEVEN 		"󱑅" //󱑅  󱑑
#define TIME_ICON_EIGHT 		"󱑆" //󱑆  󱑒
#define TIME_ICON_NINE 			"󱑇" //󱑇  󱑓
#define TIME_ICON_TEN 			"󱑈" //󱑈  󱑔
#define TIME_ICON_ELEVEN 		"󱑉" //󱑉  󱑕
#define TIME_ICON_TWELVE 		"󱑊" //󱑊  󱑖

#define BAT_10						"󰁺"
#define BAT_20						"󰁻"
#define BAT_30						"󰁼"
#define BAT_40						"󰁽"
#define BAT_50						"󰁾"
#define BAT_60						"󰁿"
#define BAT_70						"󰂀"
#define BAT_80						"󰂁"
#define BAT_90						"󰂂"
#define BAT_100					"󰁹"

#define BAT_10_CHG            "󰢜"
#define BAT_20_CHG            "󰂆"
#define BAT_30_CHG            "󰂇"
#define BAT_40_CHG            "󰂈"
#define BAT_50_CHG            "󰢝"
#define BAT_60_CHG            "󰂉"
#define BAT_70_CHG            "󰢞"
#define BAT_80_CHG            "󰂊"
#define BAT_90_CHG            "󰂋"
#define BAT_100_CHG           "󰂅"
/* ---------------- */

#include "wlr-layer-shell-unstable-v1-protocol.h"
#include "xdg-output-unstable-v1-protocol.h"
#include "xdg-shell-protocol.h"

static uint32_t utf8_decode(uint32_t *state, uint32_t *codep, uint8_t byte) {
	static const uint8_t len_tab[] = {0, 0, 0, 0, 0, 0, 0, 0,
									  0, 0, 0, 0, 1, 1, 2, 3};
	if (*state == 0) {
		if (byte < 0x80) {
			*codep = byte;
			return 0;
		}
		int len = len_tab[byte >> 4];
		if (len < 1) {
			*state = 1;
			return 1;
		}
		*codep = byte & (0x7F >> len);
		*state = len;
		return 1;
	}
	if ((byte & 0xC0) != 0x80) {
		*state = 1;
		return 1;
	}
	*codep = (*codep << 6) | (byte & 0x3F);
	if (--*state == 0)
		return 0;
	return 1;
}

static void hex_to_pixman(uint32_t hex, pixman_color_t *c) {
	c->red   = ((hex >> 24) & 0xff) * 0x101;
	c->green = ((hex >> 16) & 0xff) * 0x101;
	c->blue  = ((hex >>  8) & 0xff) * 0x101;
	c->alpha = ( hex        & 0xff) * 0x101;
}

typedef struct {
	struct wl_output *wl_output;
	struct wl_surface *wl_surface;
	struct zwlr_layer_surface_v1 *layer_surface;
	struct zxdg_output_v1 *xdg_output;
	uint32_t registry_name;
	char *name;
	bool configured;
	uint32_t width, height;
	uint32_t stride, bufsize;
	char time_str[32];
	struct wl_list link;
} Bar;

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct zwlr_layer_shell_v1 *layer_shell;
static struct zxdg_output_manager_v1 *output_manager;
static struct wl_list bar_list;
static struct fcft_font *font;
static bool running = true;

static pixman_color_t clock_fg, clock_bg;
static pixman_color_t updates_fg, updates_bg;
static pixman_color_t battery_fg, battery_bg;
static pixman_color_t outline_color;

static char battery_str[32] = "";

static void wl_buffer_release(void *data, struct wl_buffer *wl_buffer) {
	(void)data;
	wl_buffer_destroy(wl_buffer);
}
static const struct wl_buffer_listener wl_buffer_listener = {
	.release = wl_buffer_release,
};

static int allocate_shm_file(size_t size) {
	int fd = memfd_create("mangobar", MFD_CLOEXEC);
	if (fd < 0)
		return -1;
	if (ftruncate(fd, size) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

static uint32_t draw_text(const char *text, uint32_t x, uint32_t y,
						  pixman_image_t *fg, pixman_image_t *fg_mask,
						  pixman_image_t *bg, pixman_color_t *fg_color,
						  pixman_color_t *bg_color, uint32_t max_x,
						  uint32_t buf_h) {
	if (!text || !*text || x >= max_x)
		return x;
	uint32_t cur_x = x;
	uint32_t state = 0, codepoint = 0, last_cp = 0;
	for (const char *p = text; *p; p++) {
		if (utf8_decode(&state, &codepoint, (uint8_t)*p))
			continue;
		const struct fcft_glyph *g =
			fcft_rasterize_char_utf32(font, codepoint, FCFT_SUBPIXEL_NONE);
		if (!g)
			continue;
		long kern = 0;
		if (last_cp)
			fcft_kerning(font, last_cp, codepoint, &kern, NULL);
		uint32_t advance = g->advance.x + kern;
		if (cur_x + advance + 4 > max_x)
			break;
		last_cp = codepoint;

		if (fg && fg_color) {
			if (pixman_image_get_format(g->pix) == PIXMAN_a8r8g8b8) {
				pixman_image_composite32(PIXMAN_OP_OVER, g->pix, NULL, fg, 0, 0,
										 0, 0, cur_x + g->x, y - g->y, g->width,
										 g->height);
			} else {
				pixman_image_fill_boxes(PIXMAN_OP_OVER, fg, fg_color, 1,
										&(pixman_box32_t){.x1 = cur_x,
														  .x2 = cur_x + advance,
														  .y1 = 0,
														  .y2 = buf_h});
			}
			pixman_image_t *mask = pixman_image_create_solid_fill(
				&(pixman_color_t){0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF});
			pixman_image_composite32(PIXMAN_OP_OVER, g->pix, mask, fg_mask, 0,
									 0, 0, 0, cur_x + g->x, y - g->y, g->width,
									 g->height);
			pixman_image_unref(mask);
		}
		if (bg && bg_color)
			pixman_image_fill_boxes(
				PIXMAN_OP_OVER, bg, bg_color, 1,
				&(pixman_box32_t){
					.x1 = cur_x, .x2 = cur_x + advance, .y1 = 0, .y2 = buf_h});
		cur_x += advance;
	}
	return cur_x;
}

static uint32_t text_width(const char *text) {
	uint32_t w = 0, state = 0, codepoint = 0;
	for (const char *p = text; *p; p++) {
		if (utf8_decode(&state, &codepoint, (uint8_t)*p))
			continue;
		const struct fcft_glyph *g =
			fcft_rasterize_char_utf32(font, codepoint, FCFT_SUBPIXEL_NONE);
		if (g)
			w += g->advance.x;
	}
	return w;
}

static int    updates_count       = -1;
static pid_t  updates_pid         = -1;
static int    updates_pipe_fd     = -1;
static time_t updates_last_launch = 0;

static void updates_launch() {
	int pipefd[2];
	if (pipe(pipefd) < 0)
		return;
	pid_t pid = fork();
	if (pid < 0) {
		close(pipefd[0]);
		close(pipefd[1]);
		return;
	}
	if (pid == 0) {
		close(pipefd[0]);
		dup2(pipefd[1], STDOUT_FILENO);
		close(pipefd[1]);
		int devnull = open("/dev/null", O_WRONLY);
		if (devnull >= 0) { dup2(devnull, STDERR_FILENO); close(devnull); }
		execl("/bin/sh", "sh", "-c",
			"a=$(checkupdates 2>/dev/null | wc -l); "
			"b=$(yay -Qua 2>/dev/null | wc -l); "
			"echo $((a+b))", NULL);
		_exit(1);
	}
	close(pipefd[1]);
	fcntl(pipefd[0], F_SETFL, fcntl(pipefd[0], F_GETFL) | O_NONBLOCK);
	updates_pipe_fd     = pipefd[0];
	updates_pid         = pid;
	updates_last_launch = time(NULL);
}


static void get_updates_str(char *buf, size_t n) {
	if (updates_count < 0 ||
		(updates_pid != -1 && time(NULL) - updates_last_launch > 65 * 60)) {
		snprintf(buf, n, " %s", UPDATES_FETCH);
		return;
	}
	snprintf(buf, n, " %s %d", UPDATES_ICON, updates_count);
}

/* Fills a rectangle with rounded top corners and a flat bottom.
   Draws into `img` using PIXMAN_OP_OVER with `color`. */
/* side_h: how far down the left/right side strips extend (from y).
   Use h for the central strip. Pass h - bottom_corner_radius to stop before the arc. */
static void fill_top_rrect(pixman_image_t *img, pixman_color_t *color,
                            int32_t x, int32_t y, int32_t w, int32_t h, int32_t r,
                            int32_t side_h, pixman_op_t op) {
	if (w <= 0 || h <= 0) return;
	if (r > w / 2) r = w / 2;
	if (r > h)     r = h;
	if (r < 1) {
		pixman_image_fill_boxes(op, img, color, 1,
			&(pixman_box32_t){x, y, x + w, y + h});
		return;
	}
	/* central vertical strip (full height) */
	pixman_image_fill_boxes(op, img, color, 1,
		&(pixman_box32_t){x + r, y, x + w - r, y + h});
	/* left strip — stops at side_h to leave room for bottom arcs */
	if (y + r < y + side_h)
		pixman_image_fill_boxes(op, img, color, 1,
			&(pixman_box32_t){x, y + r, x + r, y + side_h});
	/* right strip */
	if (y + r < y + side_h)
		pixman_image_fill_boxes(op, img, color, 1,
			&(pixman_box32_t){x + w - r, y + r, x + w, y + side_h});
	/* top corner arcs, one row at a time */
	for (int32_t dy = 0; dy < r; dy++) {
		float vy = (float)r - (float)dy - 0.5f;
		int32_t nx = (int32_t)(sqrtf((float)(r * r) - vy * vy) + 0.5f);
		if (nx > r) nx = r;
		if (nx < 1) nx = 1;
		pixman_image_fill_boxes(op, img, color, 1,
			&(pixman_box32_t){x + r - nx, y + dy, x + r, y + dy + 1});
		pixman_image_fill_boxes(op, img, color, 1,
			&(pixman_box32_t){x + w - r, y + dy, x + w - r + nx, y + dy + 1});
	}
}

static void draw_bar(Bar *bar) {
	int fd = allocate_shm_file(bar->bufsize);
	if (fd < 0)
		return;
	uint32_t *data =
		mmap(NULL, bar->bufsize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (data == MAP_FAILED) {
		close(fd);
		return;
	}

	struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, bar->bufsize);
	struct wl_buffer *buf = wl_shm_pool_create_buffer(
		pool, 0, bar->width, bar->height, bar->stride, WL_SHM_FORMAT_ARGB8888);
	wl_buffer_add_listener(buf, &wl_buffer_listener, NULL);
	wl_shm_pool_destroy(pool);
	close(fd);

	pixman_image_t *final = pixman_image_create_bits(
		PIXMAN_a8r8g8b8, bar->width, bar->height, data, bar->width * 4);
	pixman_image_t *fg = pixman_image_create_bits(
		PIXMAN_a8r8g8b8, bar->width, bar->height, NULL, bar->width * 4);
	pixman_image_t *fg_mask = pixman_image_create_bits(
		PIXMAN_a8, bar->width, bar->height, NULL, bar->width * 4);
	/* bg rendered at 2× for supersampled anti-aliasing, scaled down when compositing */
	const int32_t S = 2;
	pixman_image_t *bg = pixman_image_create_bits(
		PIXMAN_a8r8g8b8, bar->width * S, bar->height * S, NULL, bar->width * 4 * S);

	uint32_t y = bar->height - font->descent;

	char upd_str[32];
	get_updates_str(upd_str, sizeof(upd_str));

	uint32_t bw      = text_width(battery_str);
	uint32_t tw      = text_width(bar->time_str);
	uint32_t uw      = text_width(upd_str);
	uint32_t total_w = bw + tw + uw;
	uint32_t cx = (bar->width > total_w) ? (bar->width - total_w) / 2 : 0;

	int32_t hpad = corner_radius;
	int32_t wx = (int32_t)cx - hpad;
	int32_t ww = (int32_t)total_w + 2 * hpad;
	if (wx < 0) { ww += wx; wx = 0; }

	int32_t bh  = (int32_t)bar->height;
	int32_t bcr = bottom_corner_radius;

	/* all shape coordinates ×S for 2× supersampling */
	fill_top_rrect(bg, &outline_color, wx*S, 0, ww*S, bh*S, corner_radius*S,
		(bh-bcr)*S, PIXMAN_OP_OVER);
	int32_t ir = corner_radius > outline_size ? corner_radius - outline_size : 0;
	fill_top_rrect(bg, &clock_bg,
		(wx+outline_size)*S, outline_size*S,
		(ww-2*outline_size)*S, (bh-outline_size)*S, ir*S,
		(bh-outline_size)*S, PIXMAN_OP_SRC);

	{
		int32_t r     = bcr * S;
		int32_t bhs   = bh  * S;
		int32_t wxs   = wx  * S;
		int32_t ols   = outline_size * S;
		int32_t right = (wx + ww) * S;
		int32_t bws   = (int32_t)bar->width * S;

		for (int32_t dy = 0; dy < r; dy++) {
			float   delta = (float)dy + 0.5f;
			int32_t reach = (int32_t)(sqrtf((float)(r * r) - delta * delta) + 0.5f);
			if (reach > r) reach = r;
			int32_t row = (bhs - r) + dy;

			/* Arc center at (wxs+ols-r, bhs-r): at dy=0 the outline lands exactly
			   at [wxs, wxs+ols) — flush with the side strip. */
			int32_t ax_l = wxs + ols - r + reach;
			{ int32_t x0 = ax_l < 0 ? 0 : ax_l, x1 = wxs + ols;
			  if (x0 < x1) pixman_image_fill_boxes(PIXMAN_OP_SRC, bg, &clock_bg, 1,
			      &(pixman_box32_t){x0, row, x1, row+1}); }
			{ int32_t x0 = ax_l - ols < 0 ? 0 : ax_l - ols, x1 = ax_l;
			  if (x0 < x1) pixman_image_fill_boxes(PIXMAN_OP_OVER, bg, &outline_color, 1,
			      &(pixman_box32_t){x0, row, x1, row+1}); }

			/* Arc center at (right-ols+r, bhs-r): mirror for right side. */
			int32_t ax_r = right - ols + r - reach;
			{ int32_t x0 = right - ols, x1 = ax_r > bws ? bws : ax_r;
			  if (x0 < x1) pixman_image_fill_boxes(PIXMAN_OP_SRC, bg, &clock_bg, 1,
			      &(pixman_box32_t){x0, row, x1, row+1}); }
			{ int32_t x0 = ax_r, x1 = ax_r + ols > bws ? bws : ax_r + ols;
			  if (x0 < x1) pixman_image_fill_boxes(PIXMAN_OP_OVER, bg, &outline_color, 1,
			      &(pixman_box32_t){x0, row, x1, row+1}); }
		}
	}

	uint32_t x = cx;
	if (bw > 0)
		draw_text(battery_str, x, y, fg, fg_mask, bg, &battery_fg, NULL,
				  bar->width, bar->height);
	draw_text(bar->time_str, x + bw, y, fg, fg_mask, bg, &clock_fg, NULL,
			  bar->width, bar->height);
	draw_text(upd_str, x + bw + tw, y, fg, fg_mask, bg, &updates_fg, NULL,
			  bar->width, bar->height);

	/* scale bg 2×→1× with bilinear filter for anti-aliased edges */
	{
		pixman_transform_t xform;
		pixman_transform_init_scale(&xform, pixman_int_to_fixed(S), pixman_int_to_fixed(S));
		pixman_image_set_transform(bg, &xform);
		pixman_image_set_filter(bg, PIXMAN_FILTER_BILINEAR, NULL, 0);
	}
	pixman_image_composite32(PIXMAN_OP_OVER, bg, NULL, final, 0, 0, 0, 0, 0, 0,
							 bar->width, bar->height);
	pixman_image_set_alpha_map(fg, fg_mask, 0, 0);
	pixman_image_composite32(PIXMAN_OP_OVER, fg, fg_mask, final, 0, 0, 0, 0, 0,
							 0, bar->width, bar->height);

	pixman_image_unref(fg);
	pixman_image_unref(fg_mask);
	pixman_image_unref(bg);
	pixman_image_unref(final);
	munmap(data, bar->bufsize);

	wl_surface_set_buffer_scale(bar->wl_surface, buffer_scale);
	wl_surface_attach(bar->wl_surface, buf, 0, 0);
	wl_surface_damage_buffer(bar->wl_surface, 0, 0, bar->width, bar->height);
	wl_surface_commit(bar->wl_surface);
}

static void layer_surface_configure(void *data,
									struct zwlr_layer_surface_v1 *surface,
									uint32_t serial, uint32_t w, uint32_t h) {
	Bar *bar = data;
	zwlr_layer_surface_v1_ack_configure(surface, serial);
	if (bar->configured && w == bar->width && h == bar->height)
		return;
	bar->width  = w * buffer_scale;
	bar->height = h * buffer_scale;
	bar->stride  = bar->width * 4;
	bar->bufsize = bar->stride * bar->height;
	bar->configured = true;
	draw_bar(bar);
}

static void layer_surface_closed(void *data,
								 struct zwlr_layer_surface_v1 *surface) {
	(void)data;
	(void)surface;
}

static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
	.configure = layer_surface_configure,
	.closed    = layer_surface_closed,
};

static void output_name_handler(void *data, struct zxdg_output_v1 *xdg_output,
								const char *name) {
	(void)xdg_output;
	Bar *bar = data;
	free(bar->name);
	bar->name = strdup(name);
}

static void output_logical_position(void *data, struct zxdg_output_v1 *xdg_output,
									int32_t x, int32_t y) {
	(void)data; (void)xdg_output; (void)x; (void)y;
}
static void output_logical_size(void *data, struct zxdg_output_v1 *xdg_output,
								int32_t width, int32_t height) {
	(void)data; (void)xdg_output; (void)width; (void)height;
}
static void output_done(void *data, struct zxdg_output_v1 *xdg_output) {
	(void)data; (void)xdg_output;
}
static void output_description(void *data, struct zxdg_output_v1 *xdg_output,
							   const char *description) {
	(void)data; (void)xdg_output; (void)description;
}

static const struct zxdg_output_v1_listener output_listener = {
	.name             = output_name_handler,
	.logical_position = output_logical_position,
	.logical_size     = output_logical_size,
	.done             = output_done,
	.description      = output_description,
};

static void registry_global(void *data, struct wl_registry *registry,
							uint32_t name, const char *interface,
							uint32_t version) {
	(void)data;
	(void)version;
	if (strcmp(interface, wl_compositor_interface.name) == 0)
		compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
	else if (strcmp(interface, wl_shm_interface.name) == 0)
		shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
	else if (strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0)
		layer_shell = wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, 1);
	else if (strcmp(interface, zxdg_output_manager_v1_interface.name) == 0)
		output_manager = wl_registry_bind(registry, name, &zxdg_output_manager_v1_interface, 2);
	else if (strcmp(interface, wl_output_interface.name) == 0) {
		Bar *bar = calloc(1, sizeof(Bar));
		bar->registry_name = name;
		bar->wl_output = wl_registry_bind(registry, name, &wl_output_interface, 1);
		bar->xdg_output = zxdg_output_manager_v1_get_xdg_output(output_manager, bar->wl_output);
		zxdg_output_v1_add_listener(bar->xdg_output, &output_listener, bar);
		bar->height = bar_height * buffer_scale;
		bar->wl_surface = wl_compositor_create_surface(compositor);
		bar->layer_surface = zwlr_layer_shell_v1_get_layer_surface(
			layer_shell, bar->wl_surface, bar->wl_output,
			ZWLR_LAYER_SHELL_V1_LAYER_TOP, "mangobar");
		zwlr_layer_surface_v1_add_listener(bar->layer_surface, &layer_surface_listener, bar);
		zwlr_layer_surface_v1_set_size(bar->layer_surface, 0, bar_height);
		zwlr_layer_surface_v1_set_anchor(bar->layer_surface,
			ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
			ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
			ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
		zwlr_layer_surface_v1_set_exclusive_zone(bar->layer_surface, 0);
		struct wl_region *empty = wl_compositor_create_region(compositor);
		wl_surface_set_input_region(bar->wl_surface, empty);
		wl_region_destroy(empty);
		wl_surface_commit(bar->wl_surface);
		wl_list_insert(&bar_list, &bar->link);
	}
}

static void registry_global_remove(void *data, struct wl_registry *registry,
								   uint32_t name) {
	(void)data; (void)registry; (void)name;
}

static const struct wl_registry_listener registry_listener = {
	.global        = registry_global,
	.global_remove = registry_global_remove,
};

static void update_battery_str(void) {
	battery_str[0] = '\0';
	DIR *dir = opendir("/sys/class/power_supply");
	if (!dir) return;
	char bat[64] = "";
	struct dirent *ent;
	while ((ent = readdir(dir)))
		if (strncmp(ent->d_name, "BAT", 3) == 0) {
			strncpy(bat, ent->d_name, sizeof(bat) - 1);
			break;
		}
	closedir(dir);
	if (!bat[0]) return;

	char path[128];
	int capacity = -1;
	snprintf(path, sizeof(path), "/sys/class/power_supply/%s/capacity", bat);
	FILE *f = fopen(path, "r");
	if (f) { fscanf(f, "%d", &capacity); fclose(f); }
	if (capacity < 0) return;

	int charging = 0;
	snprintf(path, sizeof(path), "/sys/class/power_supply/%s/status", bat);
	f = fopen(path, "r");
	if (f) {
		char st[16];
		if (fgets(st, sizeof(st), f))
			charging = (strncmp(st, "Charging", 8) == 0 || strncmp(st, "Full", 4) == 0);
		fclose(f);
	}

	static const char *bat_icons[10]     = { BAT_10, BAT_20, BAT_30, BAT_40, BAT_50,
	                                         BAT_60, BAT_70, BAT_80, BAT_90, BAT_100 };
	static const char *bat_chg_icons[10] = { BAT_10_CHG, BAT_20_CHG, BAT_30_CHG, BAT_40_CHG,
	                                          BAT_50_CHG, BAT_60_CHG, BAT_70_CHG, BAT_80_CHG,
	                                          BAT_90_CHG, BAT_100_CHG };
	int lvl = (capacity - 5) / 10;
	if (lvl < 0) lvl = 0;
	if (lvl > 9) lvl = 9;
	const char *icon = charging ? bat_chg_icons[lvl] : bat_icons[lvl];
	snprintf(battery_str, sizeof(battery_str), "%s %d%% ", icon, capacity);
}

/* Returns the clock-face icon for the current hour.
   Switches to the next position at :31 (past the half-hour mark). */
static const char *get_time_icon(int hour, int minute) {
	static const char *icons[12] = {
		TIME_ICON_TWELVE, TIME_ICON_ONE,   TIME_ICON_TWO,   TIME_ICON_THREE,
		TIME_ICON_FOUR,   TIME_ICON_FIVE,  TIME_ICON_SIX,   TIME_ICON_SEVEN,
		TIME_ICON_EIGHT,  TIME_ICON_NINE,  TIME_ICON_TEN,   TIME_ICON_ELEVEN
	};
	int h = hour % 12;
	if (minute >= 31) h = (h + 1) % 12;
	return icons[h];
}

static void update_time() {
	update_battery_str();
	time_t now = time(NULL);
	struct tm *tm = localtime(&now);
	char ts[16];
	strftime(ts, sizeof(ts), "%H:%M", tm);
	const char *ticon = get_time_icon(tm->tm_hour, tm->tm_min);
	Bar *b;
	wl_list_for_each(b, &bar_list, link)
		snprintf(b->time_str, sizeof(b->time_str), "%s %s", ticon, ts);
}

static void redraw_all() {
	Bar *b;
	wl_list_for_each(b, &bar_list, link)
		if (b->configured)
			draw_bar(b);
}

static void event_loop() {
	int wl_fd = wl_display_get_fd(display);
	time_t last_min = time(NULL) / 60;

	while (running) {
		/* sleep exactly until the next minute boundary */
		time_t now = time(NULL);
		struct timeval tv = { .tv_sec = 60 - (now % 60), .tv_usec = 0 };

		fd_set rfds;
		FD_ZERO(&rfds);
		FD_SET(wl_fd, &rfds);
		int maxfd = wl_fd;
		if (updates_pipe_fd >= 0) {
			FD_SET(updates_pipe_fd, &rfds);
			if (updates_pipe_fd > maxfd) maxfd = updates_pipe_fd;
		}

		wl_display_flush(display);
		int ret = select(maxfd + 1, &rfds, NULL, NULL, &tv);
		if (ret < 0) {
			if (errno == EINTR) continue;
			break;
		}

		if (FD_ISSET(wl_fd, &rfds))
			wl_display_dispatch(display);

		/* updates child finished: read result and redraw */
		if (updates_pipe_fd >= 0 && FD_ISSET(updates_pipe_fd, &rfds)) {
			char buf[32];
			ssize_t n = read(updates_pipe_fd, buf, sizeof(buf) - 1);
			if (n > 0) {
				buf[n] = '\0';
				int val = atoi(buf);
				if (val >= 0) updates_count = val;
			}
			close(updates_pipe_fd);
			updates_pipe_fd = -1;
			int wstatus;
			waitpid(updates_pid, &wstatus, 0);
			updates_pid = -1;
			redraw_all();
		}

		/* minute turned: update time, maybe relaunch updates */
		now = time(NULL);
		time_t cur_min = now / 60;
		if (cur_min != last_min) {
			last_min = cur_min;
			update_time();
			if (updates_pid == -1 &&
				(updates_last_launch == 0 || now - updates_last_launch >= 3600))
				updates_launch();
			redraw_all();
		}
	}
}

int main() {
	fcft_init(FCFT_LOG_COLORIZE_AUTO, 0, FCFT_LOG_CLASS_ERROR);
	font = fcft_from_name(1, (const char *[]){fontstr}, NULL);
	if (!font) {
		fprintf(stderr, "Failed to load fonts\n");
		return 1;
	}

	hex_to_pixman(clock_fg_color_hex,   &clock_fg);
	hex_to_pixman(clock_bg_color_hex,   &clock_bg);
	hex_to_pixman(updates_fg_color_hex, &updates_fg);
	hex_to_pixman(updates_bg_color_hex, &updates_bg);
	hex_to_pixman(battery_fg_color_hex, &battery_fg);
	hex_to_pixman(battery_bg_color_hex, &battery_bg);
	hex_to_pixman(outline_color_hex,    &outline_color);

	display = wl_display_connect(NULL);
	if (!display) {
		fcft_destroy(font);
		fcft_fini();
		return 1;
	}
	wl_list_init(&bar_list);

	struct wl_registry *registry = wl_display_get_registry(display);
	wl_registry_add_listener(registry, &registry_listener, NULL);

	wl_display_roundtrip(display);
	if (!compositor || !shm || !layer_shell || !output_manager) {
		fcft_destroy(font);
		fcft_fini();
		wl_display_disconnect(display);
		return 1;
	}

	wl_display_roundtrip(display);

	update_time();
	updates_launch();
	signal(SIGTERM, exit);
	signal(SIGINT, exit);

	event_loop();

	fcft_destroy(font);
	fcft_fini();
	wl_display_disconnect(display);

	return 0;
}
