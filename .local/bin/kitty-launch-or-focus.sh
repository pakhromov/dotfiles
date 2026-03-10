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
    # No kitty instance, start one with single-instance mode
    kitty --single-instance --listen-on="$SOCKET" "$PROGRAM" $ARGS &
    exit 0
fi

# Check if the program is already running in a tab using jq
PROGRAM_WINDOW=$(kitten @ --to "$SOCKET" ls | \
    jq -r --arg prog "$PROGRAM" '.[].tabs[].windows[] | select(.foreground_processes[]?.cmdline[]? | test($prog)) | .id' | \
    head -1)

if [ -n "$PROGRAM_WINDOW" ]; then
    # Focus existing window
    kitten @ --to "$SOCKET" focus-window --match "id:$PROGRAM_WINDOW"
else
    # Launch program in new tab
    kitten @ --to "$SOCKET" launch --type=tab "$PROGRAM" $ARGS
fi

# Focus the kitty window using foreign-toplevel protocol
focus-window kitty
