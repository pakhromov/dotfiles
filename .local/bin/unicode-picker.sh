#!/bin/bash

_footer_text=$'\033[38;2;160;160;160mTAB\033[36m select   \033[38;2;160;160;160mENTER\033[36m copy\033[m'
_footer_plain='TAB select   ENTER copy'
_pad=$(( $(tput cols) - ${#_footer_plain} - 7 ))
(( _pad > 0 )) && printf -v _footer '%*s%s' "$_pad" '' "$_footer_text" || _footer=$_footer_text

export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS
  --no-sort --multi --exact --reverse --no-hscroll --height=100%
  --highlight-line
  --scroll-off 7
  --info=inline-right
  --info-command='echo -e \"\$FZF_POS/\$FZF_MATCH_COUNT(\$FZF_SELECT_COUNT)\"'
  --border
  --input-border
  --border-label ' UNICODE PICKER '
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

if [[ "$1" == "-t" ]]; then
  flag=/tmp/.cclip_ok
  rm -f "$flag"
  $2 "$0"
  if [ -f "$flag" ]; then
    rm -f "$flag"
    sleep 0.1
    wtype -M ctrl -M shift -k v
    sleep 0.3
    pkill -x wl-copy 2>/dev/null || true
  fi
else
  sel=$(fzf < ~/.local/bin/icons/unicode.txt | awk '{print $1}' | tr -d "\n")
  if [ -n "$sel" ]; then
    setsid wl-copy -- "$sel" >/dev/null 2>&1 &
    touch /tmp/.cclip_ok
  fi
fi
