#!/bin/bash

_footer=$' \033[38;2;160;160;160mTAB\033[36m select   \033[38;2;160;160;160mCTRL+S\033[36m save   \033[38;2;160;160;160mCTRL+DEL\033[36m delete   \033[38;2;160;160;160mENTER\033[36m copy   \033[38;2;160;160;160mESC\033[36m cancel\033[m '


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
  --ellipsis '  '
  --scrollbar ''
  --separator ''
  --color fg:242,bg:233,hl:65,fg+:222,bg+:234,hl+:108
  --color info:108,prompt:110,spinner:150,pointer:167,marker:65
"

case "$1" in
  --preview)
    printf '%s\t' "$2" | cliphist decode > /tmp/cliphist-preview.png 2>/dev/null
    kitty +kitten icat --clear --transfer-mode=memory --unicode-placeholder --stdin=no \
      --place="${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0" /tmp/cliphist-preview.png 2>/dev/null | sed '$d' | sed $'$s/$/\e[m/'
    ;;
  --save)
    shift
    count=$#
    for id in "$@"; do
      timestamp=$(date +%Y%m%d_%H%M%S_%N)
      filename="clipboard_${timestamp}.png"
      printf '%s\t' "$id" | cliphist decode > ~/Pictures/"$filename" 2>/dev/null
    done
    if [ "$count" -eq 1 ]; then
      notify-send -a osd -i /usr/share/icons/Cosmic/scalable/devices/camera-photo-symbolic.svg "Saved $filename" -t 1500
    else
      notify-send -a osd -i /usr/share/icons/Cosmic/scalable/devices/camera-photo-symbolic.svg "Saved $count images"-t 1500
    fi
    ;;
  --delete)
    shift
    for id in "$@"; do
      printf '%s\t' "$id" | cliphist delete
    done
    ;;
  -t)
    $2 "$0"
    ;;
  *)
    cliphist list | grep "\[\[ binary" | sed "s/\t\[\[ binary data /\t/; s/ \]\]$//" | fzf \
      --preview "$0 --preview {1}" \
      --bind "ctrl-s:execute-silent($0 --save {+1})" \
      --bind "ctrl-delete:execute-silent($0 --delete {+1})+reload(cliphist list | grep \"\[\[ binary\" | sed \"s/\t\[\[ binary data /\t/; s/ \]\]$//\")" \
      | cliphist decode | wl-copy >/dev/null 2>&1
    ;;
esac
