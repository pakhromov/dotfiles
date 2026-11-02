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

self=$(realpath -- "$0")
if [ -z "${CLIPHIST_IMAGE_CACHE:-}" ]; then
    CLIPHIST_IMAGE_CACHE=$(mktemp -d "${TMPDIR:-/tmp}/cliphist-images.XXXXXX") || exit 1
    export CLIPHIST_IMAGE_CACHE
    trap 'rm -rf -- "$CLIPHIST_IMAGE_CACHE"' EXIT
fi

_footer=$' \033[38;2;160;160;160mTAB\033[36m select   \033[38;2;160;160;160mCTRL+S\033[36m save   \033[38;2;160;160;160mCTRL+E\033[36m edit   \033[38;2;160;160;160mCTRL+D\033[36m drag   \033[38;2;160;160;160mRIGHT\033[36m open   \033[38;2;160;160;160mDEL\033[36m delete   \033[38;2;160;160;160mENTER\033[36m copy\033[m '

export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS
  --preview-window=right:70%
  --preview-label \"$_footer\"
  --preview-label-pos 'bottom'
  -d '\t' --with-nth 2
  --no-sort --multi --reverse --no-hscroll --height=100%
  --no-input
  --no-input-border
  --highlight-line
  --scroll-off 7
  --info=right
  --border
  --border-label ' CLIPHIST IMAGES '
  --info-command='echo -e \"\$FZF_POS/\$FZF_MATCH_COUNT(\$FZF_SELECT_COUNT)\"'
  --footer-border 'none'
  --pointer '>'
  --gutter '┃'
  --marker '┃'
  --ellipsis '  '
  --scrollbar ''
  --separator ''
  --color fg:242,bg:233,hl:65,fg+:222,bg+:234,hl+:108
  --color info:108,prompt:110,spinner:150,pointer:167,marker:65
"

# Decoding is on demand; each browser session owns its temporary preview files.
image_path() {
    local id="$1" temp
    [[ $id =~ ^[0-9]+$ ]] || return 1
    if [ ! -f "$CLIPHIST_IMAGE_CACHE/$id" ]; then
        temp=$(mktemp "$CLIPHIST_IMAGE_CACHE/$id.XXXXXX") || return 1
        if ! printf '%s' "$id" | cliphist decode > "$temp"; then
            rm -f -- "$temp"
            return 1
        fi
        mv -f -- "$temp" "$CLIPHIST_IMAGE_CACHE/$id" || return 1
    fi
    printf '%s' "$CLIPHIST_IMAGE_CACHE/$id"
}

image_ext() {
    local mime ext
    mime=$(file --brief --mime-type -- "$1") || return 1
    ext=${mime#image/}
    ext=${ext%%+*}
    case "$ext" in jpeg) ext=jpg ;; ""|*/*) ext=png ;; esac
    printf '%s' "$ext"
}

list_images() {
    local help
    help=$(cliphist --help 2>&1)
    if [[ $help == *-fields* ]]; then
        cliphist list -fields id,mime,format,timestamp,preview
    else
        # Older cliphist has image metadata in previews, but no copy timestamps.
        cliphist list | awk -F '\t' '{ print $1 "\t\t\t\t" $2 }'
    fi | awk -F '\t' -v now="$(date +%s)" '
        $2 ~ /^image\// || $3 != "" || $5 ~ /^\[\[ binary data / {
            dims = "?"; size = "?"; ext = $3; ago = "?"
            if (ext == "") { ext = $2; sub(/^image\//, "", ext); sub(/\+.*/, "", ext) }
            if ($5 ~ /^\[\[ binary data /) {
                description = $5
                sub(/^\[\[ binary data /, "", description)
                sub(/ \]\]$/, "", description)
                n = split(description, parts, " ")
                dims = parts[n]; ext = parts[n-1]; size = parts[1]
                for (i = 2; i < n-1; i++) size = size " " parts[i]
            }
            if ($4 ~ /^[0-9]+$/ && $4 > 0) {
                age = now - $4
                if (age < 60) ago = "now"
                else if (age < 3600) ago = int(age / 60) "m ago"
                else if (age < 86400) ago = int(age / 3600) "h ago"
                else ago = int(age / 86400) "d ago"
            }
            printf "%s\t%-10s %-14s %s\n", $1, dims, size " " ext, ago
        }'
}

