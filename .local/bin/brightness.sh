#!/bin/bash

exec 9>/tmp/.brightness.lock
flock -n 9 || exit 0

ICONS=/usr/share/icons/Cosmic/scalable/status
DDC_STATE=/tmp/.brightness-ddc
DDC_BUS=9

# Detect if DP-2 is active
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    dp2=$(wlr-randr 2>/dev/null | awk '/^DP-2/{f=1} f && /Enabled: yes/{print 1; exit}')
else
    dp2=$(xrandr 2>/dev/null | awk '/^DP-2 connected [1-9]/{print 1}')
fi

if [ -n "$dp2" ]; then
    pct=$(cat "$DDC_STATE" 2>/dev/null)
    [ -z "$pct" ] && pct=$(ddcutil getvcp 10 --bus $DDC_BUS 2>/dev/null | grep -oP 'current value =\s*\K\d+')
    pct=${pct:-50}

    case "$1" in
        up)   pct=$(( pct + 5 > 100 ? 100 : pct + 5 ))
              ddcutil setvcp 10 "$pct" --noverify --bus $DDC_BUS >/dev/null 2>&1 & ;;
        down) pct=$(( pct - 5 < 0 ? 0 : pct - 5 ))
              ddcutil setvcp 10 "$pct" --noverify --bus $DDC_BUS >/dev/null 2>&1 & ;;
    esac
    echo "$pct" > "$DDC_STATE"
else
    case "$1" in
        up)   brightnessctl -d nvidia_0 set 5%+ >/dev/null ;;
        down) brightnessctl -d nvidia_0 set 5%- >/dev/null ;;
    esac
    pct=$(brightnessctl -d nvidia_0 -m | cut -d, -f4 | tr -d %)
fi

if (( pct > 66 )); then icon=$ICONS/display-brightness-high-symbolic.svg
elif (( pct > 33 )); then icon=$ICONS/display-brightness-medium-symbolic.svg
elif (( pct > 0 )); then icon=$ICONS/display-brightness-low-symbolic.svg
else icon=$ICONS/display-brightness-off-symbolic.svg
fi
notify-send -a osd -i "$icon" -h int:value:"$pct" -h string:x-canonical-private-synchronous:brightness "Brightness" "${pct}%" -t 1500
