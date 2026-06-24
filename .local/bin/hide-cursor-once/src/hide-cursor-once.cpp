#include <wayfire/core.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>

class wayfire_hide_cursor_once : public wf::plugin_interface_t
{
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> ipc_repo;

    // Connected only between a "hide" call and the next pointer motion.
    // Nothing is connected the rest of the time.
    wf::signal::connection_t<wf::input_event_signal<wlr_pointer_motion_event>> on_motion =
        [=] (wf::input_event_signal<wlr_pointer_motion_event>*)
    {
        on_motion.disconnect();
        wf::get_core().unhide_cursor();
    };

    wf::ipc::method_callback on_ipc_hide = [=] (wf::json_t)
    {
        wf::get_core().hide_cursor();

        // Defensive: avoid double-connecting if "hide" is called again
        // before any motion happened since the previous call.
        on_motion.disconnect();
        wf::get_core().connect(&on_motion);

        return wf::ipc::json_ok();
    };

  public:
    void init() override
    {
        ipc_repo->register_method("hide-cursor-once/hide", on_ipc_hide);
    }

    void fini() override
    {
        ipc_repo->unregister_method("hide-cursor-once/hide");
        on_motion.disconnect();
    }
};

DECLARE_WAYFIRE_PLUGIN(wayfire_hide_cursor_once);
