#!/bin/bash

exec 9>/tmp/.volume.lock
flock -n 9 || exit 0

ICONS=/usr/share/icons/Cosmic/scalable/status
MUTE_STATE=/tmp/.volume-mute-level

# Softmaster is the software volume audio-switch inserts, so it exists under
# the same name on every output regardless of what hardware is attached. The
# rest are fallbacks for a config audio-switch did not write.
get_control() {
  for ctl in Softmaster Headset Master Headphone PCM Speaker; do
    if amixer -D default sget "$ctl" >/dev/null 2>&1; then
      printf '%s\n' "$ctl"
      return 0
    fi
  done
  return 1
}

CONTROL=$(get_control) || exit 1

read_vol() {
  amixer -D default sget "$CONTROL" 2>/dev/null |
    awk -F'[][]' '/%/ {print $2; exit}' | tr -d '%'
}

# HDMI outputs expose volume with no mute switch (Capabilities: pvolume, no
# pswitch), so `sset toggle` silently does nothing there. Fall back to parking
# the volume at 0 and restoring it.
has_switch() {
  amixer -D default sget "$CONTROL" 2>/dev/null | grep -q 'pswitch'
}

STEP=10

# Relative steps (`10%-`) are applied to the control's raw range, which is
# 0-255, so 10% is 25.5 and truncates. Each press lands off-grid and the
# displayed percentage drifts: 100 90 80 69 59 49 39 29 18 8. Snapping to a
# multiple of STEP and setting an absolute percentage keeps every step exact.
step_to() {
  local cur base new
  cur=$(read_vol); cur=${cur:-0}
  base=$(( (cur + STEP / 2) / STEP * STEP ))
  new=$(( base + $1 * STEP ))
  (( new > 100 )) && new=100
  (( new < 0 )) && new=0
  amixer -D default sset "$CONTROL" "${new}%" unmute >/dev/null 2>&1
}

case "$1" in
  up)   step_to 1 ;;
  down) step_to -1 ;;
  mute)
    if has_switch; then
      amixer -D default sset "$CONTROL" toggle >/dev/null 2>&1
    else
      cur=$(read_vol)
      if [ "${cur:-0}" -gt 0 ]; then
        printf '%s\n' "$cur" > "$MUTE_STATE"
        amixer -D default sset "$CONTROL" 0% >/dev/null 2>&1
      else
        restore=$(cat "$MUTE_STATE" 2>/dev/null)
        [ -n "$restore" ] || restore=40
        amixer -D default sset "$CONTROL" "${restore}%" >/dev/null 2>&1
      fi
    fi
    ;;
esac

info=$(amixer -D default sget "$CONTROL")
vol=$(printf '%s\n' "$info" | awk -F'[][]' '/%/ {print $2; exit}' | tr -d '%')

# Match [off] directly instead of by field position: a control that reports dB
# shifts every field right, so the old `$4` picked up "0.00dB" and never "off".
if printf '%s\n' "$info" | grep -q '\[off\]' || [ "${vol:-0}" -eq 0 ]; then
  icon=$ICONS/audio-volume-muted-symbolic.svg
  notify-send -a osd -i "$icon" -h int:value:0 -h string:x-canonical-private-synchronous:volume "Volume" "Muted" -t 1500
else
  if   (( vol > 66 )); then icon=$ICONS/audio-volume-high-symbolic.svg
  elif (( vol > 33 )); then icon=$ICONS/audio-volume-medium-symbolic.svg
  else                      icon=$ICONS/audio-volume-low-symbolic.svg
  fi
  notify-send -a osd -i "$icon" -h int:value:"$vol" -h string:x-canonical-private-synchronous:volume "Volume" "${vol}%" -t 1500
fi
