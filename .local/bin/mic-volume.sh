#!/bin/bash

exec 9>/tmp/.mic-volume.lock
flock -n 9 || exit 0

ICONS=/usr/share/icons/Cosmic/scalable/status
MUTE_STATE=/tmp/.mic-volume-mute-level
RC="$HOME/.asoundrc"

notify() {  # $1 = icon name, $2 = body, $3 = value
  notify-send -a osd -i "$ICONS/$1" -h int:value:"$3" \
    -h string:x-canonical-private-synchronous:mic "Microphone" "$2" -t 1500
}

# The capture card is whatever audio-switch wrote, not `default`: ctl.!default
# points at the *output* card, so with the TV selected and the laptop mic in
# use, -D default would reach the wrong hardware entirely.
CARD=$(grep -oE 'dsnoop:CARD=[^,]+' "$RC" 2>/dev/null | head -1 | cut -d= -f2)
[ -n "$CARD" ] || { notify microphone-sensitivity-muted-symbolic.svg "None" 0; exit 1; }

# Work on the raw control elements rather than the simple mixer. On a headset
# the simple control carries playback AND capture, and `sset '<ctl>' 50% cap`
# moves both -- adjusting the mic would quietly change headphone volume too.
# Boost controls are skipped; they are a separate gain stage, not the level.
controls=$(amixer -c "$CARD" controls 2>/dev/null)
VOL_ID=$(grep -E "name='.*Capture Volume'" <<<"$controls" | grep -v Boost |
         sed 's/^numid=\([0-9]*\).*/\1/' | sort -n | head -1)
[ -n "$VOL_ID" ] || { notify microphone-sensitivity-muted-symbolic.svg "None" 0; exit 1; }

VOL_NAME=$(grep "^numid=$VOL_ID," <<<"$controls" | sed "s/.*name='\(.*\)'.*/\1/")
SW_ID=$(grep -F "name='${VOL_NAME% Volume} Switch'" <<<"$controls" |
        sed 's/^numid=\([0-9]*\).*/\1/' | head -1)

read_vol() {
  local out mx v
  out=$(amixer -c "$CARD" cget numid="$VOL_ID" 2>/dev/null)
  mx=$(sed -n 's/.*max=\([0-9]*\).*/\1/p' <<<"$out" | head -1)
  v=$(sed -n 's/^  : values=\([0-9]*\).*/\1/p' <<<"$out" | head -1)
  if [ -n "$mx" ] && [ "$mx" -gt 0 ]; then echo $(( (v * 100 + mx / 2) / mx )); else echo 0; fi
}

is_muted() {
  [ -n "$SW_ID" ] || return 1
  amixer -c "$CARD" cget numid="$SW_ID" 2>/dev/null | grep -q ': values=off'
}

STEP=10

# Snap to a multiple of STEP for both the step arithmetic and the display.
# Capture controls often have few hardware steps, so a requested 70% can read
# back as 69% or 71% depending on the range the card reports. Snapping keeps
# the OSD on an exact 10% grid and stops the value drifting as it is stepped
# repeatedly. The range itself is read from the card in read_vol.
snap() { echo $(( ( ${1:-0} + STEP / 2 ) / STEP * STEP )); }

step_to() {
  local new
  new=$(( $(snap "$(read_vol)") + $1 * STEP ))
  (( new > 100 )) && new=100
  (( new < 0 )) && new=0
  amixer -c "$CARD" cset numid="$VOL_ID" "${new}%" >/dev/null 2>&1
  [ -n "$SW_ID" ] && amixer -c "$CARD" cset numid="$SW_ID" on >/dev/null 2>&1
}

case "$1" in
  up)   step_to 1 ;;
  down) step_to -1 ;;
  mute)
    if [ -n "$SW_ID" ]; then
      if is_muted; then
        amixer -c "$CARD" cset numid="$SW_ID" on >/dev/null 2>&1
      else
        amixer -c "$CARD" cset numid="$SW_ID" off >/dev/null 2>&1
      fi
    else
      # No capture switch: park the level at 0 and put it back next time.
      cur=$(read_vol)
      if [ "${cur:-0}" -gt 0 ]; then
        printf '%s\n' "$cur" > "$MUTE_STATE"
        amixer -c "$CARD" cset numid="$VOL_ID" 0% >/dev/null 2>&1
      else
        restore=$(cat "$MUTE_STATE" 2>/dev/null)
        [ -n "$restore" ] || restore=40
        amixer -c "$CARD" cset numid="$VOL_ID" "${restore}%" >/dev/null 2>&1
      fi
    fi
    ;;
esac

vol=$(snap "$(read_vol)")

if is_muted || [ "${vol:-0}" -eq 0 ]; then
  notify microphone-sensitivity-muted-symbolic.svg "Muted" 0
else
  if   (( vol > 66 )); then icon=microphone-sensitivity-high-symbolic.svg
  elif (( vol > 33 )); then icon=microphone-sensitivity-medium-symbolic.svg
  else                      icon=microphone-sensitivity-low-symbolic.svg
  fi
  notify "$icon" "${vol}%" "$vol"
fi
