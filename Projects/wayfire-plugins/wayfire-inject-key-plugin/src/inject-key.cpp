#include <wayfire/core.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>
#include <wayfire/plugins/ipc/ipc-helpers.hpp>
#include <wayfire/nonstd/wlroots-full.hpp>
#include <ctime>
#include <vector>

class inject_key_plugin : public wf::plugin_interface_t
{
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> ipc_repo;

    wf::ipc::method_callback on_ipc_press = [=] (wf::json_t data) -> wf::json_t
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

  public:
    void init() override
    {
        ipc_repo->register_method("inject-key/press", on_ipc_press);
    }

    void fini() override
    {
        ipc_repo->unregister_method("inject-key/press");
    }
};

DECLARE_WAYFIRE_PLUGIN(inject_key_plugin);
