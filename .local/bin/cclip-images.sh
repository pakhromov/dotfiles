#!/bin/bash

_footer=$' \033[38;2;160;160;160mTAB\033[36m select   \033[38;2;160;160;160mCTRL+S\033[36m save   \033[38;2;160;160;160mDEL\033[36m delete   \033[38;2;160;160;160mENTER\033[36m copy\033[m '

export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS
  --preview-window=right:70%
  --preview-label \"$_footer\"
  --preview-label-pos 'bottom'
  -d '\t' --with-nth 2
  --no-sort --multi --exact --reverse --no-hscroll --height=100%
  --highlight-line
  --scroll-off 7
  --info=inline-right
  --border
  --input-border
  --border-label ' CLIPBOARD IMAGES '
  --info-command='echo -e \"\$FZF_POS/\$FZF_MATCH_COUNT(\$FZF_SELECT_COUNT)\"'
  --footer-border 'none'
  --prompt '> '
  --pointer '>'
  --gutter '┃'
  --marker '┃'
  --ellipsis '  '
  --scrollbar ''
  --separator ''
  --color fg:242,bg:233,hl:65,fg+:222,bg+:234,hl+:108
  --color info:108,prompt:110,spinner:150,pointer:167,marker:65
"

case "$1" in
  --list)
    while IFS=$'\t' read -r id mime size; do
      [[ "$mime" == image/* ]] || continue
      ext="${mime#image/}"
      s=$((size))
      if (( s >= 1048576 )); then label="$((s / 1048576)) MiB"
      elif (( s >= 1024 )); then label="$((s / 1024)) KiB"
      else label="$s B"
      fi
      dims=$(cclip get "$id" | file --brief - 2>/dev/null | grep -oP '\d+ x \d+' | tr -d ' ')
      printf '%s\t%s %s %s\n' "$id" "$label" "$ext" "$dims"
    done < <(cclip list id,mime,size)
    ;;
  --preview)
    cclip get "$2" > /tmp/cclip-preview.png 2>/dev/null
    kitty +kitten icat --clear --transfer-mode=memory --unicode-placeholder --stdin=no \
      --place="${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0" /tmp/cclip-preview.png 2>/dev/null | sed $'$s/$/\e[m/'
    ;;
  --save)
    shift
    count=$#
    for id in "$@"; do
      timestamp=$(date +%Y%m%d_%H%M%S_%N)
      filename="clipboard_${timestamp}.png"
      cclip get "$id" > ~/Pictures/"$filename" 2>/dev/null
    done
    if [ "$count" -eq 1 ]; then
      notify-send -a osd -i /usr/share/icons/Cosmic/scalable/devices/camera-photo-symbolic.svg "Saved $filename" -t 1500
    else
      notify-send -a osd -i /usr/share/icons/Cosmic/scalable/devices/camera-photo-symbolic.svg "Saved $count images" -t 1500
    fi
    ;;
  --delete)
    shift
    for id in "$@"; do cclip delete "$id"; done
    ;;
  -t)
    $2 "$0"
    ;;
  *)
    sel=$($0 --list | fzf \
      --preview "$0 --preview {1}" \
      --bind "ctrl-s:execute-silent($0 --save {+1})" \
      --bind "delete:execute-silent($0 --delete {+1})+reload($0 --list)")
    [ -z "$sel" ] && exit
    id="${sel%%$'\t'*}"
    cclip copy "$id"
    ;;
esac
