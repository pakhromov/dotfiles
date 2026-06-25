#!/usr/bin/env python3
"""
Bound to the same key as the XKB group toggle (e.g. <super> KEY_SPACE with
xkb_options = grp:win_space_toggle). Queries wayfire's real keyboard state
via the core "wayfire/get-keyboard-state" IPC method (no local index
tracking, so it can never drift out of sync with the actual XKB layout)
and shows a notification for whatever layout is actually active.
"""
import subprocess

from wayfire import WayfireSocket

# Keyed by layout-index, matching the order of [input] xkb_layout = us, se, ru.
# state["layout"] is the full XKB name (e.g. "Swedish"), not the short code,
# so the index is the only locale-independent way to map it.
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

sock = WayfireSocket()
state = sock.send_json({"method": "wayfire/get-keyboard-state", "data": {}})
index = state["layout-index"]
name = NAMES.get(index, state["layout"])
icon = FLAGS.get(index, "/usr/share/icons/Cosmic/scalable/devices/input-keyboard-symbolic.svg")

subprocess.run([
    "notify-send", "-a", "osd",
    "-i", icon,
    "-h", "string:x-canonical-private-synchronous:keyboard-layout",
    "Keyboard", name, "-t", "2000",
])
