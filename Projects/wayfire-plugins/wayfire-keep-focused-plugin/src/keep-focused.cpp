#include <wayfire/core.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/output.hpp>
#include <wayfire/output-layout.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/view.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/workspace-set.hpp>
#include <wayfire/scene.hpp>
#include <wayfire/scene-operations.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>
#include <wayfire/plugins/ipc/ipc-helpers.hpp>
#include <wayfire/unstable/wlr-view-keyboard-interaction.hpp>
#include <map>

namespace wf
{
namespace keep_focused
{
/**
 * A scenegraph node which always claims keyboard focus with HIGH importance
 * (regular views only get REGULAR), and forwards keyboard events to the
 * target view. It ignores the output being refocused, so the view keeps
 * focus even when another output becomes active.
 */
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
} // namespace keep_focused
} // namespace wf

class keep_focused_plugin : public wf::plugin_interface_t
{
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> ipc_repo;

    struct kept_view_t
    {
        std::shared_ptr<wf::keep_focused::keep_focused_node_t> node;
        wf::view_role_t original_role;
    };

    std::map<wayfire_view, kept_view_t> views;

    /*
     * Kept views are shown on all workspaces: like pin-view's overlay mode,
     * the view is taken out of its workspace set, its role is changed to
     * DESKTOP_ENVIRONMENT and its root node is moved to the OVERLAY layer.
     * On every workspace switch the view is moved so it stays in place.
     */
    void keep_view(wayfire_view view, wf::output_t *output)
    {
        kept_view_t kept;
        kept.original_role = view->role;
        kept.node = std::make_shared<wf::keep_focused::keep_focused_node_t>(view);

        view->role = wf::VIEW_ROLE_DESKTOP_ENVIRONMENT;
        if (auto toplevel = wf::toplevel_cast(view))
        {
            /* Bring the view to the current viewport before unlinking it from
             * the workspace set. Core's helper works on the pending geometry
             * and does nothing if the view is already visible, so it does not
             * clobber a geometry which another plugin has just set. */
            auto wset = output->wset();
            wset->move_to_workspace(toplevel, wset->get_current_workspace());
            wset->remove_view(toplevel);
        }

        wf::scene::readd_front(output->node_for_layer(wf::scene::layer::OVERLAY),
            view->get_root_node());
        wf::scene::add_front(output->node_for_layer(wf::scene::layer::OVERLAY), kept.node);
        views[view] = kept;
    }

    /*
     * Undo keep_view(). For still-mapped views (explicit disable via IPC),
     * the view goes back to the workspace set on the workspace it is
     * currently visible on. For unmapping views only the focus node needs
     * to be removed.
     */
    bool release_view(wayfire_view view)
    {
        auto it = views.find(view);
        if (it == views.end())
        {
            return false;
        }

        wf::scene::remove_child(it->second.node);
        view->role = it->second.original_role;
        auto output = view->get_output();
        if (view->is_mapped() && output)
        {
            wf::scene::readd_front(output->wset()->get_node(), view->get_root_node());
            if (auto toplevel = wf::toplevel_cast(view))
            {
                output->wset()->add_view(toplevel);
            }
        }

        views.erase(it);
        return true;
    }

    wf::signal::connection_t<wf::view_unmapped_signal> on_view_unmapped = [=] (wf::view_unmapped_signal *ev)
    {
        if (release_view(ev->view))
        {
            wf::get_core().seat->refocus();
        }
    };

    /* Kept views are outside the workspace set, so core does not shift them
     * on workspace switches - normally they stay in place on screen without
     * our help. This pulls back in any view which is somehow not visible. */
    wf::signal::connection_t<wf::workspace_changed_signal> on_workspace_changed =
        [=] (wf::workspace_changed_signal *ev)
    {
        for (auto& [view, kept] : views)
        {
            if (view->get_output() != ev->output)
            {
                continue;
            }

            if (auto toplevel = wf::toplevel_cast(view))
            {
                ev->output->wset()->move_to_workspace(toplevel, ev->new_viewport);
            }
        }
    };

    wf::signal::connection_t<wf::output_added_signal> on_output_added = [=] (wf::output_added_signal *ev)
    {
        ev->output->connect(&on_workspace_changed);
    };

    wf::ipc::method_callback on_ipc_set = [=] (wf::json_t data) -> wf::json_t
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
            if (!views.count(view))
            {
                auto output = view->get_output();
                if (!output)
                {
                    return wf::ipc::json_error("view has no output");
                }

                keep_view(view, output);
            }
        } else
        {
            release_view(view);
        }

        wf::get_core().seat->refocus();
        return wf::ipc::json_ok();
    };

  public:
    void init() override
    {
        ipc_repo->register_method("keep-focused/set", on_ipc_set);
        wf::get_core().connect(&on_view_unmapped);
        wf::get_core().output_layout->connect(&on_output_added);
        for (auto& output : wf::get_core().output_layout->get_outputs())
        {
            output->connect(&on_workspace_changed);
        }
    }

    void fini() override
    {
        ipc_repo->unregister_method("keep-focused/set");
        on_view_unmapped.disconnect();
        on_output_added.disconnect();
        on_workspace_changed.disconnect();

        bool had_views = !views.empty();
        while (!views.empty())
        {
            release_view(views.begin()->first);
        }

        if (had_views)
        {
            wf::get_core().seat->refocus();
        }
    }
};

DECLARE_WAYFIRE_PLUGIN(keep_focused_plugin);
