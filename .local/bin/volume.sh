#!/bin/bash

exec 9>/tmp/.volume.lock
flock -n 9 || exit 0

CONTROL=Master
ICONS=/usr/share/icons/Cosmic/scalable/status

get_control() {
  for ctl in Headset Master Headphone PCM Speaker; do
    if amixer -D default sget "$ctl" >/dev/null 2>&1; then
      printf '%s\n' "$ctl"
      return 0
    fi
  done
  return 1
}

CONTROL=$(get_control) || exit 1

case "$1" in
  up)   amixer -D default sset "$CONTROL" 5%+ unmute >/dev/null ;;
  down) amixer -D default sset "$CONTROL" 5%- unmute >/dev/null ;;
  mute) amixer -D default sset "$CONTROL" toggle >/dev/null ;;
esac

info=$(amixer -D default sget "$CONTROL")
vol=$(printf '%s\n' "$info" | awk -F'[][]' '/%/ {print $2; exit}' | tr -d '%')
state=$(printf '%s\n' "$info" | awk -F'[][]' '/%/ {print $4; exit}')

if [ "$state" = "off" ]; then
  icon=$ICONS/audio-volume-muted-symbolic.svg
  notify-send -a osd -i "$icon" -h int:value:0 -h string:x-canonical-private-synchronous:volume "Volume" "Muted" -t 1500
else
  if (( vol > 66 )); then icon=$ICONS/audio-volume-high-symbolic.svg
  elif (( vol > 33 )); then icon=$ICONS/audio-volume-medium-symbolic.svg
  else icon=$ICONS/audio-volume-low-symbolic.svg
  fi
  notify-send -a osd -i "$icon" -h int:value:"$vol" -h string:x-canonical-private-synchronous:volume "Volume" "${vol}%" -t 1500
fi
