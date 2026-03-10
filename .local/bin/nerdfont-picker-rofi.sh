#!/usr/bin/env bash

if [[ "$1" == "-t" ]]; then
  "$2" "$0"
  exit
fi

sel=$(
  rofi -dmenu \
    -multi-select \
    -no-sort \
    -matching normal \
    -kb-element-next "" \
    -kb-accept-alt "Tab" \
    -mesg "Tab: select, Enter: accept" \
    < "$HOME/.local/bin/icons/nerdfont.txt" |
    cut -d" " -f1 |
    paste -sd" "
)

[ -n "$sel" ] && wl-copy -- "$sel" >/dev/null 2>&1
