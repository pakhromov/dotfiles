#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <dlfcn.h>
#include <stdexcept>
#include <string>

namespace {
CFunctionHook* swapchainHook = nullptr;

// Find the owner without depending on CMonitorState's private member layout.
PHLMONITOR panelForState(Monitor::CMonitorState* state) {
    for (const auto& monitor : State::monitorState()->allMonitors()) {
        if (monitor->m_name == "eDP-1" && &monitor->m_state == state)
            return monitor;
    }
    return nullptr;
}

bool updateSwapchain(Monitor::CMonitorState* state) {
    const auto monitor = panelForState(state);
    if (monitor && !monitor->enabled() && monitor->m_output && !monitor->m_output->state->state().enabled) {
        const auto& output = monitor->m_output;
        const auto& pending = output->state->state();

        // Aquamarine 0.15.1 rejects even a disable commit without a mode.
        // Select metadata only: do not enable the output, call next(), or
        // reconfigure the swapchain. ensureBufferPresent() already skips
        // disabled outputs, so the normal commit can then disable KMS.
        if (!pending.mode && !pending.customMode) {
            const auto mode = output->preferredMode();
            if (!mode)
                return false;
            output->state->setMode(mode);
        }
        return true;
    }

    using Original = bool (*)(Monitor::CMonitorState*);
    return reinterpret_cast<Original>(swapchainHook->m_original)(state);
}

std::string status() {
    for (const auto& monitor : State::monitorState()->allMonitors()) {
        if (monitor->m_name != "eDP-1" || !monitor->m_output)
            continue;
        const auto& output = monitor->m_output;
        return std::format("eDP-1: enabled={}, pending_enabled={}, swapchain_length={}, pending_buffer={}\n",
                           monitor->enabled(), output->state->state().enabled,
                           output->swapchain ? output->swapchain->currentOptions().length : 0,
                           static_cast<bool>(output->state->state().buffer));
    }
    return "eDP-1: not present\n";
}
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string{__hyprland_api_get_hash()} != __hyprland_api_get_client_hash())
        throw std::runtime_error("edp-disable-fix: rebuild against the running Hyprland and dependency headers");

    // An exact symbol avoids accidentally hooking an overload or another build.
    void* target = dlsym(RTLD_DEFAULT, "_ZN7Monitor13CMonitorState15updateSwapchainEv");
    if (!target)
        throw std::runtime_error("edp-disable-fix: CMonitorState::updateSwapchain symbol not found");
    swapchainHook = HyprlandAPI::createFunctionHook(handle, target, reinterpret_cast<void*>(&updateSwapchain));
    if (!swapchainHook || !swapchainHook->hook())
        throw std::runtime_error("edp-disable-fix: could not install swapchain hook");

    // Repair the failed startup commit immediately, without an on/off cycle.
    // Enabled panels and all other outputs retain the original code path.
    for (const auto& monitor : State::monitorState()->allMonitors()) {
        if (monitor->m_name != "eDP-1" || monitor->enabled() || !monitor->m_output)
            continue;
        monitor->m_output->state->resetExplicitFences();
        monitor->m_output->state->setEnabled(false);
        if (!monitor->m_state.commit()) {
            swapchainHook->unhook();
            throw std::runtime_error("edp-disable-fix: eDP-1 disable commit failed");
        }
        break;
    }

    const auto command = HyprlandAPI::registerHyprCtlCommand(handle, {
        .name = "edp-disable-status",
        .handler = [](const IPC::Socket1::SRequest&) -> IPC::Socket1::SResponse { return status(); },
    });
    if (!command) {
        swapchainHook->unhook();
        throw std::runtime_error("edp-disable-fix: could not register status command");
    }

    return {"edp-disable-fix", "Commit startup eDP-1 disable without allocating a swapchain", "local", "0.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    if (swapchainHook)
        swapchainHook->unhook();
}
