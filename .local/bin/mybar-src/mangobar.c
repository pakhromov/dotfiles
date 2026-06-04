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
#define CORNER_RADIUS         6
#define BOTTOM_CORNER_RADIUS  9
#define OUTLINE_SIZE          1
#define outline_color_hex     0x888888FF
#define battery_fg_color_hex  0x888888FF
/* supersampling factor for background shape anti-aliasing */
#define BGSS 2
/* ---------------- */

#define UPDATES_ICON          "" //
#define UPDATES_FETCH         "󰭽"

#define TIME_ICON_ONE         "󱐿"
#define TIME_ICON_TWO         "󱑀"
#define TIME_ICON_THREE       "󱑁"
#define TIME_ICON_FOUR        "󱑂"
#define TIME_ICON_FIVE        "󱑃"
#define TIME_ICON_SIX         "󱑄"
#define TIME_ICON_SEVEN       "󱑅"
#define TIME_ICON_EIGHT       "󱑆"
#define TIME_ICON_NINE        "󱑇"
#define TIME_ICON_TEN         "󱑈"
#define TIME_ICON_ELEVEN      "󱑉"
#define TIME_ICON_TWELVE      "󱑊"

#define BAT_10    "󰁺"
#define BAT_20    "󰁻"
#define BAT_30    "󰁼"
#define BAT_40    "󰁽"
#define BAT_50    "󰁾"
#define BAT_60    "󰁿"
#define BAT_70    "󰂀"
#define BAT_80    "󰂁"
#define BAT_90    "󰂂"
#define BAT_100   "󰁹"

#define BAT_10_CHG  "󰢜"
#define BAT_20_CHG  "󰂆"
#define BAT_30_CHG  "󰂇"
#define BAT_40_CHG  "󰂈"
#define BAT_50_CHG  "󰢝"
#define BAT_60_CHG  "󰂉"
#define BAT_70_CHG  "󰢞"
#define BAT_80_CHG  "󰂊"
#define BAT_90_CHG  "󰂋"
#define BAT_100_CHG "󰂅"

#include "wlr-layer-shell-unstable-v1-protocol.h"

/* Precomputed per-row arc spans for background shape (filled once in main).
   Sized for the exact supersampled radii used during drawing. */
static int32_t arc_top_outer[CORNER_RADIUS * BGSS];
static int32_t arc_top_inner[(CORNER_RADIUS - OUTLINE_SIZE) * BGSS];
static int32_t arc_bot[BOTTOM_CORNER_RADIUS * BGSS];

static uint32_t utf8_decode(uint32_t *state, uint32_t *codep, uint8_t byte) {
	static const uint8_t len_tab[] = {0,0,0,0,0,0,0,0,0,0,0,0,1,1,2,3};
	if (*state == 0) {
		if (byte < 0x80) { *codep = byte; return 0; }
		int len = len_tab[byte >> 4];
		if (len < 1) { *state = 1; return 1; }
		*codep = byte & (0x7F >> len);
		*state = len;
		return 1;
	}
	if ((byte & 0xC0) != 0x80) { *state = 1; return 1; }
	*codep = (*codep << 6) | (byte & 0x3F);
	if (--*state == 0) return 0;
	return 1;
}

static void hex_to_pixman(uint32_t hex, pixman_color_t *c) {
	c->red   = ((hex >> 24) & 0xff) * 0x101;
	c->green = ((hex >> 16) & 0xff) * 0x101;
	c->blue  = ((hex >>  8) & 0xff) * 0x101;
	c->alpha = ( hex        & 0xff) * 0x101;
}

typedef struct {
	struct wl_buffer *buffer;
	uint32_t         *data;
	pixman_image_t   *image;
	uint32_t          width, height, stride, bufsize;
	bool              busy;
} BufferSlot;

