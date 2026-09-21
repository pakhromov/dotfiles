#!/bin/bash

message='<span foreground="#a0a0a0">TAB</span> <span foreground="#00cdcd">select</span>   <span foreground="#a0a0a0">ENTER</span> <span foreground="#00cdcd">copy</span>'

# Paste the selection into the window that was focused before the menu opened.
# Gated on XDG_CURRENT_DESKTOP (a colon-separated list, e.g. "Wayfire:wlroots").
#   hyprland - native send_shortcut dispatcher; addressing the window explicitly
#              avoids racing rofi's focus handback.
#   wayfire  - inject-key, as before.
current_desktop() {
    case ":${XDG_CURRENT_DESKTOP,,}:" in
        *:hyprland:*) echo hyprland ;;
        *:wayfire:*)  echo wayfire ;;
        *)            echo unknown ;;
    esac
}

capture_target() {
    [ "$(current_desktop)" = hyprland ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty'
}

paste_into() {
    local win="$1" lua

    case "$(current_desktop)" in
        hyprland)
            if [ -n "$win" ]; then
                lua=$(printf 'hl.dsp.send_shortcut({ mods = "CTRL SHIFT", key = "V", window = "address:%s" })' "$win")
            else
                lua='hl.dsp.send_shortcut({ mods = "CTRL SHIFT", key = "V" })'
            fi
            hyprctl dispatch "$lua" >/dev/null
            ;;
        wayfire)
            inject-key KEY_V KEY_LEFTCTRL KEY_LEFTSHIFT
            ;;
        *)
            return 1
            ;;
    esac
}

target=$(capture_target)

sel=$(rofi -dmenu -multi-select -matching normal \
    -p ' UNICODE PICKER ' \
    -mesg "$message" \
    -ballot-selected-str '┃' \
    -ballot-unselected-str ' ' \
    -kb-element-next "" \
    -kb-accept-alt "Tab" \
    < ~/.local/share/icons/unicode.txt | awk '{print $1}' | tr -d "\n")

if [ -n "$sel" ]; then
    setsid wl-copy -- "$sel" >/dev/null 2>&1 &
    sleep 0.1
    paste_into "$target"
    pkill -x wl-copy 2>/dev/null || true
fi
