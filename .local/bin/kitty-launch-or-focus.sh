#!/bin/bash
# Launch a program in a new kitty tab or focus existing one
# Usage: kitty-launch-or-focus.sh <program> [args...]
# Requires kitty to be started with: --single-instance --listen-on=unix:@mykitty

if [ $# -eq 0 ]; then
    echo "Usage: $0 <program> [args...]"
    exit 1
fi

PROGRAM="$1"
shift
ARGS="$@"

# Fixed socket for single-instance mode
SOCKET="unix:@mykitty"

# Check if kitty single-instance is running
if ! kitten @ --to "$SOCKET" ls &>/dev/null; then
    kitty --single-instance --listen-on="$SOCKET" --class shell "$PROGRAM" $ARGS &
    timeout 10 wlrctl window waitfor "app_id:shell" || true
    for _ in 1 2 3 4 5; do
        wlrctl window focus "app_id:shell" || true
        sleep 0.1
    done
    exit 0
fi

# Check if the program is already running
PROGRAM_WINDOW=$(kitten @ --to "$SOCKET" ls | \
    jq -r --arg prog "$PROGRAM" '.[].tabs[].windows[] | select(.foreground_processes[]?.cmdline[]? | test($prog)) | .id' | \
    head -1)

if [ -n "$PROGRAM_WINDOW" ]; then
    kitten @ --to "$SOCKET" focus-window --match "id:$PROGRAM_WINDOW"
else
    SHELL_PANE=$(kitten @ --to "$SOCKET" ls | jq -r '.[] | select(.wm_class == "shell") | .tabs[0].windows[0].id')
    if [ -n "$SHELL_PANE" ]; then
        kitten @ --to "$SOCKET" focus-window --match "id:$SHELL_PANE" &>/dev/null
        kitten @ --to "$SOCKET" launch --type=tab "$PROGRAM" $ARGS >/dev/null
    else
        kitten @ --to "$SOCKET" launch --type=os-window --os-window-class shell "$PROGRAM" $ARGS >/dev/null
        timeout 10 wlrctl window waitfor "app_id:shell" || true
    fi
fi

for _ in 1 2 3 4 5; do
    wlrctl window focus "app_id:shell" || true
    sleep 0.1
done