typedef struct {
	struct wl_output             *wl_output;
	struct wl_surface            *wl_surface;
	struct zwlr_layer_surface_v1 *layer_surface;
	uint32_t registry_name;
	bool     configured;
	uint32_t width, height;
	uint32_t stride, bufsize;

	BufferSlot slots[2];
	pixman_image_t *fg;
	pixman_image_t *fg_mask;
	pixman_image_t *bg;
	uint32_t fg_w, fg_h, mask_w, mask_h, bg_w, bg_h;

	struct wl_list link;
} Bar;

static struct wl_display              *display;
static struct wl_compositor           *compositor;
static struct wl_shm                  *shm;
static struct zwlr_layer_shell_v1     *layer_shell;
static struct wl_list  bar_list;
static struct fcft_font *font;
static bool running = true;

static pixman_color_t clock_fg, clock_bg;
static pixman_color_t updates_fg;
static pixman_color_t battery_fg;
static pixman_color_t outline_color;

static pixman_image_t *white_solid = NULL;

static char battery_str[32] = "";
static char time_str[32]    = "";  /* shared across all bars */
static char upd_str[32]     = "";  /* cached updates display string */

/* Layout widths; recomputed only when any string changes. */
static uint32_t layout_bw = 0, layout_tw = 0, layout_uw = 0;
static bool     layout_dirty = true;

/* Battery sysfs paths found once on first call to update_battery_str. */
static char bat_capacity_path[128] = "";
static char bat_status_path[128]   = "";

static int    updates_count       = -1;
static pid_t  updates_pid         = -1;
static int    updates_pipe_fd     = -1;
static time_t updates_last_launch = 0;

/* ---- wl_buffer ---- */
static void wl_buffer_release(void *data, struct wl_buffer *wl_buffer) {
	(void)wl_buffer;
	((BufferSlot *)data)->busy = false;
}
static const struct wl_buffer_listener wl_buffer_listener = {
	.release = wl_buffer_release,
};

static int allocate_shm_file(size_t size) {
	int fd = memfd_create("mangobar", MFD_CLOEXEC);
	if (fd < 0) return -1;
	if (ftruncate(fd, size) < 0) { close(fd); return -1; }
	return fd;
}

static void buffer_slot_destroy(BufferSlot *slot) {
	if (slot->image) pixman_image_unref(slot->image);
	if (slot->buffer) wl_buffer_destroy(slot->buffer);
	if (slot->data) munmap(slot->data, slot->bufsize);
	memset(slot, 0, sizeof(*slot));
}

static bool buffer_slot_ensure(BufferSlot *slot, uint32_t width, uint32_t height,
                               uint32_t stride, uint32_t bufsize) {
	if (slot->buffer && slot->width == width && slot->height == height &&
	    slot->stride == stride && slot->bufsize == bufsize)
		return true;

	buffer_slot_destroy(slot);

	int fd = allocate_shm_file(bufsize);
	if (fd < 0) return false;
	uint32_t *data = mmap(NULL, bufsize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (data == MAP_FAILED) { close(fd); return false; }

	struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, bufsize);
	struct wl_buffer *buffer = wl_shm_pool_create_buffer(
		pool, 0, width, height, stride, WL_SHM_FORMAT_ARGB8888);
	wl_shm_pool_destroy(pool);
	close(fd);

	pixman_image_t *image = pixman_image_create_bits(
		PIXMAN_a8r8g8b8, width, height, data, stride);
	if (!image) {
		wl_buffer_destroy(buffer);
		munmap(data, bufsize);
		return false;
	}

	slot->buffer  = buffer;
	slot->data    = data;
	slot->image   = image;
	slot->width   = width;
	slot->height  = height;
	slot->stride  = stride;
	slot->bufsize = bufsize;
	wl_buffer_add_listener(buffer, &wl_buffer_listener, slot);
	return true;
}

static BufferSlot *bar_next_slot(Bar *bar) {
	for (size_t i = 0; i < 2; i++) {
		BufferSlot *slot = &bar->slots[i];
		if (!slot->busy &&
		    buffer_slot_ensure(slot, bar->width, bar->height, bar->stride, bar->bufsize))
			return slot;
	}
	return NULL;
}

