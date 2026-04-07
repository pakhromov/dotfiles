#!/bin/bash

export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS
  --preview-window=right:60%
  --no-sort --exact --reverse --no-hscroll --height=100%
  --highlight-line
  --scroll-off 7
  --info=inline-right
  --border
  --input-border
  --border-label ' FONT PREVIEW '
  --info-command='echo -e \"\$FZF_POS/\$FZF_MATCH_COUNT\"'
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

TEXT="${FONT_PREVIEW_TEXT:-ABCDEF abcdef\n0123456789\n               \n     󰡨    󰣠   󱄅 \n!?@#$%^&*-=_+.,;: <>()[]\n== <= >= != -> =>}"
BG="${FONT_PREVIEW_BG:-#121212}"
FG="${FONT_PREVIEW_FG:-#A0A0A0}"
SIZE="${FONT_PREVIEW_SIZE:-48}"

case "$1" in
  --preview)
    magick -size 1000x800 -background "$BG" -fill "$FG" -font "$2" \
      -pointsize "$SIZE" -gravity center label:"$(echo -e "$TEXT")" \
      /tmp/font-preview.png 2>/dev/null
    kitty +kitten icat --clear --transfer-mode=memory --unicode-placeholder --stdin=no \
      --place="${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0" /tmp/font-preview.png 2>/dev/null | sed '$d' | sed $'$s/$/\e[m/'
    ;;
  *)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t|--text) TEXT="$2"; shift 2 ;;
        -bg|--bg-color) BG="$2"; shift 2 ;;
        -fg|--fg-color) FG="$2"; shift 2 ;;
        -s|--size) SIZE="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    export FONT_PREVIEW_TEXT="$TEXT" FONT_PREVIEW_BG="$BG" FONT_PREVIEW_FG="$FG" FONT_PREVIEW_SIZE="$SIZE"
    sel=$(magick -list font | awk '/Font:/{print $2}' | sort -u |
      awk -F- '
      {
        prefix = $1; lower = tolower($0)
        if (lower ~ /regular/)                                              score = 0
        else if (lower ~ /bold|italic|light|thin|medium|black|heavy|oblique|semibold|condensed/) score = 2
        else                                                                score = 1
        if (!(prefix in best) || score < best_score[prefix] ||
            (score == best_score[prefix] && length($0) < length(best[prefix]))) {
          best[prefix] = $0; best_score[prefix] = score
        }
      }
      END { for (p in best) print best[p] }' | sort |
      fzf --multi --preview "$0 --preview {}")
    [ -n "$sel" ] && while IFS= read -r font; do
      file=$(magick -list font | awk -v f="$font" '/Font:/{found=($2==f)} /glyphs:/ && found{print $2; exit}')
      fc-query --format="%{family[0]}\n" "$file" 2>/dev/null | head -1
    done <<< "$sel"
    ;;
esac
