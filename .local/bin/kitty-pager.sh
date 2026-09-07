#!/usr/bin/env bash

if [ "$#" -eq 0 ]; then

  tmpfile=$(mktemp /tmp/kitty-pager-XXXXXX.txt) || exit 1
  cat > "$tmpfile"

  fifo=$(mktemp -u /tmp/kitty-pager-fifo-XXXXXX)
  mkfifo "$fifo"

  kitty @ launch --type=overlay --allow-remote-control --var PAGER_MODE=1 bash "$0" "$tmpfile" "$fifo"

  cat "$fifo" > /dev/null
  rm -f "$fifo"
  exit 0
fi


tmpfile="$1"
fifo="$2"

# Run cleanup on ANY exit, not just a clean quit-key press. If kitty force-
# closes this overlay (SIGHUP, e.g. ctrl+shift+w) or it's interrupted, the entry
# process's `cat "$fifo"` would otherwise block forever, hanging whatever
# launched the pager (e.g. `man`). The signal traps turn those signals into a
# normal exit so the EXIT trap fires and unblocks it.
cleanup() {
  stty echo 2>/dev/null
  kitty @ close-window --match var:SEARCH_WIN=1 2>/dev/null  # close the search window too
  echo done > "$fifo" 2>/dev/null                            # unblock the entry process
}
trap cleanup EXIT
trap 'exit' HUP TERM INT

cat "$tmpfile"
rm -f "$tmpfile"

kitty @ scroll-window start

# Quit keys are configurable via env vars (set with `env NAME=VALUE` in
# kitty.conf; this overlay inherits them). No hard-coded default -- an unset
# var means no quit key of that kind:
#   PAGER_QUIT      any single character in this string quits (e.g. "q")
#   PAGER_QUIT_ESC  1/true -> a bare Esc also quits; 0/false/unset -> it doesn't
stty -echo 2>/dev/null
while IFS= read -rsn1 key; do
  if [[ -n "$key" && -n "$PAGER_QUIT" && "$PAGER_QUIT" == *"$key"* ]]; then
    break
  elif [[ ("${PAGER_QUIT_ESC,,}" == "1" || "${PAGER_QUIT_ESC,,}" == "true") && "$key" == $'\x1b' ]]; then
    # A bare Esc quits, but Esc that begins an escape sequence (an unmapped
    # function key, etc.) does not -- if more bytes arrive within 50ms it's a
    # sequence, not a lone Esc press.
    if ! IFS= read -rsn1 -t 0.05 _rest; then
      break
    fi
  fi
done
# stty echo, closing the search window, and signalling the entry all happen in
# the cleanup() EXIT trap above.
