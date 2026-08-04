#!/bin/bash

STORE="${ZZZCLIP_STORE_PATH:-${XDG_STATE_HOME:-$HOME/.local/state}/zzzclip}"

footer='<span foreground="#a0a0a0">TAB</span> <span foreground="#00cdcd">select</span>   <span foreground="#a0a0a0">DELETE</span> <span foreground="#00cdcd">remove</span>   <span foreground="#a0a0a0">ENTER</span> <span foreground="#00cdcd">copy</span>   <span foreground="#a0a0a0">CTRL+SPACE</span> <span foreground="#00cdcd">space</span>   <span foreground="#a0a0a0">ALT+,</span> <span foreground="#00cdcd">comma</span>   <span foreground="#a0a0a0">ALT+SPACE</span> <span foreground="#00cdcd">comma+space</span>'

list_entries() {
    zzzclip list -v | awk '
      /^[^\t]/          { if (l != "") emit(); l = $0; m = ""; p = ""; next }
      /^\tMIME types: / { m = substr($0, 14); next }
      /^\tPreview: /    { p = substr($0, 11) }
      END               { if (l != "") emit() }
      function emit() {
        if (m ~ /(^|, )text\//) { gsub(/\t/, " ", p); print l "\t" p }
      }
    '
}

pick() {
    local ret selpick_raw idx sep combined entry id
    local -a rows ids sel_ids

    while :; do
        mapfile -t rows < <(list_entries)
        [ "${#rows[@]}" -eq 0 ] && return 1

        ids=("${rows[@]%%$'\t'*}")

        selpick_raw=$(printf '%s\n' "${rows[@]#*$'\t'}" | rofi -dmenu -multi-select -format i \
            -matching normal \
            -p ' ZZZCLIP HISTORY ' \
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

        [ -z "$selpick_raw" ] && return 1

        # -format i emits plain integers, one per line, so word splitting is safe
        sel_ids=()
        for idx in $selpick_raw; do
            sel_ids+=("${ids[idx]}")
        done

        if [ "$ret" -eq 10 ]; then
            zzzclip delete "${sel_ids[@]}"
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
    for id in "${sel_ids[@]}"; do
        entry=$(<"$STORE/$id")
        combined="${combined:+$combined$sep}$entry"
    done

    printf '%s' "$combined" | wl-copy
}

if pick; then
    if ! inject-key KEY_V KEY_LEFTCTRL KEY_LEFTSHIFT; then
        #sleep 0.1
        wtype -M ctrl -M shift -k v
    fi
    pkill -x wl-copy || true
fi