/* ---- drawing ---- */

/* Rounded-top rectangle using precomputed arc spans.
   side_h: height (from y=0) at which the left/right side strips stop. */
static void fill_top_rrect(pixman_image_t *img, pixman_color_t *color,
                            int32_t x, int32_t y, int32_t w, int32_t h,
                            int32_t r, const int32_t *arc_nx,
                            int32_t side_h, pixman_op_t op) {
	if (w <= 0 || h <= 0) return;
	if (r > w / 2) r = w / 2;
	if (r > h)     r = h;
	if (r < 1) {
		pixman_image_fill_boxes(op, img, color, 1,
			&(pixman_box32_t){x, y, x + w, y + h});
		return;
	}
	pixman_image_fill_boxes(op, img, color, 1,
		&(pixman_box32_t){x + r, y, x + w - r, y + h});
	if (r < side_h) {
		pixman_image_fill_boxes(op, img, color, 1,
			&(pixman_box32_t){x, y + r, x + r, y + side_h});
		pixman_image_fill_boxes(op, img, color, 1,
			&(pixman_box32_t){x + w - r, y + r, x + w, y + side_h});
	}
	for (int32_t dy = 0; dy < r; dy++) {
		int32_t nx = arc_nx[dy];
		pixman_image_fill_boxes(op, img, color, 1,
			&(pixman_box32_t){x + r - nx, y + dy, x + r, y + dy + 1});
		pixman_image_fill_boxes(op, img, color, 1,
			&(pixman_box32_t){x + w - r, y + dy, x + w - r + nx, y + dy + 1});
	}
}

/* Draw text into fg (color) and fg_mask (coverage), returning x after last glyph.
   Uses the cached white_solid image instead of allocating per glyph. */
static uint32_t draw_text(const char *text, uint32_t x, uint32_t y,
                          pixman_image_t *fg, pixman_image_t *fg_mask,
                          pixman_color_t *fg_color,
                          uint32_t max_x, uint32_t buf_h) {
	if (!text || !*text || x >= max_x) return x;
	uint32_t cur_x = x;
	uint32_t state = 0, codepoint = 0, last_cp = 0;
	for (const char *p = text; *p; p++) {
		if (utf8_decode(&state, &codepoint, (uint8_t)*p))
			continue;
		const struct fcft_glyph *g =
			fcft_rasterize_char_utf32(font, codepoint, FCFT_SUBPIXEL_NONE);
		if (!g) continue;
		long kern = 0;
		if (last_cp) fcft_kerning(font, last_cp, codepoint, &kern, NULL);
		uint32_t advance = g->advance.x + kern;
		if (cur_x + advance + 4 > max_x) break;
		last_cp = codepoint;

		if (pixman_image_get_format(g->pix) == PIXMAN_a8r8g8b8) {
			pixman_image_composite32(PIXMAN_OP_OVER, g->pix, NULL, fg,
				0, 0, 0, 0, cur_x + g->x, y - g->y, g->width, g->height);
		} else {
			pixman_image_fill_boxes(PIXMAN_OP_OVER, fg, fg_color, 1,
				&(pixman_box32_t){.x1 = cur_x, .x2 = cur_x + advance,
				                  .y1 = 0,     .y2 = buf_h});
		}
		pixman_image_composite32(PIXMAN_OP_OVER, g->pix, white_solid, fg_mask,
			0, 0, 0, 0, cur_x + g->x, y - g->y, g->width, g->height);
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
		if (g) w += g->advance.x;
	}
	return w;
}

static void update_layout(void) {
	layout_bw    = text_width(battery_str);
	layout_tw    = text_width(time_str);
	layout_uw    = text_width(upd_str);
	layout_dirty = false;
}

