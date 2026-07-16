#!/usr/bin/env bash

ME=$(realpath "$0")

# ── Subcommands (called internally from fzf bindings) ─────────────────────────
case "${1:-}" in

--list)
    dir="$2"; renamed_f="$3"
    found=$(find "$dir" -maxdepth 1 -type f \
        \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
           -o -iname "*.gif" -o -iname "*.webp" -o -iname "*.avif" \) | sort)
    [[ -z "$found" ]] && exit 0
    if [[ -s "$renamed_f" ]]; then
        printf '%s\n' "$found" | grep -vFf "$renamed_f" || true
    else
        printf '%s\n' "$found"
    fi
    exit 0
    ;;

--preview)
    kitty +kitten icat --clear --transfer-mode=memory --unicode-placeholder --stdin=no \
        --place="${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0" "$2" 2>/dev/null |
        sed $'$s/$/\e[m/'
    exit 0
    ;;

--rename)
    file="$2"; cat="$3"; state="$4"; renamed_f="$5"
    count=$(cat "$state/count_$cat" 2>/dev/null || echo 0)
    ext="${file##*.}"
    dir=$(dirname "$file")
    newpath="$dir/${cat}_${count}.${ext}"
    while [[ -e "$newpath" ]]; do
        count=$((count + 1))
        newpath="$dir/${cat}_${count}.${ext}"
    done
    mv -- "$file" "$newpath"
    echo $((count + 1)) > "$state/count_$cat"
    printf '%s\n' "$newpath" >> "$renamed_f"
    exit 0
    ;;

esac

# ── Configuration: map single keys to category names ─────────────────────────
declare -A CATS=(
    []=""
    []=""
    []=""
    []=""
    []=""
    []=""
)

# ── Setup ─────────────────────────────────────────────────────────────────────
DIR=$(realpath "${1:-.}")
[[ -d "$DIR" ]] || { printf 'Not a directory: %s\n' "$DIR" >&2; exit 1; }

STATE=$(mktemp -d)
RENAMED="$STATE/renamed"
touch "$RENAMED"
trap 'rm -rf "$STATE"' EXIT

# ── Footer ────────────────────────────────────────────────────────────────────
_k=$'\033[38;2;160;160;160m'
_a=$'\033[36m'
_r=$'\033[m'
footer_text=""; footer_plain=""
for key in $(printf '%s\n' "${!CATS[@]}" | sort); do
    footer_text+="${_k}${key}${_a} ${CATS[$key]}   "
    footer_plain+="${key} ${CATS[$key]}   "
done
footer_text+="${_k}DEL${_a} delete   ${_r}"
footer_plain+="DEL delete   "
_pad=$(( $(tput cols 2>/dev/null || echo 80) - ${#footer_plain} - 7 ))
(( _pad > 0 )) && printf -v footer '%*s%s' "$_pad" '' "$footer_text" || footer=$footer_text

# ── Bindings ──────────────────────────────────────────────────────────────────
binds=()
for key in "${!CATS[@]}"; do
    cat="${CATS[$key]}"
    binds+=(--bind "${key}:execute-silent($ME --rename {} $cat $STATE $RENAMED)+reload($ME --list $DIR $RENAMED)")
done
binds+=(--bind "delete:execute-silent(rm -f {})+reload($ME --list $DIR $RENAMED)")

# ── Run ───────────────────────────────────────────────────────────────────────
"$ME" --list "$DIR" "$RENAMED" | fzf \
    --no-sort \
    --delimiter / --with-nth -1 \
    --border-label ' IMAGE RENAMER ' \
    --preview "$ME --preview {}" \
    --preview-window "right:70%:noinfo" \
    --footer "$footer" --footer-border none \
    --highlight-line \
    --scroll-off 7 \
    --info=inline-right \
    --border \
    --input-border \
    --prompt '> ' \
    --pointer '>' \
    --gutter '┃' \
    --marker '┃' \
    --ellipsis '  ' \
    --scrollbar '' \
    --separator '' \
    --color fg:242,bg:233,hl:65,fg+:222,bg+:234,hl+:108 \
    --color info:108,prompt:110,spinner:150,pointer:167,marker:65 \
    "${binds[@]}"
