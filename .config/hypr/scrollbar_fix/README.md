# scrollbar_fix

Turn a plain left click in an app's right-hand scrollbar strip into a
Shift-left click. Configured per app, with five rule fields:

```lua
if hl.plugin.scrollbar_fix then
    hl.plugin.scrollbar_fix.rule({
        app = "vivaldi-stable",
        scrollbar_width = 17,
        gap_top = 80,
        gap_bottom = 15,
        gaps_fullscreen = 0,
    })
end
```

Repeat the call for each app; each app can have different dimensions.
`app` matches the exact, case-sensitive app ID shown as `class` in
`hyprctl clients`. It is not a title, executable name, or regular expression.
Calling `rule` again for the same app replaces its previous rule. Rules clear
before a config reload, so removing a rule from the config takes effect.

For a window of width W and height H, the target is:

```text
W - scrollbar_width <= x < W
gap_top             <= y < H - gap_bottom
```

When the window is fullscreen, `gaps_fullscreen` replaces both `gap_top` and
`gap_bottom`. For example, `gaps_fullscreen = 5` excludes the top 5 and bottom
5 pixels. It defaults to zero. Maximized windows keep the normal gaps. The
fullscreen state is read on a matching app's left press, so entering/leaving
fullscreen takes effect without a config reload or a motion/event listener.

The coordinates are relative to the app window, in logical pixels, including
for floating and resized windows. These are the same pixel units Hyprland
uses for `cursor.hotspot_padding`; at scale 1 they are physical pixels too.
All gaps default to zero; width is required. All dimensions must be
non-negative integers. Width zero disables a rule. Overlapping top/bottom
gaps leave no target region. Unknown rule fields are rejected.

Only plain left-button presses qualify. Ctrl/Alt/Super clicks, user-held
Shift clicks, other mouse buttons, scrolling, typing, and pointer motion
keep their normal behavior. Caps Lock and Num Lock can remain enabled.
The release of a qualifying press is treated as part of that click, even
when released outside the strip, provided its recipient is the same surface.
Menus and popups are excluded.

The plugin changes no coordinates, focus, key bindings, keyboard XKB state,
or cursor settings. It hooks final `CSeatManager::sendPointerButton` delivery,
after native focus and key bindings, so a first click that focuses the app
can qualify. It sends Shift modifiers, the original button event and a
pointer frame, then restores the real modifiers immediately. It also ends
any preceding pointer frame before injecting Shift. This ordering supports
clients that process button events at frame boundaries, without leaving
Shift asserted during typing, movement, or a drag.

As with a physical modifier, the client must have keyboard focus to receive
the modifier notification. If pointer and keyboard recipients belong to
different clients, the event is left alone. Active compositor grabs and
drag-and-drop keep their native delivery rules.

## Runtime overhead

The Lua guard and rule declarations run only during config parsing, at startup
or reload. Each declaration copies the app ID and dimensions into a C++ hash
table. No Lua runs from the input hook.

There is no pointer-motion, scroll, keyboard, or render hook, and no timer or
polling loop. An open but unfocused configured app causes no background work.
The single C++ button hook remains installed even when all configured apps
are closed:

- Non-left buttons and ordinary unpaired left releases immediately forward.
- With no rules configured, left presses also immediately forward.
- Other left presses resolve the recipient window and look up its app ID.
  Unconfigured apps return here, without reading keyboard/modifier state.
- Configured apps get a rectangle check. Presses outside the strip return
  here too, without reading keyboard/modifier state.
- Only a press in a matching strip, or the release paired with an already
  converted press, reads modifier state. This includes the shared-keyboard
  scan. A converted event adds two modifier notifications and two pointer
  frame calls around the original event.

App lookup is average O(1); it does not scan the list of open windows or apps.
The rectangle check is O(1). Modifier aggregation is O(K) in the number of
keyboard devices and happens only after a strip match (or for its paired
release). A main-surface subsurface ownership check may walk that surface's
tree, also only after the rectangle matches. Actual latency and resident
memory have not been measured; operation counts are not timing benchmarks.

## Build and load

Rebuilt and checked against Hyprland **0.57.0**
(`0aa6745f705f2c4b0a5004eb019ef76e5bbdb426`), plugin API **0.2**. Existing Lua
rules and click behavior are compatible; no configuration changes are required.

```sh
./build.sh
hyprctl plugin load /home/pavel/.config/hypr/scrollbar_fix/libscrollbar_fix.so
hyprctl reload
```

Run the build command from this directory. It writes the library beside the
source, with no separate build directory. Rebuilding atomically replaces the
library; unload and load the plugin to use the new code in a running session.

The current `hyprland.lua` already contains the startup load and app rules.
Edit that rule block to adjust the width or give individual apps different
values. The Lua guard allows config parsing before the plugin is loaded;
reload the config after manually loading the plugin to register its rules.

To unload:

```sh
hyprctl plugin unload /home/pavel/.config/hypr/scrollbar_fix/libscrollbar_fix.so
```

Remove its startup load to keep it unloaded after login. The pre-change
config is saved as `../hyprland.lua.bak-before-scrollbar-fix`.

Rebuild after a Hyprland update. The plugin refuses an incompatible
compositor/header ABI hash.