static void clear_image(pixman_image_t *img, int32_t w, int32_t h) {
	static pixman_color_t transparent = {0, 0, 0, 0};
	pixman_image_fill_boxes(PIXMAN_OP_SRC, img, &transparent, 1,
		&(pixman_box32_t){0, 0, w, h});
}

static bool ensure_temp_image(pixman_image_t **img, pixman_format_code_t format,
                              uint32_t *old_w, uint32_t *old_h,
                              uint32_t w, uint32_t h, uint32_t stride) {
	if (*img && *old_w == w && *old_h == h)
		return true;
	if (*img) pixman_image_unref(*img);
	*img = pixman_image_create_bits(format, w, h, NULL, stride);
	*old_w = w;
	*old_h = h;
	return *img != NULL;
}

static void draw_bar(Bar *bar) {
	if (layout_dirty) update_layout();

	BufferSlot *slot = bar_next_slot(bar);
	if (!slot) return;
	pixman_image_t *final = slot->image;
	clear_image(final, bar->width, bar->height);

	uint32_t y = bar->height - font->descent;

	uint32_t bw      = layout_bw;
	uint32_t tw      = layout_tw;
	uint32_t uw      = layout_uw;
	uint32_t total_w = bw + tw + uw;
	uint32_t cx      = (bar->width > total_w) ? (bar->width - total_w) / 2 : 0;

	int32_t hpad = CORNER_RADIUS;
	int32_t wx   = (int32_t)cx - hpad;
	int32_t ww   = (int32_t)total_w + 2 * hpad;
	if (wx < 0) { ww += wx; wx = 0; }

	int32_t bh = (int32_t)bar->height;
	int32_t bcr = BOTTOM_CORNER_RADIUS;
	int32_t bg_x = wx - bcr;
	int32_t bg_right = wx + ww + bcr;
	if (bg_x < 0) bg_x = 0;
	if (bg_right > (int32_t)bar->width) bg_right = (int32_t)bar->width;
	uint32_t local_w = bg_right > bg_x ? (uint32_t)(bg_right - bg_x) : 1;

	if (!ensure_temp_image(&bar->fg, PIXMAN_a8r8g8b8, &bar->fg_w, &bar->fg_h,
	                       local_w, bar->height, local_w * 4))
		return;
	if (!ensure_temp_image(&bar->fg_mask, PIXMAN_a8, &bar->mask_w, &bar->mask_h,
	                       local_w, bar->height, (local_w + 3) & ~3u))
		return;
	if (!ensure_temp_image(&bar->bg, PIXMAN_a8r8g8b8, &bar->bg_w, &bar->bg_h,
	                       local_w * BGSS, bh * BGSS, local_w * 4 * BGSS))
		return;

	pixman_image_t *fg = bar->fg;
	pixman_image_t *fg_mask = bar->fg_mask;
	pixman_image_t *bg = bar->bg;
	clear_image(fg, local_w, bar->height);
	clear_image(fg_mask, local_w, bar->height);
	clear_image(bg, local_w * BGSS, bh * BGSS);

	int32_t S   = BGSS;
	int32_t OLS = OUTLINE_SIZE * BGSS;
	int32_t ir  = CORNER_RADIUS > OUTLINE_SIZE ? CORNER_RADIUS - OUTLINE_SIZE : 0;

	/* Outer outline: absolute coords, top rounded, sides stop before bottom arc zone */
	fill_top_rrect(bg, &outline_color,
		(wx - bg_x) * S, 0, ww * S, bh * S,
		CORNER_RADIUS * S, arc_top_outer,
		(bh - bcr) * S, PIXMAN_OP_OVER);

	/* Inner fill: absolute coords, covers almost to bottom */
	fill_top_rrect(bg, &clock_bg,
		(wx - bg_x + OUTLINE_SIZE) * S, OLS,
		(ww - 2 * OUTLINE_SIZE) * S, (bh - OUTLINE_SIZE) * S,
		ir * S, arc_top_inner,
		(bh - OUTLINE_SIZE) * S, PIXMAN_OP_SRC);

	/* Concave bottom corner arcs — outline extends outside widget boundary */
	{
			int32_t r     = bcr * S;
			int32_t bhs   = bh  * S;
			int32_t wxs   = (wx - bg_x) * S;
			int32_t ols   = OLS;
			int32_t right = (wx - bg_x + ww) * S;
			int32_t bws   = (int32_t)local_w * S;

		for (int32_t dy = 0; dy < r; dy++) {
			int32_t reach = arc_bot[dy];
			int32_t row   = (bhs - r) + dy;

			int32_t ax_l = wxs + ols - r + reach;
			{ int32_t x0 = ax_l < 0 ? 0 : ax_l, x1 = wxs + ols;
			  if (x0 < x1) pixman_image_fill_boxes(PIXMAN_OP_SRC, bg, &clock_bg, 1,
			      &(pixman_box32_t){x0, row, x1, row+1}); }
			{ int32_t x0 = ax_l - ols < 0 ? 0 : ax_l - ols, x1 = ax_l < 0 ? 0 : ax_l;
			  if (x0 < x1) pixman_image_fill_boxes(PIXMAN_OP_OVER, bg, &outline_color, 1,
			      &(pixman_box32_t){x0, row, x1, row+1}); }

			int32_t ax_r = right - ols + r - reach;
			{ int32_t x0 = right - ols, x1 = ax_r > bws ? bws : ax_r;
			  if (x0 < x1) pixman_image_fill_boxes(PIXMAN_OP_SRC, bg, &clock_bg, 1,
			      &(pixman_box32_t){x0, row, x1, row+1}); }
			{ int32_t x0 = ax_r, x1 = ax_r + ols > bws ? bws : ax_r + ols;
			  if (x0 < x1) pixman_image_fill_boxes(PIXMAN_OP_OVER, bg, &outline_color, 1,
			      &(pixman_box32_t){x0, row, x1, row+1}); }
		}
	}

	/* Scale bg BGSS×→1× with bilinear filter; composite full width */
	{
		pixman_transform_t xform;
		pixman_transform_init_scale(&xform,
			pixman_int_to_fixed(BGSS), pixman_int_to_fixed(BGSS));
		pixman_image_set_transform(bg, &xform);
		pixman_image_set_filter(bg, PIXMAN_FILTER_BILINEAR, NULL, 0);
	}
	pixman_image_composite32(PIXMAN_OP_OVER, bg, NULL, final,
		0, 0, 0, 0, bg_x, 0, local_w, bh);

	/* Draw text segments */
	uint32_t x = cx - bg_x;
	if (bw > 0)
		draw_text(battery_str, x,          y, fg, fg_mask, &battery_fg,
		          local_w, bar->height);
	draw_text(time_str,    x + bw,      y, fg, fg_mask, &clock_fg,
	          local_w, bar->height);
	draw_text(upd_str,     x + bw + tw, y, fg, fg_mask, &updates_fg,
	          local_w, bar->height);

	pixman_image_composite32(PIXMAN_OP_OVER, fg, fg_mask, final,
		0, 0, 0, 0, bg_x, 0, local_w, bar->height);

	wl_surface_set_buffer_scale(bar->wl_surface, buffer_scale);
	wl_surface_attach(bar->wl_surface, slot->buffer, 0, 0);
	wl_surface_damage_buffer(bar->wl_surface, 0, 0, bar->width, bar->height);
	slot->busy = true;
	wl_surface_commit(bar->wl_surface);
}

