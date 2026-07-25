#!/bin/bash

footer='<span foreground="#a0a0a0">TAB</span> <span foreground="#00cdcd">select</span>   <span foreground="#a0a0a0">DELETE</span> <span foreground="#00cdcd">remove</span>   <span foreground="#a0a0a0">ENTER</span> <span foreground="#00cdcd">copy</span>   <span foreground="#a0a0a0">CTRL+SPACE</span> <span foreground="#00cdcd">space</span>   <span foreground="#a0a0a0">ALT+,</span> <span foreground="#00cdcd">comma</span>   <span foreground="#a0a0a0">ALT+SPACE</span> <span foreground="#00cdcd">comma+space</span>'

list_entries() {
    cclip list id,mime,preview | awk -F'\t' '$2 ~ /^text\// {print $1"\t"$3}'
}

# Runs the picker (looping on delete so the list can refresh), then copies
# the result to the clipboard. Returns 1 if the user cancelled.
pick() {
    local ret selpick_raw menu idx sep combined entry id r
    local -a rows ids selpick sel_ids

    while :; do
        mapfile -t rows < <(list_entries)
        [ "${#rows[@]}" -eq 0 ] && return 1

        ids=()
        menu=""
        for r in "${rows[@]}"; do
            ids+=("${r%%$'\t'*}")
            menu+="${r#*$'\t'}"$'\n'
        done

        selpick_raw=$(printf '%s' "$menu" | rofi -dmenu -multi-select -format i \
            -matching normal \
            -p ' CLIPBOARD HISTORY ' \
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
        mapfile -t selpick <<< "$selpick_raw"

        sel_ids=()
        for idx in "${selpick[@]}"; do
            sel_ids+=("${ids[idx]}")
        done

        if [ "$ret" -eq 10 ]; then
            for id in "${sel_ids[@]}"; do cclip delete "$id"; done
            continue
        fi

        break
    done

    if [ "${#sel_ids[@]}" -eq 1 ]; then
        cclip copy "${sel_ids[0]}"
    else
        sep=$'\n'
        case "$ret" in
            11) sep=' ' ;;
            12) sep=',' ;;
            13) sep=', ' ;;
        esac
        combined=""
        for id in "${sel_ids[@]}"; do
            entry=$(cclip get "$id" 2>/dev/null)
            combined="${combined:+$combined$sep}$entry"
        done
        printf '%s' "$combined" | wl-copy
        sleep 0.1
        cclip copy "$(cclip list id | head -1)"
    fi
}

if pick; then
    if ! inject-key KEY_V KEY_LEFTCTRL KEY_LEFTSHIFT; then
        sleep 0.1
        wtype -M ctrl -M shift -k v
    fi
    pkill -x wl-copy 2>/dev/null || true
fi
