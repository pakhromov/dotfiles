#!/bin/bash

_footer_text=$'\033[38;2;160;160;160mTAB\033[36m select   \033[38;2;160;160;160mCTRL+DEL\033[36m delete   \033[38;2;160;160;160mENTER\033[36m copy   \033[38;2;160;160;160mESC\033[36m cancel\033[m'
_footer_plain='TAB select   CTRL+DEL delete   ENTER copy   ESC cancel'
_pad=$(( $(tput cols) - ${#_footer_plain} - 7 ))
(( _pad > 0 )) && printf -v _footer '%*s%s' "$_pad" '' "$_footer_text" || _footer=$_footer_text

export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS
  -d '\t' --with-nth 2
  --no-sort --multi --exact --reverse --no-hscroll --height=100%
  --highlight-line
  --scroll-off 7
  --info=inline-right
  --border
  --input-border
  --border-label ' CLIPBOARD HISTORY '
  --info-command='echo -e \"\$FZF_POS/\$FZF_MATCH_COUNT(\$FZF_SELECT_COUNT)\"'
  --footer \"$_footer\"
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
    cclip list id,mime,preview | awk -F'\t' '$2 ~ /^text\// {print $1"\t"$3}'
    ;;
  --delete)
    shift
    for id in "$@"; do cclip delete "$id"; done
    ;;
  -t)
    flag=/tmp/.cclip_ok
    rm -f "$flag"
    $2 "$0"
    [ -f "$flag" ] && { rm -f "$flag"; sleep 0.1; wtype -M ctrl -M shift -k v; sleep 0.1; pkill -x wl-copy 2>/dev/null || true; }
    ;;
  *)
    sel=$($0 --list | fzf \
      --bind "ctrl-delete:execute-silent($0 --delete {+1})+reload($0 --list)")
    if [ -n "$sel" ]; then
      combined=""
      while IFS=$'\t' read -r id _; do
        entry=$(cclip get "$id" 2>/dev/null)
        if [ -z "$combined" ]; then
          combined="$entry"
        else
          combined="$combined
$entry"
        fi
      done <<< "$sel"
      wl-copy -- "$combined" >/dev/null 2>&1 && touch /tmp/.cclip_ok
    fi
    ;;
esac
