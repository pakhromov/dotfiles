#!/usr/bin/env bash

red=$(tput setaf 1)
green=$(tput setaf 2)
blue=$(tput setaf 4)
reset=$(tput sgr0)
errs=()

die() { printf '%s\n' "$red$1$reset" >&2; exit 1; }

for c in fzf git; do
  command -v "$c" &>/dev/null || die "$c not found"
done

export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS
  --ansi --multi --cycle --no-sort --exact --reverse --no-hscroll --height=100%
  --preview-window=right:50%:noinfo:wrap
  --highlight-line
  --scroll-off 7
  --info=inline-right
  --border
  --input-border
  --info-command='echo -e \"\$FZF_POS/\$FZF_MATCH_COUNT(\$FZF_SELECT_COUNT)\"'
  --prompt '> '
  --pointer '>'
  --gutter '┃'
  --marker '┃'
  --ellipsis '  '
  --scrollbar ''
  --separator ''
  --color fg:242,bg:233,hl:65,fg+:222,bg+:234,hl+:108
  --color info:108,prompt:110,spinner:150,pointer:167,marker:65"

_k=$'\033[38;2;160;160;160m'
_a=$'\033[36m'
_r=$'\033[m'
_kb=" ${_k}TAB${_a} select   ${_k}CTRL+A${_a} all   ${_k}CTRL+RIGHT${_a} url   ${_k}ENTER${_a} pull${_r} "

mapfile -t all_repos < <(find . -name '.git' -printf '%h\n' 2>/dev/null)

(( ${#all_repos[@]} > 0 )) || die "no git repos found"

# Filter to repos that are behind upstream (no fetch, uses cached info)
outdated=()
for d in "${all_repos[@]}"; do
  behind=$(git -C "$d" rev-list HEAD..@{u} --count 2>/dev/null)
  [[ "$behind" -gt 0 ]] && outdated+=("$d")
done

(( ${#outdated[@]} > 0 )) || { printf "all repos are up to date\n"; exit 0; }

mapfile -t repos < <(printf '%s\n' "${outdated[@]}" | fzf --border-label ' GIT PULL ' \
  --preview-label "$_kb" --preview-label-pos 'bottom' \
  --preview "git -C {} rev-list HEAD..@{u} | while read h; do git -C {} log --color=always --oneline -1 \$h; git -C {} diff --color=always \$h^ \$h -- '*.md' 2>/dev/null; done" \
  --bind "ctrl-a:toggle-all" \
  --bind "load:select-all" \
  --bind "ctrl-right:execute-silent(url=\$(git -C {} config --get remote.origin.url); url=\${url%.git}; url=\${url/#git@github.com:/https://github.com/}; [ -n \"\$url\" ] && xdg-open \"\$url\")")

(( ${#repos[@]} > 0 )) || exit

for d in "${repos[@]}"; do
  name="${d##*/}"
  printf '%s\n' "${blue}:: pulling $name${reset}"
  if ! git -C "$d" pull; then
    errs+=( "$name" )
  fi
done

if (( ${#errs[@]} > 0 )); then
  printf '%s\n' "${red}failed to update: ${errs[*]}${reset}"
fi
printf '%s\n' "${green}updated ${#repos[@]} repos${reset}"
read -rsn1 -p "Press enter or esc to exit..."
