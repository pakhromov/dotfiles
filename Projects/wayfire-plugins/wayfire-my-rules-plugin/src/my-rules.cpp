#include <wayfire/core.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/output.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/view.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/window-manager.hpp>
#include <wayfire/workspace-set.hpp>
#include <wayfire/matcher.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/config/compound-option.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/util.hpp>
#include <wayfire/util/log.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>
#include <wayfire/plugins/ipc/ipc-helpers.hpp>
#include <algorithm>
#include <sstream>
#include <vector>

/*
 * Personal window rules. Syntax:
 *   if <criteria> then assign-focus RC
 *   if <criteria> then set geometry_ppt X Y W H
 *   if <criteria> then keep-focused
 *
 * <criteria> uses the same condition language as core plugins
 * (wf::view_matcher_t), e.g.: app_id contains "mpv" & !(title is "x").
 *
 * RC is a 1-based two-digit workspace: first digit = row, second = column
 * (12 = first row, second column). Works for any grid size up to 9x9.
 *
 * Rules run once, when a parentless toplevel maps. The "open" client can
 * claim the next mapping view beforehand (my-rules/prepare-open), in which
 * case no rules are applied to it.
 */
class my_rules_plugin : public wf::plugin_interface_t
{
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> ipc_repo;

    struct rule_t
    {
        enum class action_t
        {
            ASSIGN_FOCUS,
            SET_GEOMETRY_PPT,
            KEEP_FOCUSED,
        };

        std::shared_ptr<wf::config::option_t<std::string>> condition_opt;
        std::unique_ptr<wf::view_matcher_t> matcher;
        action_t action;
        wf::point_t ws; /* assign-focus, 0-based */
        wf::geometry_t geometry_ppt;
    };

    std::vector<rule_t> rules;

    /* Armed by my-rules/prepare-open: the next parentless toplevel to map
     * belongs to the "open" client and gets no rules applied. */
    bool suppress_armed = false;
    wf::wl_timer<false> suppress_expiry;

    /* Split "if <criteria> then <action>" at the first " then " which is
     * outside of double quotes. Returns false on malformed rules. */
    static bool split_rule(const std::string& text, std::string& criteria, std::string& action)
    {
        const std::string if_kw   = "if ";
        const std::string then_kw = " then ";

        size_t begin = text.find_first_not_of(" \t");
        if ((begin == std::string::npos) || (text.compare(begin, if_kw.size(), if_kw) != 0))
        {
            return false;
        }

        begin += if_kw.size();

        bool in_quotes = false;
        for (size_t i = begin; i + then_kw.size() <= text.size(); i++)
        {
            if (text[i] == '"')
            {
                in_quotes = !in_quotes;
            } else if (!in_quotes && (text.compare(i, then_kw.size(), then_kw) == 0))
            {
                criteria = text.substr(begin, i - begin);
                action   = text.substr(i + then_kw.size());
                return !criteria.empty() && !action.empty();
            }
        }

        return false;
    }

    /* Parse a 1-based two-digit row/column ("12" = row 1, column 2)
     * into a 0-based workspace point. */
    static bool parse_workspace(const std::string& token, wf::point_t& ws)
    {
        if ((token.size() != 2) || !isdigit(token[0]) || !isdigit(token[1]))
        {
            return false;
        }

        int row = token[0] - '0';
        int col = token[1] - '0';
        if ((row < 1) || (col < 1))
        {
            return false;
        }

        ws = wf::point_t{col - 1, row - 1};
        return true;
    }

    void setup_rules_from_config()
    {
        rules.clear();

        wf::option_wrapper_t<wf::config::compound_list_t<std::string>> rule_list{"my-rules/rules"};
        for (const auto& [name, text] : rule_list.value())
        {
            std::string criteria, action_str;
            if (!split_rule(text, criteria, action_str))
            {
                LOGE("my-rules: malformed rule (expected 'if <criteria> then <action>'): ", text);
                continue;
            }

            std::istringstream tokens{action_str};
            std::string verb;
            tokens >> verb;

            rule_t rule;
            if (verb == "assign-focus")
            {
                std::string ws_token;
                tokens >> ws_token;
                if (!parse_workspace(ws_token, rule.ws))
                {
                    LOGE("my-rules: invalid workspace (two digits, 1-based row+column): ", text);
                    continue;
                }

                rule.action = rule_t::action_t::ASSIGN_FOCUS;
            } else if (verb == "set")
            {
                std::string what;
                tokens >> what;
                auto& g = rule.geometry_ppt;
                if ((what != "geometry_ppt") || !(tokens >> g.x >> g.y >> g.width >> g.height))
                {
                    LOGE("my-rules: only 'set geometry_ppt X Y W H' is supported: ", text);
                    continue;
                }

                rule.action = rule_t::action_t::SET_GEOMETRY_PPT;
            } else if (verb == "keep-focused")
            {
                rule.action = rule_t::action_t::KEEP_FOCUSED;
            } else
            {
                LOGE("my-rules: unknown action '", verb, "' in rule: ", text);
                continue;
            }

            rule.condition_opt = std::make_shared<wf::config::option_t<std::string>>(
                "my-rules-condition", criteria);
            rule.matcher = std::make_unique<wf::view_matcher_t>(rule.condition_opt);
            rules.push_back(std::move(rule));
        }
    }

