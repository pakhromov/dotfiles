#!/usr/bin/env python3
"""
Usage: pin-overlay-launch.py <app_id> -- <command> [args...]

Always runs <command> (it's the command's own job to decide what to do,
e.g. a toggle script that opens or closes itself). Afterwards, waits for
any view matching <app_id> to appear, and if one does, suspends
follow-focus/change_view until it closes.

follow-focus (focus-follows-mouse) steals focus back as soon as the
cursor moves, since a regular xdg_toplevel view has no way to request
focus_importance::HIGH the way wlr-layer-shell exclusive-keyboard
surfaces (rofi, fuzzel) or the session-lock surface can. As a practical
workaround, this script suspends follow-focus/change_view for as long
as something is open, then restores it. A refcounted lock file handles
multiple such popups being open at once.
"""
import fcntl
import subprocess
import sys
import time

from wayfire import WayfireSocket

LOCK_PATH = "/tmp/.pin-overlay-launch-follow-focus.lock"


def find_match(socket, app_id, exclude_ids):
    for view in socket.list_views():
        if view["mapped"] and view["app-id"] == app_id and view["id"] not in exclude_ids:
            return view
    return None


def view_exists(socket, view_id):
    return any(v["id"] == view_id for v in socket.list_views())


class FollowFocusSuspender:
    """Refcounted suspend/restore of follow-focus/change_view across concurrent popups."""

    def __init__(self, socket):
        self.socket = socket

    def _with_lock(self, fn):
        with open(LOCK_PATH, "a+") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            try:
                f.seek(0)
                count = int(f.read().strip() or "0")
                count = fn(count)
                f.seek(0)
                f.truncate()
                f.write(str(count))
            finally:
                fcntl.flock(f, fcntl.LOCK_UN)

    def suspend(self):
        def bump(count):
            if count == 0:
                self.socket.set_option_values({"follow-focus/change_view": False})
            return count + 1

        self._with_lock(bump)

    def restore(self):
        def bump(count):
            count = max(0, count - 1)
            if count == 0:
                self.socket.set_option_values({"follow-focus/change_view": True})
            return count

        self._with_lock(bump)


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
    suspender = FollowFocusSuspender(socket)
    suspender.suspend()

    try:
        subprocess.Popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        deadline = time.monotonic() + 10
        view = None
        while time.monotonic() < deadline:
            view = find_match(socket, app_id, exclude_ids=set())
            if view is not None:
                break
            time.sleep(0.1)

        if view is None:
            return

        #socket.set_view_always_on_top(view["id"], True)

        while view_exists(socket, view["id"]):
            time.sleep(0.3)
    finally:
        suspender.restore()


if __name__ == "__main__":
    main()
