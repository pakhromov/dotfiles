#!/usr/bin/env bash
# Usage: launch-or-focus.sh <app_id> <command> [args...]
#
# If a window with the given app_id is already running, focus it
# (and switch to its workspace, via wayfire's ensure_visible()).
# Otherwise launch <command> [args...], wait for the window to map,
# then focus it.

set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <app_id> <command> [args...]" >&2
    exit 1
fi

app_id="$1"
shift

if wlrctl window find "app_id:${app_id}" >/dev/null 2>&1; then
    exec wlrctl window focus "app_id:${app_id}"
fi

setsid -f "$@" >/dev/null 2>&1 &

if ! timeout 10 wlrctl window waitfor "app_id:${app_id}"; then
    echo "Timed out waiting for app_id:${app_id} to appear" >&2
    exit 1
fi

# The window may not have settled into its assigned workspace yet (window
# rules / tile plugin apply asynchronously after the toplevel handle is
# announced), so retry focusing a few times to catch it once it has.
for _ in 1 2 3 4 5; do
    wlrctl window focus "app_id:${app_id}" || true
    sleep 0.1
done