    void apply_rule(const rule_t& rule, wayfire_toplevel_view toplevel)
    {
        auto view   = wayfire_view{toplevel};
        auto output = toplevel->get_output();
        if (!output)
        {
            return;
        }

        switch (rule.action)
        {
          case rule_t::action_t::ASSIGN_FOCUS:
          {
            auto wset = output->wset();
            auto grid = wset->get_workspace_grid_size();
            if ((rule.ws.x >= grid.width) || (rule.ws.y >= grid.height))
            {
                LOGE("my-rules: workspace out of range for ", grid.width, "x", grid.height, " grid");
                return;
            }

            wf::point_t from = wset->get_view_main_workspace(toplevel);
            wset->move_to_workspace(toplevel, rule.ws);

            wf::view_change_workspace_signal signal;
            signal.view = toplevel;
            signal.from = from;
            signal.to   = rule.ws;
            output->emit(&signal);

            /* Switch the viewport explicitly: focus_raise_view()'s
             * ensure_visible() judges by the committed bounding box, which
             * does not reflect the still-pending move_to_workspace() above,
             * so it would consider the view visible and not switch. */
            wset->request_workspace(rule.ws);
            wf::get_core().default_wm->focus_raise_view(view, /* allow_switch_ws */ false);
            break;
          }

          case rule_t::action_t::SET_GEOMETRY_PPT:
          {
            auto og = output->get_relative_geometry();
            auto& g = rule.geometry_ppt;
            wf::geometry_t target = {
                og.width * std::clamp(g.x, 0.0, 100.0) / 100,
                og.height * std::clamp(g.y, 0.0, 100.0) / 100,
                og.width * std::clamp(g.width, 0.0, 100.0) / 100,
                og.height * std::clamp(g.height, 0.0, 100.0) / 100,
            };
            toplevel->set_geometry(target);
            break;
          }

          case rule_t::action_t::KEEP_FOCUSED:
          {
            wf::json_t data;
            data["view-id"] = (uint64_t)view->get_id();
            data["enabled"] = true;
            auto response = ipc_repo->call_method("keep-focused/set", data);
            if (response.has_member("error"))
            {
                LOGE("my-rules: keep-focused failed (is the keep-focused plugin loaded?): ",
                    (std::string)response["error"]);
            }

            break;
          }
        }
    }

    wf::signal::connection_t<wf::view_mapped_signal> on_view_mapped = [=] (wf::view_mapped_signal *ev)
    {
        auto toplevel = wf::toplevel_cast(ev->view);
        if (!toplevel || toplevel->parent)
        {
            return;
        }

        if (suppress_armed)
        {
            suppress_armed = false;
            suppress_expiry.disconnect();
            return;
        }

        for (auto& rule : rules)
        {
            if (rule.matcher->matches(ev->view))
            {
                apply_rule(rule, toplevel);
            }
        }
    };

    wf::signal::connection_t<wf::reload_config_signal> on_reload_config =
        [=] (wf::reload_config_signal *ev)
    {
        setup_rules_from_config();
    };

    /* IPC for the "open" client */

    wf::ipc::method_callback on_ipc_focus_existing = [=] (wf::json_t data) -> wf::json_t
    {
        auto by    = wf::ipc::json_get_string(data, "by");
        auto value = wf::ipc::json_get_string(data, "value");
        auto exact = wf::ipc::json_get_bool(data, "exact");
        auto exclude_title = wf::ipc::json_get_optional_string(data, "exclude-title");

        if ((by != "app_id") && (by != "title"))
        {
            return wf::ipc::json_error("\"by\" must be \"app_id\" or \"title\"");
        }

        for (auto& view : wf::get_core().get_all_views())
        {
            auto toplevel = wf::toplevel_cast(view);
            if (!toplevel || toplevel->parent || !view->is_mapped())
            {
                continue;
            }

            std::string field = (by == "title") ? view->get_title() : view->get_app_id();
            bool matches = exact ? (field == value) : (field.find(value) != std::string::npos);
            if (!matches)
            {
                continue;
            }

            if (exclude_title && !exclude_title->empty() &&
                (view->get_title().find(*exclude_title) != std::string::npos))
            {
                continue;
            }

            wf::get_core().default_wm->focus_raise_view(view, /* allow_switch_ws */ true);
            wf::json_t response = wf::ipc::json_ok();
            response["found"] = true;
            return response;
        }

        wf::json_t response = wf::ipc::json_ok();
        response["found"] = false;
        return response;
    };

    wf::ipc::method_callback on_ipc_prepare_open = [=] (wf::json_t data) -> wf::json_t
    {
        auto row = wf::ipc::json_get_optional_uint64(data, "row");
        auto col = wf::ipc::json_get_optional_uint64(data, "col");

        if (row.has_value() && col.has_value())
        {
            auto output = wf::get_core().seat->get_active_output();
            if (!output)
            {
                return wf::ipc::json_error("no active output");
            }

            auto wset = output->wset();
            auto grid = wset->get_workspace_grid_size();
            wf::point_t ws{(int)*col - 1, (int)*row - 1};
            if ((ws.x < 0) || (ws.y < 0) || (ws.x >= grid.width) || (ws.y >= grid.height))
            {
                return wf::ipc::json_error("workspace out of range");
            }

            wset->request_workspace(ws);
        }

        suppress_armed = true;
        suppress_expiry.disconnect();
        suppress_expiry.set_timeout(3000, [=] ()
        {
            suppress_armed = false;
        });

        return wf::ipc::json_ok();
    };

  public:
    void init() override
    {
        setup_rules_from_config();
        wf::get_core().connect(&on_view_mapped);
        wf::get_core().connect(&on_reload_config);
        ipc_repo->register_method("my-rules/focus-existing", on_ipc_focus_existing);
        ipc_repo->register_method("my-rules/prepare-open", on_ipc_prepare_open);
    }

    void fini() override
    {
        ipc_repo->unregister_method("my-rules/focus-existing");
        ipc_repo->unregister_method("my-rules/prepare-open");
        on_view_mapped.disconnect();
        on_reload_config.disconnect();
        suppress_expiry.disconnect();
    }
};

DECLARE_WAYFIRE_PLUGIN(my_rules_plugin);
