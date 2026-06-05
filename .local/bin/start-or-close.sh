#!/bin/sh
# Usage: start-or-close.sh <cmd> [terminal [terminal-args...]]
CMD="$1"
shift

if pgrep -x "$CMD" > /dev/null; then
    pkill -x "$CMD"
else
    if [ $# -gt 0 ]; then
        "$@" -e "$CMD" &
    else
        "$CMD" &
    fi
fi
