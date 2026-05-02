#!/usr/bin/env bash

[[ $# -gt 0 ]] || { echo "Usage: fif <search term>" >&2; exit 1; }

mapfile -t files < <(
  rg --files-with-matches --no-messages "$1" |
    fzf --multi --preview "rg --ignore-case --pretty --context 10 '$1' {}"
)
[[ ${#files[@]} -gt 0 ]] && ${EDITOR:-vim} "${files[@]}"
