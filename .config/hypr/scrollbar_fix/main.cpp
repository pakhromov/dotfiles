#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowMetadata.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/devices/IKeyboard.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/protocols/core/DataDevice.hpp>
#include <hyprutils/utils/ScopeGuard.hpp>

#include <lua.hpp>
#include <linux/input-event-codes.h>
#include <dlfcn.h>
#include <xkbcommon/xkbcommon.h>

#include <climits>
#include <cstring>
#include <stdexcept>
#include <string>
#include <unordered_map>

#include "region.hpp"

namespace {
using Button = void (*)(CSeatManager*, uint32_t, uint32_t, wl_pointer_button_state);
CFunctionHook* buttonHook = nullptr;
CHyprSignalListener preReload;
std::unordered_map<std::string, ScrollbarFix::Rule> rules;
WP<CWLSurfaceResource> clickSurface;

uint32_t mask(xkb_keymap* keymap, const char* name) {
    if (!keymap)
        return 0;
    const auto index = xkb_keymap_mod_get_index(keymap, name);
    return index == XKB_MOD_INVALID || index >= 32 ? 0 : uint32_t{1} << index;
}

struct Modifiers {
    uint32_t depressed, latched, locked, group;
};

Modifiers physicalModifiers(const SP<IKeyboard>& keyboard) {
    const auto& current = keyboard->m_modifiersState;
    Modifiers mods{current.depressed, current.latched, current.locked, current.group};
    // Match Hyprland's shared keyboard state, including a modifier held on
    // another physical keyboard. Never write to an XKB state or a key binding.
    for (const auto& other : g_pInputManager->m_keyboards) {
        if (!other->m_enabled || !other->shareStates() ||
            (other->isVirtual() && g_pInputManager->shouldIgnoreVirtualKeyboard(other)))
            continue;
        mods.depressed |= other->m_modifiersState.depressed;
        mods.latched |= other->m_modifiersState.latched;
        mods.locked |= other->m_modifiersState.locked;
    }
    return mods;
}

bool inConfiguredStrip(const SP<CWLSurfaceResource>& surface) {
    const auto hlSurface = Desktop::View::CWLSurface::fromResource(surface);
    const auto window = hlSurface ? Desktop::View::CWindow::fromView(hlSurface->view()) : nullptr;
    if (!window || !window->mapped())
        return false;
    const auto rule = rules.find(window->metadata().appID());
    if (rule == rules.end())
        return false;

    const auto box = window->logicalBox();
    if (!box)
        return false;
    const auto point = g_pInputManager->getMouseCoordsInternal() - box->pos();
    const bool fullscreen = Fullscreen::controller()->isFullscreen(window, Fullscreen::FSMODE_FULLSCREEN);
    if (!ScrollbarFix::contains(rule->second, point.x, point.y, box->w, box->h, fullscreen))
        return false;

    // Check surface ownership only after the app and rectangle have matched.
    // Popups are separate from the main surface's subsurface tree.
    const auto root = window->backend().surface();
    return root && (root == surface || root->findFirstPreorder([&](auto candidate) { return candidate == surface; }));
}

void sendButton(CSeatManager* seat, uint32_t time, uint32_t button, wl_pointer_button_state state) {
    const auto original = reinterpret_cast<Button>(buttonHook->m_original);
    if (button != BTN_LEFT)
        return original(seat, time, button, state);

    const bool pressed = state == WL_POINTER_BUTTON_STATE_PRESSED;
    // Ordinary releases and an empty rule table need no window or keyboard work.
    if ((!pressed && clickSurface.expired()) || (pressed && rules.empty()))
        return original(seat, time, button, state);

    const auto surface = seat->m_state.pointerFocus.lock();
    const bool pairedRelease = !pressed && surface && clickSurface == surface;
    // Remember the press target, not the release coordinates. A click released
    // outside the strip must finish on the same terms as its initial press.
    clickSurface.reset();

    if (!surface || !g_pInputManager || !seat->m_state.pointerFocusResource)
        return original(seat, time, button, state);
    // Do all app/area rejection before looking at the keyboard or modifiers.
    // A paired release follows its qualifying press even outside the strip.
    if (pressed ? !inConfiguredStrip(surface) : !pairedRelease)
        return original(seat, time, button, state);

    const auto keyboard = seat->m_keyboard.lock();
    const auto keyboardSurface = seat->m_state.keyboardFocus.lock();
    if (!keyboard || !keyboardSurface || (PROTO::data && PROTO::data->dndActive()) ||
        keyboardSurface->client() != surface->client())
        return original(seat, time, button, state);

    const auto mods = physicalModifiers(keyboard);
    if (pressed && (mods.depressed | mods.latched))
        return original(seat, time, button, state);
    const auto shift = mask(keyboard->m_xkbKeymap, XKB_MOD_NAME_SHIFT);
    if (!shift)
        return original(seat, time, button, state);
    if (pressed && mods.locked) {
        const auto clickMods = shift | mask(keyboard->m_xkbKeymap, XKB_MOD_NAME_CTRL) |
                               mask(keyboard->m_xkbKeymap, XKB_MOD_NAME_ALT) |
                               mask(keyboard->m_xkbKeymap, XKB_MOD_NAME_LOGO);
        if (mods.locked & clickMods)
            return original(seat, time, button, state);
    }
    if (pressed)
        clickSurface = surface;

    // Finish preceding motion with its real modifiers, then bracket ONLY this
    // button event with Shift. Frame before restoring modifiers so clients that
    // batch pointer events see the intended state. No Shift spans a drag, key,
    // axis, or motion event; the physical keyboard state is never modified.
    seat->sendPointerFrame();
    seat->sendKeyboardMods(mods.depressed | shift, mods.latched, mods.locked, mods.group);
    Hyprutils::Utils::CScopeGuard restore([&] {
        seat->sendKeyboardMods(mods.depressed, mods.latched, mods.locked, mods.group);
    });
    original(seat, time, button, state);
    seat->sendPointerFrame();
}

int integer(lua_State* state, const char* field, bool required) {
    lua_getfield(state, 1, field);
    if (!required && lua_isnil(state, -1)) {
        lua_pop(state, 1);
        return 0;
    }
    int valid = 0;
    const auto value = lua_tointegerx(state, -1, &valid);
    if (!valid || lua_type(state, -1) != LUA_TNUMBER || value < 0 || value > INT_MAX)
        luaL_error(state, "scrollbar_fix.%s must be a non-negative integer", field);
    lua_pop(state, 1);
    return static_cast<int>(value);
}

int addRule(lua_State* state) {
    luaL_checktype(state, 1, LUA_TTABLE);
    lua_pushnil(state);
    while (lua_next(state, 1)) {
        const char* key = lua_type(state, -2) == LUA_TSTRING ? lua_tostring(state, -2) : nullptr;
        if (!key || (std::strcmp(key, "app") && std::strcmp(key, "scrollbar_width") &&
                     std::strcmp(key, "gap_top") && std::strcmp(key, "gap_bottom") && std::strcmp(key, "gaps_fullscreen")))
            return luaL_error(state, "scrollbar_fix.rule accepts only app, scrollbar_width, gap_top, gap_bottom, gaps_fullscreen");
        lua_pop(state, 1);
    }
    lua_getfield(state, 1, "app");
    size_t length = 0;
    const char* app = lua_type(state, -1) == LUA_TSTRING ? lua_tolstring(state, -1, &length) : nullptr;
    if (!app || !length || std::strlen(app) != length)
        return luaL_error(state, "scrollbar_fix.app must be a non-empty app ID");
    // Keep the app string rooted on the Lua stack while validating the numbers.
    const int width = integer(state, "scrollbar_width", true);
    const int top = integer(state, "gap_top", false);
    const int bottom = integer(state, "gap_bottom", false);
    const int fullscreen = integer(state, "gaps_fullscreen", false);
    rules.insert_or_assign(std::string(app, length), ScrollbarFix::Rule{width, top, bottom, fullscreen});
    return 0;
}
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string{__hyprland_api_get_hash()} != __hyprland_api_get_client_hash())
        throw std::runtime_error("scrollbar_fix: rebuild against the running Hyprland headers");
    void* target = dlsym(RTLD_DEFAULT, "_ZN12CSeatManager17sendPointerButtonEjj23wl_pointer_button_state");
    if (!target)
        throw std::runtime_error("scrollbar_fix: sendPointerButton not found");
    buttonHook = HyprlandAPI::createFunctionHook(handle, target, reinterpret_cast<void*>(&sendButton));
    if (!buttonHook || !buttonHook->hook())
        throw std::runtime_error("scrollbar_fix: cannot hook button delivery");
    if (!HyprlandAPI::addLuaFunction(handle, "scrollbar_fix", "rule", addRule)) {
        buttonHook->unhook();
        throw std::runtime_error("scrollbar_fix: cannot register Lua configuration");
    }
    preReload = Event::bus()->m_events.config.preReload.listen([] { rules.clear(); });
    return {"scrollbar_fix", "Plain left clicks in per-app scrollbar strips become Shift-clicks", "local", "0.2.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    preReload.reset();
    if (buttonHook)
        buttonHook->unhook();
    clickSurface.reset();
    rules.clear();
}
