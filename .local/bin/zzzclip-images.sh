#!/bin/bash

STORE="${ZZZCLIP_STORE_PATH:-${XDG_STATE_HOME:-$HOME/.local/state}/zzzclip}"

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
  --border-label ' ZZZCLIP IMAGES '
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

# The store keeps byte copies under extensionless labels, so anything that
# leaves it needs an extension from the real MIME type or a jpeg/webp ends up
# named .png. `get -l` only prints MIME strings, so it is unaffected by the
# binary-output bug.
_ext() {
  mime=$(zzzclip get -l "$1" 2>/dev/null | head -1)
  ext="${mime#image/}"
  ext="${ext%%+*}"   # image/svg+xml -> svg
  case "$ext" in jpeg) ext=jpg ;; ""|*/*) ext=png ;; esac
  printf '%s' "$ext"
}

case "$1" in
  --list)

    mapfile -t rows < <(zzzclip list -v | awk '
      /^[^\t]/          { if (l != "") emit(); l = $0; m = ""; p = ""; next }
      /^\tMIME types: / { m = substr($0, 14); next }
      /^\tPreview: /    { p = substr($0, 11) }
      END               { if (l != "") emit() }
      function emit(   ext, size, i) {
        if (m !~ /(^|, )image\//) return
        ext = m; sub(/,.*/, "", ext); sub(/^image\//, "", ext); sub(/\+.*/, "", ext)
        i = index(p, ", ")
        size = (i > 0) ? substr(p, i + 2) : "?"
        print l "\t" size " " ext
      }
    ')
    [ "${#rows[@]}" -eq 0 ] && exit 0

    # zzzclip records no dimensions, so they come from file(1) - called once
    # for every image rather than once per row, which keeps this flat as the
    # history grows. It emits one line per argument, so the two arrays align.
    kept=(); paths=()
    for r in "${rows[@]}"; do
      f="$STORE/${r%%$'\t'*}"
      [ -f "$f" ] || continue
      kept+=("$r"); paths+=("$f")
    done
    [ "${#kept[@]}" -eq 0 ] && exit 0
    mapfile -t descs < <(file --brief "${paths[@]}" 2>/dev/null)

    # zzzclip records no timestamps either, so the copy time is the file mtime.
    # One batched stat(1) for the whole set, same shape as the file(1) call.
    mapfile -t mtimes < <(stat -c %Y "${paths[@]}" 2>/dev/null)
    now=$(date +%s)

    # file(1) spaces dimensions differently per format - "1920 x 1080" for PNG
    # and GIF, "1920x1080" for JPEG and WebP - so allow both. Requiring a whole
    # comma-delimited field starting with a digit avoids matching JPEG's
    # "density 1x1", which would otherwise win as the earlier match.
    dims_re='(^|, )([0-9]+) ?x ?([0-9]+)(,|$)'
    for i in "${!kept[@]}"; do
      dims=""
      [[ "${descs[i]}" =~ $dims_re ]] && dims="${BASH_REMATCH[2]}x${BASH_REMATCH[3]}"
      age=$(( now - mtimes[i] ))
      if   [ "$age" -lt 60 ];    then ago="now"
      elif [ "$age" -lt 3600 ];  then ago="$((age / 60))m ago"
      elif [ "$age" -lt 86400 ]; then ago="$((age / 3600))h ago"
      else                            ago="$((age / 86400))d ago"
      fi
      # kept[i] is "label<TAB>size ext"; the tab-delimited label has to stay
      # first for fzf's --with-nth, so the columns are rebuilt around it.
      printf '%s\t%-10s %-14s %s\n' "${kept[i]%%$'\t'*}" "$dims" "${kept[i]#*$'\t'}" "$ago"
    done
    ;;
  --preview)
    kitty +kitten icat --clear --transfer-mode=memory --unicode-placeholder --stdin=no \
      --place="${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0" "$STORE/$2" 2>/dev/null | sed $'$s/$/\e[m/'
    ;;
  --save)
    shift
    count=$#
    for label in "$@"; do
      timestamp=$(date +%Y%m%d_%H%M%S_%N)
      filename="clipboard_${timestamp}.$(_ext "$label")"
      cp "$STORE/$label" ~/Pictures/"$filename" 2>/dev/null
    done
    if [ "$count" -eq 1 ]; then msg="Saved $filename"; else msg="Saved $count images"; fi
    # -A names the default action, which dunst fires on left click (its
    # mouse_left_click is do_action) and notify-send then echoes on stdout.
    # -A implies --wait, so this runs in the background to keep fzf responsive.
    { [ "$(notify-send -a osd -i /usr/share/icons/Cosmic/scalable/devices/camera-photo-symbolic.svg \
           -t 5000 -A default="Open folder" "$msg")" = default ] \
        && xdg-open ~/Pictures; } >/dev/null 2>&1 &
    ;;
  --delete)
    shift
    zzzclip delete "$@"
    ;;
  --edit)
    swappy -f "$STORE/$2"
    ;;
  --open)
    shift
    # A viewer takes one path and builds its own file list by scanning that
    # file's directory - qimgv filters that scan on a filename regex, so the
    # extensionless store names are invisible to it and every window would hold
    # a single image. Handing it a directory of named symlinks instead is what
    # puts the whole selection in one window; the index prefix keeps the
    # viewer's name sort in the order the list showed.
    view=$(mktemp -d)
    i=0; first=""
    for label in "$@"; do
      i=$((i + 1))
      link=$(printf '%s/%03d_%s.%s' "$view" "$i" "$label" "$(_ext "$label")")
      ln -s "$STORE/$label" "$link"
      [ -z "$first" ] && first="$link"
    done
    # xdg-open only returns once the viewer exits, so the links live exactly as
    # long as the window does. Backgrounded to keep fzf responsive.
    { xdg-open "$first"; rm -rf "$view"; } >/dev/null 2>&1 &
    ;;
  --drag)
    shift
    files=()
    for label in "$@"; do
      files+=("$STORE/$label")
    done
    # -a drags the whole selection as one grab. dragon-drop holds its window
    # open until the drop lands, so it runs in the background to keep fzf
    # responsive.
    dragon-drop -a -x -i -T "${files[@]}" >/dev/null 2>&1 &
    ;;
  *)
    sel=$($0 --list | fzf \
      --preview "$0 --preview {1}" \
      --bind "ctrl-s:execute-silent($0 --save {+1})" \
      --bind "ctrl-e:execute-silent($0 --edit {1})" \
      --bind "ctrl-d:execute-silent($0 --drag {+1})" \
      --bind "right:execute-silent($0 --open {+1})" \
      --bind "delete,bspace:execute-silent($0 --delete {+1})+reload($0 --list)")
    [ -z "$sel" ] && exit
    label="${sel%%$'\t'*}"
    zzzclip get "$label"
    ;;
esac
