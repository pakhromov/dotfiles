#!/usr/bin/env bash

LAYOUTS=(us se ru)
NAMES=("English(us) 🇬🇧" "Svenska(se) 🇸🇪" "Русский(ru) 🇷🇺")
STATE="${XDG_RUNTIME_DIR:-/tmp}/current_xkb_index"
IDX=$(cat "$STATE" 2>/dev/null || echo 0)
IDX=$(( (IDX + 1) % ${#LAYOUTS[@]} ))
echo "$IDX" > "$STATE"
notify-send -a osd -i /usr/share/icons/Cosmic/scalable/devices/input-keyboard-symbolic.svg "Keyboard" "${NAMES[$IDX]}" -t 1500
