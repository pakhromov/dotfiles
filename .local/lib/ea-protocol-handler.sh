#!/bin/bash
# Handle origin2:// (and origin://, link2ea://) URLs from the browser.
#
# Battlelog opens URLs like
#   origin2://library/open?
#   origin2://game/launch/?offerIds=...&title=...&authCode=...&cmdParams=...
# EALauncher.exe understands these, so the URL is passed straight through:
# if the EA app is already running it hands the request to that instance,
# otherwise it starts up first.
#
# Registered for the scheme via ea-app.desktop.
set -u

PREFIX=/home/pavel/mnt/nvme0n1p4/ea-app
LAUNCHER=/home/pavel/.local/bin/ea-app-wayland.sh
LOG="$PREFIX/logs/protocol-handler.log"
mkdir -p "$(dirname "$LOG")"

url=${1:-}
echo "[$(date -Is)] handling: ${url:-<no url>}" >> "$LOG"

if [ -z "$url" ]; then
    exec "$LAUNCHER" >>"$LOG" 2>&1
fi

exec "$LAUNCHER" "$url" >>"$LOG" 2>&1