# Viewers and drag windows get independent files so closing fzf cannot remove
# their data. An opener can return before the viewer has read its file.
export_images() {
    local id path ext index=0
    exported_dir=$(mktemp -d "$1/cliphist-export.XXXXXX") || return 1
    shift
    exported_files=()
    for id in "$@"; do
        path=$(image_path "$id") && ext=$(image_ext "$path") || {
            rm -rf -- "$exported_dir"
            return 1
        }
        index=$((index + 1))
        printf -v exported_path '%s/%03d_%s.%s' "$exported_dir" "$index" "$id" "$ext"
        cp -- "$path" "$exported_path" || { rm -rf -- "$exported_dir"; return 1; }
        exported_files+=("$exported_path")
    done
}

case "${1:-}" in
    --list)
        list_images
        ;;
    --preview)
        path=$(image_path "$2") || exit 1
        kitty +kitten icat --clear --transfer-mode=stream --unicode-placeholder --stdin=no \
            --place="${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0" "$path" 2>/dev/null | sed $'$s/$/\e[m/'
        ;;
    --save)
        shift
        count=$#
        for id in "$@"; do
            path=$(image_path "$id") && ext=$(image_ext "$path") || exit 1
            filename="clipboard_$(date +%Y%m%d_%H%M%S_%N).$ext"
            cp -- "$path" "$HOME/Pictures/$filename" || exit 1
        done
        if [ "$count" -eq 1 ]; then msg="Saved $filename"; else msg="Saved $count images"; fi
        { [ "$(notify-send -a osd -i /usr/share/icons/Cosmic/scalable/devices/camera-photo-symbolic.svg \
                -t 5000 -A default="Open folder" "$msg")" = default ] \
                && xdg-open "$HOME/Pictures"; } >/dev/null 2>&1 &
        ;;
    --delete)
        shift
        printf '%s\n' "$@" | cliphist delete || exit 1
        for id in "$@"; do
            [[ $id =~ ^[0-9]+$ ]] && rm -f -- "$CLIPHIST_IMAGE_CACHE/$id"
        done
        ;;
    --edit)
        path=$(image_path "$2") || exit 1
        swappy -f "$path"
        ;;
    --open)
        shift
        # Successful opens keep their files for the runtime directory's life;
        # xdg-open does not report when a viewer has finished using them.
        export_images "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}" "$@" || exit 1
        { xdg-open "${exported_files[0]}" || rm -rf -- "$exported_dir"; } >/dev/null 2>&1 &
        ;;
    --drag)
        shift
        export_images "${TMPDIR:-/tmp}" "$@" || exit 1
        { dragon-drop -a -x -i -T "${exported_files[@]}"; rm -rf -- "$exported_dir"; } >/dev/null 2>&1 &
        ;;
    *)
        selection=$("$self" --list | fzf \
            --preview "'$self' --preview {1}" \
            --bind "ctrl-s:execute-silent('$self' --save {+1})" \
            --bind "ctrl-e:execute-silent('$self' --edit {1})" \
            --bind "ctrl-d:execute-silent('$self' --drag {+1})" \
            --bind "right:execute-silent('$self' --open {+1})" \
            --bind "delete,bspace:execute-silent('$self' --delete {+1})+reload('$self' --list)") || exit 1
        [ -n "$selection" ] || exit 1
        id=${selection%%$'\t'*}
        path=$(image_path "$id") || exit 1
        mime=$(file --brief --mime-type -- "$path") || exit 1
        copy_clipboard "$mime" < "$path"
        ;;
esac
