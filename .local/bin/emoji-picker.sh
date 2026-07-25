#!/bin/bash

message='<span foreground="#a0a0a0">TAB</span> <span foreground="#00cdcd">select</span>   <span foreground="#a0a0a0">ENTER</span> <span foreground="#00cdcd">copy</span>'

sel=$(rofi -dmenu -multi-select -matching normal \
    -p ' EMOJI PICKER ' \
    -mesg "$message" \
    -ballot-selected-str '┃' \
    -ballot-unselected-str ' ' \
    -kb-element-next "" \
    -kb-accept-alt "Tab" \
    < ~/.local/bin/icons/emoji.txt | awk '{print $1}' | tr -d "\n")

if [ -n "$sel" ]; then
    setsid wl-copy -- "$sel" >/dev/null 2>&1 &
    sleep 0.1
    if ! inject-key KEY_V KEY_LEFTCTRL KEY_LEFTSHIFT; then
        sleep 0.1
        wtype -M ctrl -M shift -k v
    fi
    pkill -x wl-copy 2>/dev/null || true
fi
