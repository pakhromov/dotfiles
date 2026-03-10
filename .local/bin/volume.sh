#!/bin/bash

# Kill previous instances
exec 9>/tmp/.volume.lock
flock -n 9 || exit 0

ICONS=/usr/share/icons/Cosmic/scalable/status

case "$1" in
  up)   wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0 ;;
  down) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
  mute) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
esac

info=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
vol=$(echo "$info" | awk '{printf "%.0f", $2 * 100}')
if echo "$info" | grep -q MUTED; then
  icon=$ICONS/audio-volume-muted-symbolic.svg
  notify-send -a osd -i $icon -h int:value:0 -h string:x-canonical-private-synchronous:volume "Volume" "Muted" -t 1500
else
  if (( vol > 66 )); then icon=$ICONS/audio-volume-high-symbolic.svg
  elif (( vol > 33 )); then icon=$ICONS/audio-volume-medium-symbolic.svg
  else icon=$ICONS/audio-volume-low-symbolic.svg
  fi
  notify-send -a osd -i $icon -h int:value:"$vol" -h string:x-canonical-private-synchronous:volume "Volume" "${vol}%" -t 1500
fi
