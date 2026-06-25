#!/usr/bin/env python3
"""
Watches wayfire's "keyboard-modifier-state-changed" IPC event (emitted by
the ipc-rules plugin) and sends a desktop notification whenever the active
XKB keyboard layout actually changes. The event also fires for plain
modifier presses (Shift, Ctrl, ...), so the last-seen layout is tracked to
only notify on a real layout switch. Pure event-driven watcher: blocks on
the IPC socket, no polling.
"""
import subprocess

from wayfire import WayfireSocket

sock = WayfireSocket()
sock.watch(["keyboard-modifier-state-changed"])

last_layout = None
while True:
    msg = sock.read_next_event()
    layout = msg.get("state", {}).get("layout")
    if layout is None or layout == last_layout:
        continue

    last_layout = layout
    subprocess.Popen(["notify-send", "-a", "keyboard-layout", "Keyboard layout", layout])
