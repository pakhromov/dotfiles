#!/usr/bin/env python3
"""
Bound to <super> KEY_SPACE. Shows a notification for whatever XKB layout is
actually active. Works under both wayfire and hyprland, gated on
XDG_CURRENT_DESKTOP (a colon-separated list, e.g. "Wayfire:wlroots").

The active index is always read back from the compositor rather than tracked
locally, so it can never drift out of sync with the real XKB layout.

The two compositors need different amounts of help:

  wayfire  - xkb_options = grp:win_space_toggle does the switching, and the
             keyboard state is seat-global. This script only reports.

  hyprland - xkb state is kept *per keyboard*, so a group toggle would only
             move the device the key was pressed on and leave the others
             behind. This script switches every device itself via
             `hyprctl switchxkblayout all`, reproducing wayfire's seat-global
             behaviour. Do not also set grp:win_space_toggle there, or the
             layout will advance twice per press.
"""
import json
import os
import subprocess
import sys

# Keyed by layout-index, matching the order of the configured layout list
# (wayfire: xkb_layout = us, se, ru / hyprland: input.kb_layout = "us,se,ru").
NAMES = {
    0: "English(us)",
    1: "Svenska(se)",
    2: "Russian(ru)",
}

FLAGS = {
    0: "/usr/share/circle-flags-svg/us.svg",
    1: "/usr/share/circle-flags-svg/se.svg",
    2: "/usr/share/circle-flags-svg/ru.svg",
}

FALLBACK_ICON = "/usr/share/icons/Cosmic/scalable/devices/input-keyboard-symbolic.svg"


def current_desktop():
    names = {n.strip().lower() for n in os.environ.get("XDG_CURRENT_DESKTOP", "").split(":")}
    if "hyprland" in names:
        return "hyprland"
    if "wayfire" in names:
        return "wayfire"
    return "unknown"


def hyprctl(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True).stdout


def hypr_main_keyboard():
    keyboards = json.loads(hyprctl("devices", "-j")).get("keyboards", [])
    if not keyboards:
        return None
    return next((k for k in keyboards if k.get("main")), keyboards[0])


def query_hyprland():
    """Advance the layout on every keyboard, then report what actually stuck."""
    keeb = hypr_main_keyboard()
    if keeb is None:
        return None

    layouts = [x.strip() for x in (keeb.get("layout") or "").split(",") if x.strip()]
    if len(layouts) < 2:
        return None  # nothing to cycle

    nxt = (keeb.get("active_layout_index", 0) + 1) % len(layouts)

    # An explicit index rather than "next": hyprland's "next" branch wraps on
    # `activeLayout > LAYOUTS`, which cannot be true, so the last->first step is
    # left to xkb's out-of-range handling. An index keeps it deterministic.
    hyprctl("switchxkblayout", "all", str(nxt))

    keeb = hypr_main_keyboard() or keeb
    return keeb.get("active_layout_index", nxt), keeb.get("active_keymap")


def query_wayfire():
    """grp:win_space_toggle already switched; just read the seat state."""
    from wayfire import WayfireSocket

    state = WayfireSocket().send_json({"method": "wayfire/get-keyboard-state", "data": {}})
    return state["layout-index"], state.get("layout")


def main():
    desktop = current_desktop()
    try:
        if desktop == "hyprland":
            result = query_hyprland()
        elif desktop == "wayfire":
            result = query_wayfire()
        else:
            print(f"unsupported XDG_CURRENT_DESKTOP: {os.environ.get('XDG_CURRENT_DESKTOP')!r}",
                  file=sys.stderr)
            return 1
    except Exception as exc:  # compositor not up, IPC gone, module missing, bad JSON
        print(f"{desktop}: could not read keyboard state: {exc}", file=sys.stderr)
        return 1

    if result is None:
        return 0

    index, keymap = result

    subprocess.run([
        "notify-send", "-a", "osd",
        "-i", FLAGS.get(index, FALLBACK_ICON),
        "-h", "string:x-canonical-private-synchronous:keyboard-layout",
        "Keyboard", NAMES.get(index, keymap or "?"), "-t", "2000",
    ])
    return 0


if __name__ == "__main__":
    sys.exit(main())
