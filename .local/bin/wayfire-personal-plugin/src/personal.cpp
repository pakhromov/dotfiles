#include <wayfire/core.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/output.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/view.hpp>
#include <wayfire/scene.hpp>
#include <wayfire/scene-operations.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>
#include <wayfire/plugins/ipc/ipc-helpers.hpp>
#include <wayfire/unstable/wlr-view-keyboard-interaction.hpp>
#include <wayfire/nonstd/wlroots-full.hpp>
#include <ctime>
#include <vector>

namespace wf
{
namespace personal
{
class keep_focused_node_t : public wf::scene::node_t
{
    std::weak_ptr<wf::view_interface_t> view;
    std::unique_ptr<wf::wlr_view_keyboard_interaction_t> kb_interaction;

  public:
    keep_focused_node_t(wayfire_view view) : node_t(false)
    {
        this->view = view->weak_from_this();
        this->kb_interaction = std::make_unique<wf::wlr_view_keyboard_interaction_t>(view);
    }

    wf::keyboard_focus_node_t keyboard_refocus(wf::output_t *output) override
    {
        auto v = view.lock();
        if (!v || !v->is_mapped())
        {
            return wf::keyboard_focus_node_t{};
        }

        return wf::keyboard_focus_node_t{
            this, wf::focus_importance::HIGH, /* allow_focus_below */ false
        };
    }

    wf::keyboard_interaction_t& keyboard_interaction() override
    {
        return *kb_interaction;
    }
};
} // namespace personal
} // namespace wf

class personal_plugin : public wf::plugin_interface_t
{
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> ipc_repo;

    // ---- hide-cursor ----
    // Connected only between a "hide-cursor" call and the next pointer
    // motion. Nothing is connected the rest of the time.
    wf::signal::connection_t<wf::input_event_signal<wlr_pointer_motion_event>> on_motion =
        [=] (wf::input_event_signal<wlr_pointer_motion_event>*)
    {
        on_motion.disconnect();
        wf::get_core().unhide_cursor();
    };

    wf::ipc::method_callback on_ipc_hide_cursor = [=] (wf::json_t)
    {
        wf::get_core().hide_cursor();

        on_motion.disconnect();
        wf::get_core().connect(&on_motion);

        return wf::ipc::json_ok();
    };

    // ---- inject-key ----
    wf::ipc::method_callback on_ipc_inject_key = [=] (wf::json_t data) -> wf::json_t
    {
        auto keycode = wf::ipc::json_get_uint64(data, "keycode");

        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        uint32_t msec = (uint32_t)(now.tv_sec * 1000 + now.tv_nsec / 1000000);

        auto *seat = wf::get_core().seat->seat;
        auto *kbd  = wlr_seat_get_keyboard(seat);
        if (!kbd)
        {
            return wf::ipc::json_error("no keyboard");
        }

        std::vector<uint32_t> mods;
        if (data.has_member("modifiers") && data["modifiers"].is_array())
        {
            size_t n = data["modifiers"].size();
            for (size_t i = 0; i < n; i++)
            {
                mods.push_back((uint32_t)data["modifiers"][i].as_uint64());
            }
        }

        struct wlr_keyboard_modifiers orig_mods = kbd->modifiers;

        if (!mods.empty())
        {
            for (uint32_t mod : mods)
            {
                xkb_state_update_key(kbd->xkb_state, mod + 8, XKB_KEY_DOWN);
            }

            struct wlr_keyboard_modifiers new_mods = {
                .depressed = xkb_state_serialize_mods(kbd->xkb_state, XKB_STATE_MODS_DEPRESSED),
                .latched   = xkb_state_serialize_mods(kbd->xkb_state, XKB_STATE_MODS_LATCHED),
                .locked    = xkb_state_serialize_mods(kbd->xkb_state, XKB_STATE_MODS_LOCKED),
                .group     = xkb_state_serialize_layout(kbd->xkb_state, XKB_STATE_LAYOUT_EFFECTIVE),
            };
            kbd->modifiers = new_mods;
            wlr_seat_keyboard_notify_modifiers(seat, &new_mods);
        }

        wlr_seat_keyboard_notify_key(seat, msec, (uint32_t)keycode, WL_KEYBOARD_KEY_STATE_PRESSED);
        wlr_seat_keyboard_notify_key(seat, msec, (uint32_t)keycode, WL_KEYBOARD_KEY_STATE_RELEASED);

        if (!mods.empty())
        {
            for (auto it = mods.rbegin(); it != mods.rend(); ++it)
            {
                xkb_state_update_key(kbd->xkb_state, *it + 8, XKB_KEY_UP);
            }

            kbd->modifiers = orig_mods;
            wlr_seat_keyboard_notify_modifiers(seat, &orig_mods);
        }

        return wf::ipc::json_ok();
    };

    // ---- keep-focused ----
    std::map<wayfire_view, std::shared_ptr<wf::personal::keep_focused_node_t>> keep_focused_nodes;

    void remove_keep_focused(wayfire_view view)
    {
        auto it = keep_focused_nodes.find(view);
        if (it != keep_focused_nodes.end())
        {
            wf::scene::remove_child(it->second);
            keep_focused_nodes.erase(it);
        }
    }

    wf::signal::connection_t<wf::view_unmapped_signal> on_view_unmapped = [=] (wf::view_unmapped_signal *ev)
    {
        remove_keep_focused(ev->view);
        wf::get_core().seat->refocus();
    };

    wf::ipc::method_callback on_ipc_keep_focused = [=] (wf::json_t data) -> wf::json_t
    {
        auto view_id = wf::ipc::json_get_uint64(data, "view-id");
        auto enabled = wf::ipc::json_get_bool(data, "enabled");

        auto view = wf::ipc::find_view_by_id(view_id);
        if (!view)
        {
            return wf::ipc::json_error("view not found");
        }

        if (enabled)
        {
            if (!keep_focused_nodes.count(view))
            {
                auto output = view->get_output();
                if (!output)
                {
                    return wf::ipc::json_error("view has no output");
                }

                auto node = std::make_shared<wf::personal::keep_focused_node_t>(view);
                wf::scene::add_front(output->node_for_layer(wf::scene::layer::OVERLAY), node);
                keep_focused_nodes[view] = node;
            }
        } else
        {
            remove_keep_focused(view);
        }

        wf::get_core().seat->refocus();
        return wf::ipc::json_ok();
    };

  public:
    void init() override
    {
        ipc_repo->register_method("personal/hide-cursor", on_ipc_hide_cursor);
        ipc_repo->register_method("personal/inject-key", on_ipc_inject_key);
        ipc_repo->register_method("personal/keep-focused", on_ipc_keep_focused);
        wf::get_core().connect(&on_view_unmapped);
    }

    void fini() override
    {
        ipc_repo->unregister_method("personal/hide-cursor");
        ipc_repo->unregister_method("personal/inject-key");
        ipc_repo->unregister_method("personal/keep-focused");
        on_view_unmapped.disconnect();
        on_motion.disconnect();

        for (auto& [view, node] : keep_focused_nodes)
        {
            wf::scene::remove_child(node);
        }

        keep_focused_nodes.clear();
    }
};

DECLARE_WAYFIRE_PLUGIN(personal_plugin);
