#!/bin/bash
# audio-default - point ~/.asoundrc at one specific device, or at nothing.
#
# Meant for session startup. Unlike audio-switch, this one is deliberately
# opinionated: only the device named below may become the default on its own.
# If it is not connected, output is muted and no microphone is reachable --
# never a fallback to speakers or a built-in mic. Anything else has to be
# chosen by hand through audio-switch.

DEVICE="Sennheiser"

RC="$HOME/.asoundrc"

# Devices that are actually connected, as: <card-id> <device> <label>
# $1 is aplay or arecord. Jack sensors named '...pcm=N Jack' report whether
# device N has anything plugged into it. Devices with no such sensor are
# always listed.
devices() {
    $1 -l 2>/dev/null | grep '^card' | grep -v Loopback | \
    sed -n 's/card \([0-9]*\): [^[]*\[\([^]]*\)\], device \([0-9]*\): [^[]*\[\([^]]*\)\]/\1 \3 \2 — \4/p' | \
    while read -r num dev label; do
        state=$(amixer -c "$num" contents 2>/dev/null | awk -v want="$dev" '
            /iface=CARD.*pcm=[0-9]+.*Jack/ {
                if (match($0, /pcm=[0-9]+/)) cur = substr($0, RSTART+4, RLENGTH-4); next }
            /: values=/ { if (cur != "" && cur "" == want "") { print (index($0,"values=on") ? "on" : "off"); f=1; exit } }
            END { if (!f) print "na" }')
        [[ "$state" == off ]] && continue
        printf '%s\t%s\t%s\n' "$(< "/proc/asound/card$num/id")" "$dev" "$label"
    done
}

sel=$(grep -iF -- "$DEVICE" <<<"$(devices aplay)" | head -1)

if [[ -z "$sel" ]]; then
    echo "$DEVICE not connected - muting all output"
    # asym with no capture.pcm: playback is discarded and any attempt to open a
    # microphone fails, rather than returning noise.
    printf 'pcm.!default {\n    type asym\n    playback.pcm { type null }\n}\nctl.!default { type null }\n' > "$RC"
    exit 1
fi
IFS=$'\t' read -r ocard odev label <<<"$sel"

# Capture follows the same device, with no fallback: if it has no input,
# nothing is captured rather than some other microphone. A headset's physical
# mic switch is handled in its firmware and is invisible to ALSA, so this stays
# configured and simply goes quiet while that switch is off.
misel=$(grep -iF -- "$DEVICE" <<<"$(devices arecord)" | head -1)
if [[ -n "$misel" ]]; then IFS=$'\t' read -r icard idev _ <<<"$misel"
else icard=""; idev=""; fi

# No input -> leave capture.pcm out entirely, so opening an input fails cleanly.
# `type null` is wrong here: it opens successfully and returns uninitialised
# memory, i.e. full-scale noise, instead of nothing.
if [[ -n "$icard" ]]; then
    capture_pcm="    capture.pcm {
        type plug
        slave.pcm \"dsnoop:CARD=$icard,DEV=$idev\"
    }"
else
    capture_pcm=""
fi

# Card by name, not number: numbers shift when devices are unplugged.
# softvol because HDMI has no hardware volume at all, so this is the only
# control that works on every output. asym splits the two directions, since
# dmix is playback-only and capture cannot share it.
cat > "$RC" <<EOF
pcm.!default {
    type asym
    playback.pcm {
        type plug
        slave.pcm {
            type softvol
            slave.pcm "dmix:CARD=$ocard,DEV=$odev"
            control {
                name "Softmaster"
                card "$ocard"
            }
        }
    }
$capture_pcm
}
ctl.!default {
    type hw
    card "$ocard"
}
EOF

# Let the codec route to speakers when nothing is in the headphone jack, and
# lift anything left muted or at zero. Without this a card can be selected
# correctly and still be silent.
amixer -c "$ocard" sset 'Auto-Mute Mode' Enabled >/dev/null 2>&1
amixer -c "$ocard" scontrols 2>/dev/null | sed "s/^Simple mixer control '//; s/',[0-9]*$//" |
while IFS= read -r ctl; do
    case "$ctl" in *Capture*|*Mic*|*Loopback*|*Beep*|*IEC958*) continue ;; esac
    info=$(amixer -c "$ocard" sget "$ctl" 2>/dev/null)
    grep -q 'Playback channels' <<<"$info" || continue
    vol=$(awk -F'[][]' '/%/{print $2; exit}' <<<"$info" | tr -d '%')
    if grep -q '\[off\]' <<<"$info" || [[ "${vol:-0}" -eq 0 ]]; then
        amixer -c "$ocard" sset "$ctl" 60% unmute >/dev/null 2>&1
    fi
done

echo "Set: $label  [out $ocard,$odev  in ${icard:-none}${icard:+,$idev}]"
aplay -D default -f S16_LE -r 48000 -c 2 -d 1 -t raw /dev/zero &>/dev/null