/* ---- bar lifecycle ---- */

static void bar_destroy(Bar *bar) {
	if (bar->layer_surface) zwlr_layer_surface_v1_destroy(bar->layer_surface);
	if (bar->wl_surface)    wl_surface_destroy(bar->wl_surface);
	if (bar->wl_output)     wl_output_destroy(bar->wl_output);
	for (size_t i = 0; i < 2; i++) buffer_slot_destroy(&bar->slots[i]);
	if (bar->fg) pixman_image_unref(bar->fg);
	if (bar->fg_mask) pixman_image_unref(bar->fg_mask);
	if (bar->bg) pixman_image_unref(bar->bg);
	wl_list_remove(&bar->link);
	free(bar);
}

/* ---- layer shell callbacks ---- */

static void layer_surface_configure(void *data,
                                    struct zwlr_layer_surface_v1 *surface,
                                    uint32_t serial, uint32_t w, uint32_t h) {
	Bar *bar = data;
	zwlr_layer_surface_v1_ack_configure(surface, serial);
	if (bar->configured && w == bar->width && h == bar->height)
		return;
	bar->width   = w * buffer_scale;
	bar->height  = h * buffer_scale;
	bar->stride  = bar->width * 4;
	bar->bufsize = bar->stride * bar->height;
	bar->configured = true;
	draw_bar(bar);
}

