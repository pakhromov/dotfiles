#!/bin/bash
set -o pipefail

copy_clipboard() {
    python3 -c '
import base64
import subprocess
import sys

api = "hl.plugin.clipboard_bridge."
token = None

def call(code, result=False):
    process = subprocess.run(["hyprctl", "repl" if result else "eval", code], capture_output=True, text=True)
    if process.returncode or process.stdout.startswith("error:"):
        raise RuntimeError(process.stdout.strip() or process.stderr.strip() or "hyprctl failed")
    return process.stdout.strip()

try:
    mime = "\"" + "".join("\\%03d" % byte for byte in sys.argv[1].encode()) + "\""
    reply = call(api + "begin_copy(" + mime + ")", result=True)
    if not reply.isdecimal():
        raise RuntimeError("unexpected upload ID: " + reply)
    token = reply
    while True:
        chunk = sys.stdin.buffer.read(48 * 1024)
        if not chunk:
            break
        encoded = base64.b64encode(chunk).decode("ascii")
        call(api + "append_copy(" + token + ",\"" + encoded + "\")")
    call(api + "finish_copy(" + token + ")")
    token = None
except (OSError, RuntimeError, KeyboardInterrupt) as error:
    print("clipboard_bridge: " + str(error), file=sys.stderr)
    sys.exit(1)
finally:
    if token is not None:
        try:
            call(api + "cancel_copy(" + token + ")")
        except (OSError, RuntimeError):
            pass
' "${1:-text/plain;charset=utf-8}"
}

footer='<span foreground="#a0a0a0">TAB</span> <span foreground="#00cdcd">select</span>   <span foreground="#a0a0a0">DELETE</span> <span foreground="#00cdcd">remove</span>   <span foreground="#a0a0a0">ENTER</span> <span foreground="#00cdcd">copy</span>   <span foreground="#a0a0a0">CTRL+SPACE</span> <span foreground="#00cdcd">space</span>   <span foreground="#a0a0a0">ALT+,</span> <span foreground="#00cdcd">comma</span>   <span foreground="#a0a0a0">ALT+SPACE</span> <span foreground="#00cdcd">comma+space</span>'

list_entries() {
    local help
    help=$(cliphist --help 2>&1)
    if [[ $help == *-fields* ]]; then
        cliphist list -fields id,mime,format,preview | awk -F '\t' '
            ($2 ~ /^text\// || $2 == "UTF8_STRING" || $2 == "TEXT" || $2 == "STRING" || ($2 == "" && $3 == "")) {
                print $1 "\t" $4
            }'
    else
        cliphist list | awk -F '\t' '$2 !~ /^\[\[ binary data /'
    fi
}

pick() {
    local ret selection idx sep combined entry id first
    local -a rows ids selected

    while :; do
        mapfile -t rows < <(list_entries)
        [ "${#rows[@]}" -eq 0 ] && return 1
        ids=("${rows[@]%%$'\t'*}")

        selection=$(printf '%s\n' "${rows[@]#*$'\t'}" | rofi -dmenu -multi-select -format i \
            -matching normal \
            -p ' CLIPHIST HISTORY ' \
            -mesg "$footer" \
            -ballot-selected-str '┃' \
            -ballot-unselected-str ' ' \
            -kb-row-select "" \
            -kb-element-next "" \
            -kb-accept-alt "Tab" \
            -kb-remove-char-forward "Control+d" \
            -kb-custom-1 "Delete" \
            -kb-custom-2 "Control+space" \
            -kb-custom-3 "Alt+comma" \
            -kb-custom-4 "Alt+space")
        ret=$?
        [ -z "$selection" ] && return 1
        case "$ret" in 0|10|11|12|13) ;; *) return 1 ;; esac

        selected=()
        while IFS= read -r idx; do
            [[ $idx =~ ^[0-9]+$ ]] && ((idx < ${#ids[@]})) || return 1
            selected+=("${ids[idx]}")
        done <<< "$selection"

        if [ "$ret" -eq 10 ]; then
            printf '%s\n' "${selected[@]}" | cliphist delete || return 1
            continue
        fi
        break
    done

    sep=$'\n'
    case "$ret" in
        11) sep=' ' ;;
        12) sep=',' ;;
        13) sep=', ' ;;
    esac
    combined=""
    first=1
    for id in "${selected[@]}"; do
        # The sentinel preserves trailing newlines through command substitution.
        entry=$(printf '%s' "$id" | cliphist decode && printf '\001') || return 1
        entry=${entry%$'\001'}
        if [ "$first" -eq 0 ]; then combined+="$sep"; fi
        combined+="$entry"
        first=0
    done
    printf '%s' "$combined" | copy_clipboard
}

current_desktop() {
    case ":${XDG_CURRENT_DESKTOP,,}:" in
        *:hyprland:*) echo hyprland ;;
        *:wayfire:*) echo wayfire ;;
        *) echo unknown ;;
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
        wayfire) inject-key KEY_V KEY_LEFTCTRL KEY_LEFTSHIFT ;;
        *) return 1 ;;
    esac
}

target=$(capture_target)
if pick; then
    paste_into "$target"
else
    exit 1
fi
