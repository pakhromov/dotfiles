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

cat "$tmpfile"
rm -f "$tmpfile"


kitty @ scroll-window start

stty -echo 2>/dev/null
while IFS= read -rsn1 key; do
  if [[ "$key" == "q" ]]; then
    break
  elif [[ "$key" == $'\x1b' ]]; then
    if ! IFS= read -rsn1 -t 0.05 _rest; then
      break
    fi
  fi
done
stty echo 2>/dev/null

# If a search window was opened for this pager, close it too, so it isn't left
# orphaned when the pager exits.
kitty @ close-window --match var:SEARCH_WIN=1 2>/dev/null

echo done > "$fifo"
