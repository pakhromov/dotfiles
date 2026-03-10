#!/bin/bash

exec 9>/tmp/.brightness.lock
flock -n 9 || exit 0

ICONS=/usr/share/icons/Cosmic/scalable/status

case "$1" in
  up)
    brightnessctl -d nvidia_0 set 5%+ >/dev/null
    ddcutil setvcp 10 + 5 --noverify --bus 9 >/dev/null 2>&1 &
    ;;
  down)
    brightnessctl -d nvidia_0 set 5%- >/dev/null
    ddcutil setvcp 10 - 5 --noverify --bus 9 >/dev/null 2>&1 &
    ;;
esac

pct=$(brightnessctl -d nvidia_0 -m | cut -d, -f4 | tr -d %)
if (( pct > 66 )); then icon=$ICONS/display-brightness-high-symbolic.svg
elif (( pct > 33 )); then icon=$ICONS/display-brightness-medium-symbolic.svg
elif (( pct > 0 )); then icon=$ICONS/display-brightness-low-symbolic.svg
else icon=$ICONS/display-brightness-off-symbolic.svg
fi
notify-send -a osd -i $icon -h int:value:"$pct" -h string:x-canonical-private-synchronous:brightness "Brightness" "${pct}%" -t 1500
