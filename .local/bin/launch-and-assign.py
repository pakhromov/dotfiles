#!/usr/bin/env python3
"""
Usage: launch-and-assign.py <app_id> <title_substr> <ws_x> <ws_y> -- <command> [args...]

Launches <command>, waits for a new (not previously existing) toplevel view
whose app-id equals <app_id> and whose title contains <title_substr>, then
moves it to workspace (ws_x, ws_y) and switches the viewport there.

If a matching view already exists before launch, <command> is skipped and
the existing view is used instead (so re-running just refocuses it).

Solves the race where window-rules' "created" rule evaluates the title
before the app has finished setting it (e.g. Firefox private windows,
where the "Private Browsing" suffix is set asynchronously after map).
"""
import subprocess
import sys
import time

from wayfire import WayfireSocket


def find_match(socket, app_id, title_substr, exclude_ids):
    for view in socket.list_views():
        if (
            view["mapped"]
            and view["app-id"] == app_id
            and title_substr in view["title"]
            and view["id"] not in exclude_ids
        ):
            return view
    return None


def main():
    args = sys.argv[1:]
    if "--" not in args:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    sep = args.index("--")
    app_id, title_substr, x, y = args[:sep]
    command = args[sep + 1:]
    x, y = int(x), int(y)

    if not command:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    socket = WayfireSocket()

    existing = find_match(socket, app_id, title_substr, exclude_ids=set())
    if existing is None:
        existing_ids = {v["id"] for v in socket.list_views()}
        subprocess.Popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        deadline = time.monotonic() + 15
        view = None
        while time.monotonic() < deadline:
            view = find_match(socket, app_id, title_substr, exclude_ids=existing_ids)
            if view is not None:
                break
            time.sleep(0.15)

        if view is None:
            print(
                f"Timed out waiting for app-id={app_id!r} "
                f"title containing {title_substr!r}",
                file=sys.stderr,
            )
            sys.exit(1)
    else:
        view = existing

    socket.send_view_to_workspace(view["id"], x, y)
    socket.set_workspace(x, y)
    socket.set_focus(view["id"])


if __name__ == "__main__":
    main()
