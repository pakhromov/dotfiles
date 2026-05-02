#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>
#include <wayland-client.h>
#include "wlr-layer-shell-unstable-v1-client-protocol.h"

/* stub: layer-shell protocol references xdg_popup but we never call get_popup */
extern const struct wl_interface xdg_popup_interface;
const struct wl_interface xdg_popup_interface = { "xdg_popup" };

static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct zwlr_layer_shell_v1 *layer_shell;
static struct wl_surface *surface;
static struct wl_buffer *buffer;

static void registry_global(void *data, struct wl_registry *registry,
    uint32_t name, const char *interface, uint32_t version)
{
    if (strcmp(interface, wl_compositor_interface.name) == 0)
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 1);
    else if (strcmp(interface, wl_shm_interface.name) == 0)
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    else if (strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0)
        layer_shell = wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, 1);
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {}

static const struct wl_registry_listener registry_listener = {
    .global        = registry_global,
    .global_remove = registry_global_remove,
};

static void layer_surface_configure(void *data,
    struct zwlr_layer_surface_v1 *ls, uint32_t serial, uint32_t w, uint32_t h)
{
    zwlr_layer_surface_v1_ack_configure(ls, serial);
    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_damage(surface, 0, 0, 1, 1);
    wl_surface_commit(surface);
}

static void layer_surface_closed(void *data, struct zwlr_layer_surface_v1 *ls)
{
    exit(0);
}

static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
    .configure = layer_surface_configure,
    .closed    = layer_surface_closed,
};

int main(void)
{
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "waypixel: cannot connect to Wayland display\n");
        return 1;
    }

    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    if (!compositor || !shm || !layer_shell) {
        fprintf(stderr, "waypixel: compositor missing required globals\n");
        return 1;
    }

    /* 1x1 ARGB8888 pixel: alpha=1/255, invisible but non-transparent */
    char path[] = "/tmp/waypixel-XXXXXX";
    int fd = mkstemp(path);
    unlink(path);
    uint32_t pixel = 0x01000000;
    write(fd, &pixel, sizeof pixel);

    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, sizeof pixel);
    buffer = wl_shm_pool_create_buffer(pool, 0, 1, 1, 4, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);

    surface = wl_compositor_create_surface(compositor);

    struct zwlr_layer_surface_v1 *ls = zwlr_layer_shell_v1_get_layer_surface(
        layer_shell, surface, NULL,
        ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "waypixel");

    zwlr_layer_surface_v1_set_size(ls, 1, 1);
    zwlr_layer_surface_v1_set_anchor(ls,
        ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    zwlr_layer_surface_v1_set_exclusive_zone(ls, -1);
    zwlr_layer_surface_v1_add_listener(ls, &layer_surface_listener, NULL);

    wl_surface_commit(surface);
    wl_display_roundtrip(display);

    while (wl_display_dispatch(display) != -1) {}

    return 0;
}
