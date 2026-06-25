#!/usr/bin/env python3
"""
Usage: keep-focused-launch.py <app_id> -- <command> [args...]

Always runs <command> unconditionally (so toggle-style scripts that close
an already-open view still work), then briefly waits for a mapped view
matching <app_id> to appear. If one shows up, marks it via the personal
plugin's "keep-focused" IPC method so it keeps keyboard focus for as long
as it stays open -- the same mechanism wlr-layer-shell exclusive surfaces
(rofi, fuzzel) get natively. The plugin releases focus on its own when the
view closes, so this script doesn't need to stay running. If no view shows
up (e.g. the command just closed an existing one), it exits quietly.
"""
import subprocess
import sys
import time

from wayfire import WayfireSocket


def find_match(socket, app_id):
    for view in socket.list_views():
        if view["mapped"] and view["app-id"] == app_id:
            return view
    return None


def main():
    args = sys.argv[1:]
    if "--" not in args:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    sep = args.index("--")
    (app_id,) = args[:sep]
    command = args[sep + 1:]

    if not command:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    socket = WayfireSocket()

    subprocess.Popen(
        command,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.monotonic() + 3
    view = None
    while time.monotonic() < deadline:
        view = find_match(socket, app_id)
        if view is not None:
            break
        time.sleep(0.1)

    if view is None:
        return

    socket.send_json({
        "method": "personal/keep-focused",
        "data": {"view-id": view["id"], "enabled": True},
    })


if __name__ == "__main__":
    main()