static void layer_surface_closed(void *data,
                                 struct zwlr_layer_surface_v1 *surface) {
	(void)surface;
	bar_destroy((Bar *)data);
}

static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
	.configure = layer_surface_configure,
	.closed    = layer_surface_closed,
};

/* ---- registry callbacks ---- */

static void registry_global(void *data, struct wl_registry *registry,
                            uint32_t name, const char *interface,
                            uint32_t version) {
	(void)data; (void)version;
	if (strcmp(interface, wl_compositor_interface.name) == 0)
		compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
	else if (strcmp(interface, wl_shm_interface.name) == 0)
		shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
	else if (strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0)
		layer_shell = wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, 1);
	else if (strcmp(interface, wl_output_interface.name) == 0) {
		Bar *bar = calloc(1, sizeof(Bar));
		bar->registry_name = name;
		bar->wl_output = wl_registry_bind(registry, name, &wl_output_interface, 1);
		bar->height     = bar_height * buffer_scale;
		bar->wl_surface = wl_compositor_create_surface(compositor);
		bar->layer_surface = zwlr_layer_shell_v1_get_layer_surface(
			layer_shell, bar->wl_surface, bar->wl_output,
			ZWLR_LAYER_SHELL_V1_LAYER_TOP, "mangobar");
		zwlr_layer_surface_v1_add_listener(bar->layer_surface,
			&layer_surface_listener, bar);
		zwlr_layer_surface_v1_set_size(bar->layer_surface, 0, bar_height);
		zwlr_layer_surface_v1_set_anchor(bar->layer_surface,
			ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
			ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT   |
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
	(void)data; (void)registry;
	Bar *bar, *tmp;
	wl_list_for_each_safe(bar, tmp, &bar_list, link)
		if (bar->registry_name == name) { bar_destroy(bar); return; }
}

static const struct wl_registry_listener registry_listener = {
	.global        = registry_global,
	.global_remove = registry_global_remove,
};

/* ---- state updates ---- */

static void update_battery_str(void) {
	/* Find battery paths once; reuse on subsequent calls. */
	if (!bat_capacity_path[0]) {
		DIR *dir = opendir("/sys/class/power_supply");
		if (!dir) return;
		char bat[64] = "";
		struct dirent *ent;
		while ((ent = readdir(dir)))
			if (strncmp(ent->d_name, "BAT", 3) == 0) {
				size_t nl = strlen(ent->d_name);
				if (nl < sizeof(bat)) memcpy(bat, ent->d_name, nl + 1);
				break;
			}
		closedir(dir);
		if (!bat[0]) return;
		snprintf(bat_capacity_path, sizeof(bat_capacity_path),
			"/sys/class/power_supply/%s/capacity", bat);
		snprintf(bat_status_path, sizeof(bat_status_path),
			"/sys/class/power_supply/%s/status", bat);
	}

	int capacity = -1;
	FILE *f = fopen(bat_capacity_path, "r");
	if (f) { fscanf(f, "%d", &capacity); fclose(f); }
	if (capacity < 0) return;

	int charging = 0;
	f = fopen(bat_status_path, "r");
	if (f) {
		char st[16];
		if (fgets(st, sizeof(st), f))
			charging = (strncmp(st, "Charging", 8) == 0 ||
			            strncmp(st, "Full",     4) == 0);
		fclose(f);
	}

	static const char *bat_icons[10] = {
		BAT_10, BAT_20, BAT_30, BAT_40, BAT_50,
		BAT_60, BAT_70, BAT_80, BAT_90, BAT_100
	};
	static const char *bat_chg_icons[10] = {
		BAT_10_CHG, BAT_20_CHG, BAT_30_CHG, BAT_40_CHG, BAT_50_CHG,
		BAT_60_CHG, BAT_70_CHG, BAT_80_CHG, BAT_90_CHG, BAT_100_CHG
	};
	int lvl = (capacity - 5) / 10;
	if (lvl < 0) lvl = 0;
	if (lvl > 9) lvl = 9;
	snprintf(battery_str, sizeof(battery_str), "%s %d%% ",
		charging ? bat_chg_icons[lvl] : bat_icons[lvl], capacity);
}

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

static void refresh_upd_str(time_t now) {
	if (updates_count < 0 ||
	    (updates_pid != -1 && now - updates_last_launch > 65 * 60))
		snprintf(upd_str, sizeof(upd_str), " %s", UPDATES_FETCH);
	else
		snprintf(upd_str, sizeof(upd_str), " %s %d", UPDATES_ICON, updates_count);
}

static void update_time(void) {
	update_battery_str();
	time_t     now = time(NULL);
	struct tm *tm  = localtime(&now);
	char ts[16];
	strftime(ts, sizeof(ts), "%H:%M", tm);
	snprintf(time_str, sizeof(time_str), "%s %s",
		get_time_icon(tm->tm_hour, tm->tm_min), ts);
	refresh_upd_str(now);
	layout_dirty = true;
}

static void redraw_all(void) {
	Bar *b;
	wl_list_for_each(b, &bar_list, link)
		if (b->configured) draw_bar(b);
}

/* ---- updates subprocess (no /bin/sh, no wc) ---- */

/* Count newlines in the stdout of prog/argv. Blocking — call only from a child. */
static int count_output_lines(const char *prog, char *const argv[]) {
	int p[2];
	if (pipe2(p, O_CLOEXEC) < 0) return 0;
	pid_t pid = fork();
	if (pid < 0) { close(p[0]); close(p[1]); return 0; }
	if (pid == 0) {
		close(p[0]);
		dup2(p[1], STDOUT_FILENO);
		close(p[1]);
		int dn = open("/dev/null", O_WRONLY);
		if (dn >= 0) { dup2(dn, STDERR_FILENO); close(dn); }
		execvp(prog, argv);
		_exit(0);
	}
	close(p[1]);
	int count = 0;
	char buf[256]; ssize_t n;
	while ((n = read(p[0], buf, sizeof(buf))) > 0)
		for (ssize_t i = 0; i < n; i++)
			if (buf[i] == '\n') count++;
	close(p[0]);
	int ws; waitpid(pid, &ws, 0);
	return count;
}

static void updates_launch(void) {
	int pipefd[2];
	if (pipe2(pipefd, O_CLOEXEC | O_NONBLOCK) < 0) return;
	pid_t pid = fork();
	if (pid < 0) { close(pipefd[0]); close(pipefd[1]); return; }
	if (pid == 0) {
		/* Intermediate child: runs checkupdates + yay directly, writes total. */
		close(pipefd[0]);
		char *cu_argv[]  = {"checkupdates", NULL};
		char *yay_argv[] = {"yay", "-Qua", NULL};
		int total = count_output_lines("checkupdates", cu_argv)
		          + count_output_lines("yay",          yay_argv);
		char out[16];
		int  len = snprintf(out, sizeof(out), "%d\n", total);
		write(pipefd[1], out, len);
		close(pipefd[1]);
		_exit(0);
	}
	close(pipefd[1]);
	updates_pipe_fd     = pipefd[0];
	updates_pid         = pid;
	updates_last_launch = time(NULL);
}

/* ---- event loop ---- */

static void event_loop(void) {
	int    wl_fd    = wl_display_get_fd(display);
	time_t last_min = time(NULL) / 60;

	while (running) {
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

		/* Updates child finished: read result, refresh display string, redraw. */
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
			refresh_upd_str(now);
			layout_dirty = true;
			redraw_all();
		}

		/* Minute boundary: update time, maybe relaunch updates check. */
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

/* ---- arc precomputation ---- */

static void precompute_arcs(void) {
	/* Top outer corners: r = CORNER_RADIUS * BGSS */
	{
		int32_t r = CORNER_RADIUS * BGSS;
		for (int32_t dy = 0; dy < r; dy++) {
			float   vy = (float)r - dy - 0.5f;
			int32_t nx = (int32_t)(sqrtf((float)(r * r) - vy * vy) + 0.5f);
			arc_top_outer[dy] = nx > r ? r : (nx < 1 ? 1 : nx);
		}
	}
	/* Top inner corners: r = (CORNER_RADIUS - OUTLINE_SIZE) * BGSS */
	{
		int32_t r = (CORNER_RADIUS - OUTLINE_SIZE) * BGSS;
		for (int32_t dy = 0; dy < r; dy++) {
			float   vy = (float)r - dy - 0.5f;
			int32_t nx = (int32_t)(sqrtf((float)(r * r) - vy * vy) + 0.5f);
			arc_top_inner[dy] = nx > r ? r : (nx < 1 ? 1 : nx);
		}
	}
	/* Bottom concave arc: large reach at dy=0 (near arc center), shrinks toward bottom edge */
	{
		int32_t r = BOTTOM_CORNER_RADIUS * BGSS;
		for (int32_t dy = 0; dy < r; dy++) {
			float   delta = (float)dy + 0.5f;
			int32_t reach = (int32_t)(sqrtf((float)(r * r) - delta * delta) + 0.5f);
			arc_bot[dy] = reach > r ? r : reach;
		}
	}
}

/* ---- main ---- */

int main(void) {
	fcft_init(FCFT_LOG_COLORIZE_AUTO, 0, FCFT_LOG_CLASS_ERROR);
	font = fcft_from_name(1, (const char *[]){fontstr}, NULL);
	if (!font) { fprintf(stderr, "Failed to load fonts\n"); return 1; }

	hex_to_pixman(clock_fg_color_hex,   &clock_fg);
	hex_to_pixman(clock_bg_color_hex,   &clock_bg);
	hex_to_pixman(updates_fg_color_hex, &updates_fg);
	hex_to_pixman(battery_fg_color_hex, &battery_fg);
	hex_to_pixman(outline_color_hex,    &outline_color);

	white_solid = pixman_image_create_solid_fill(
		&(pixman_color_t){0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF});

	precompute_arcs();

	display = wl_display_connect(NULL);
	if (!display) { fcft_destroy(font); fcft_fini(); return 1; }
	wl_list_init(&bar_list);

	struct wl_registry *registry = wl_display_get_registry(display);
	wl_registry_add_listener(registry, &registry_listener, NULL);
	wl_display_roundtrip(display);

	if (!compositor || !shm || !layer_shell) {
		fcft_destroy(font); fcft_fini();
		wl_display_disconnect(display);
		return 1;
	}
	wl_display_roundtrip(display);

	update_time();
	updates_launch();
	signal(SIGTERM, exit);
	signal(SIGINT,  exit);

	event_loop();

	fcft_destroy(font);
	fcft_fini();
	wl_display_disconnect(display);
	return 0;
}
