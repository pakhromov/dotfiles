/* Simple Wayland client to focus a window by app_id using foreign-toplevel protocol */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

struct state {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_seat *seat;
    struct zwlr_foreign_toplevel_manager_v1 *manager;
    char *target_app_id;
    int found;
};

static void toplevel_handle_title(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, const char *title) {}
static void toplevel_handle_app_id(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, const char *app_id) {
    struct state *state = data;
    if (strcmp(app_id, state->target_app_id) == 0) {
        zwlr_foreign_toplevel_handle_v1_activate(handle, state->seat);
        state->found = 1;
    }
}
static void toplevel_handle_output_enter(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_output *output) {}
static void toplevel_handle_output_leave(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_output *output) {}
static void toplevel_handle_state(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_array *state) {}
static void toplevel_handle_done(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle) {
    struct state *state = data;
    if (state->found) {
        wl_display_roundtrip(state->display);
    }
}
static void toplevel_handle_closed(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle) {
    zwlr_foreign_toplevel_handle_v1_destroy(handle);
}
static void toplevel_handle_parent(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct zwlr_foreign_toplevel_handle_v1 *parent) {}

static const struct zwlr_foreign_toplevel_handle_v1_listener toplevel_listener = {
    .title = toplevel_handle_title,
    .app_id = toplevel_handle_app_id,
    .output_enter = toplevel_handle_output_enter,
    .output_leave = toplevel_handle_output_leave,
    .state = toplevel_handle_state,
    .done = toplevel_handle_done,
    .closed = toplevel_handle_closed,
    .parent = toplevel_handle_parent,
};

static void manager_handle_toplevel(void *data, struct zwlr_foreign_toplevel_manager_v1 *manager,
        struct zwlr_foreign_toplevel_handle_v1 *toplevel) {
    struct state *state = data;
    zwlr_foreign_toplevel_handle_v1_add_listener(toplevel, &toplevel_listener, state);
}

static void manager_handle_finished(void *data, struct zwlr_foreign_toplevel_manager_v1 *manager) {
    zwlr_foreign_toplevel_manager_v1_destroy(manager);
}

static const struct zwlr_foreign_toplevel_manager_v1_listener manager_listener = {
    .toplevel = manager_handle_toplevel,
    .finished = manager_handle_finished,
};

static void registry_handle_global(void *data, struct wl_registry *registry,
        uint32_t name, const char *interface, uint32_t version) {
    struct state *state = data;
    if (strcmp(interface, zwlr_foreign_toplevel_manager_v1_interface.name) == 0) {
        state->manager = wl_registry_bind(registry, name, &zwlr_foreign_toplevel_manager_v1_interface, 3);
        zwlr_foreign_toplevel_manager_v1_add_listener(state->manager, &manager_listener, state);
    } else if (strcmp(interface, wl_seat_interface.name) == 0) {
        state->seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    }
}

static void registry_handle_global_remove(void *data, struct wl_registry *registry, uint32_t name) {}

static const struct wl_registry_listener registry_listener = {
    .global = registry_handle_global,
    .global_remove = registry_handle_global_remove,
};

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <app_id>\n", argv[0]);
        return 1;
    }

    struct state state = {0};
    state.target_app_id = argv[1];

    state.display = wl_display_connect(NULL);
    if (!state.display) {
        fprintf(stderr, "Failed to connect to Wayland display\n");
        return 1;
    }

    state.registry = wl_display_get_registry(state.display);
    wl_registry_add_listener(state.registry, &registry_listener, &state);
    wl_display_roundtrip(state.display);

    if (!state.manager || !state.seat) {
        fprintf(stderr, "Compositor doesn't support required protocols\n");
        wl_display_disconnect(state.display);
        return 1;
    }

    wl_display_roundtrip(state.display);
    wl_display_disconnect(state.display);

    return state.found ? 0 : 1;
}
