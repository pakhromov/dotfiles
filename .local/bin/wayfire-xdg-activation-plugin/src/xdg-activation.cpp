#include <wayfire/plugin.hpp>
#include <wayfire/core.hpp>
#include <wayfire/view.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/window-manager.hpp>
#include <unordered_set>
#include <string>
#include <random>
#include "xdg-activation-v1-protocol.h"

class wayfire_xdg_activation : public wf::plugin_interface_t
{
  public:
    void init() override
    {
        global = wl_global_create(wf::get_core().display,
            &xdg_activation_v1_interface, 1, this, bind_manager);
    }

    void fini() override
    {
        if (global)
        {
            wl_global_destroy(global);
            global = nullptr;
        }
    }

    bool is_unloadable() override { return false; }

  private:
    struct wl_global *global = nullptr;
    std::unordered_set<std::string> tokens;

    static std::string generate_token()
    {
        static std::mt19937_64 rng{std::random_device{}()};
        char buf[33];
        snprintf(buf, sizeof(buf), "%016llx%016llx",
            (unsigned long long)rng(), (unsigned long long)rng());
        return buf;
    }

    static void token_set_serial (wl_client *, wl_resource *, uint32_t, wl_resource *) {}
    static void token_set_app_id (wl_client *, wl_resource *, const char *) {}
    static void token_set_surface(wl_client *, wl_resource *, wl_resource *) {}
    static void token_destroy    (wl_client *, wl_resource *r) { wl_resource_destroy(r); }

    static void token_commit(wl_client *, wl_resource *r)
    {
        auto *self = static_cast<wayfire_xdg_activation *>(wl_resource_get_user_data(r));
        if (!self) return;
        std::string tok = generate_token();
        self->tokens.insert(tok);
        xdg_activation_token_v1_send_done(r, tok.c_str());
        wl_resource_set_user_data(r, nullptr);
    }

    static constexpr struct xdg_activation_token_v1_interface token_impl = {
        .set_serial  = token_set_serial,
        .set_app_id  = token_set_app_id,
        .set_surface = token_set_surface,
        .commit      = token_commit,
        .destroy     = token_destroy,
    };

    static void manager_destroy(wl_client *, wl_resource *r) { wl_resource_destroy(r); }

    static void manager_get_activation_token(wl_client *client,
        wl_resource *manager, uint32_t id)
    {
        auto *self = static_cast<wayfire_xdg_activation *>(wl_resource_get_user_data(manager));
        auto *r = wl_resource_create(client, &xdg_activation_token_v1_interface,
            wl_resource_get_version(manager), id);
        if (!r) { wl_client_post_no_memory(client); return; }
        wl_resource_set_implementation(r, &token_impl, self, nullptr);
    }

    static void manager_activate(wl_client *, wl_resource *manager,
        const char *token, wl_resource *surface)
    {
        auto *self = static_cast<wayfire_xdg_activation *>(wl_resource_get_user_data(manager));
        if (!self || !self->tokens.erase(token)) return;
        auto view = wf::wl_surface_to_wayfire_view(surface);
        if (!view) return;
        auto toplevel = wf::toplevel_cast(view);
        if (!toplevel) return;
        wf::get_core().default_wm->focus_request(toplevel);
    }

    static constexpr struct xdg_activation_v1_interface manager_impl = {
        .destroy              = manager_destroy,
        .get_activation_token = manager_get_activation_token,
        .activate             = manager_activate,
    };

    static void bind_manager(wl_client *client, void *data,
        uint32_t version, uint32_t id)
    {
        auto *r = wl_resource_create(client, &xdg_activation_v1_interface, version, id);
        if (!r) { wl_client_post_no_memory(client); return; }
        wl_resource_set_implementation(r, &manager_impl, data, nullptr);
    }
};

DECLARE_WAYFIRE_PLUGIN(wayfire_xdg_activation);
