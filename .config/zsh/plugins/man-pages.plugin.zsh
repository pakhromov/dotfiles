# Requires colors autoload.
# See termcap(5).

# Set up once, and then reuse. This way it supports user overrides after the
# plugin is loaded.
typeset -AHg less_termcap

# bold & blinking mode
less_termcap[mb]="${fg_bold[red]}"
less_termcap[md]="${fg_bold[red]}"
less_termcap[me]="${reset_color}"
# standout mode
less_termcap[so]="${fg_bold[yellow]}${bg[blue]}"
less_termcap[se]="${reset_color}"
# underlining
less_termcap[us]="${fg_bold[green]}"
less_termcap[ue]="${reset_color}"

# Handle $0 according to the standard:
# https://zdharma-continuum.github.io/Zsh-100-Commits-Club/Zsh-Plugin-Standard.html
0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
0="${${(M)0:#/*}:-$PWD/$0}"

# Absolute path to this file's directory.
typeset -g __colored_man_pages_dir="${0:A:h}"

function colored() {
  MANROFFOPT="-c" command "$@"
}

# Colorize man and dman/debman (from debian-goodies)
function man \
  dman \
  debman {
  if [[ $0 == "man" && $# -eq 0 ]]; then
    # No arguments - show fzf with all man pages, loop until cancelled
    local preview_cmd='echo {} | sed "s/\([^ ]*\) (\([^)]*\)).*/\2 \1/" | xargs man 2>/dev/null | col -bx | bat --language=man --plain --color always --theme=ansi'
    while true; do
      local selected=$(apropos . | fzf --ansi --preview="$preview_cmd" --bind 'enter:execute(MANROFFOPT="-c" man $(echo {} | sed "s/\([^ ]*\) (\([^)]*\)).*/\2 \1/"))')
      [[ -z $selected ]] && break
    done
  elif [[ $0 == "man" && $# -eq 1 ]]; then
    # One argument - check if there are multiple matches
    local matches=$(apropos "^$1" 2>/dev/null)
    local count=$(echo "$matches" | grep -c .)

    if [[ $count -eq 0 ]]; then
      # No matches, try regular man
      colored $0 "$@"
    elif [[ $count -eq 1 ]]; then
      # Exactly one match, show it directly (no loop, exit after viewing)
      colored $0 "$@"
    else
      # Multiple matches, show fzf with loop
      local preview_cmd='echo {} | sed "s/\([^ ]*\) (\([^)]*\)).*/\2 \1/" | xargs man 2>/dev/null | col -bx | bat --language=man --plain --color always --theme=ansi'
      while true; do
        local selected=$(echo "$matches" | fzf --ansi --preview="$preview_cmd" --bind 'enter:execute(MANROFFOPT="-c" man $(echo {} | sed "s/\([^ ]*\) (\([^)]*\)).*/\2 \1/"))')
        [[ -z $selected ]] && break
      done
    fi
  else
    # Multiple arguments or other commands, use normal behavior
    colored $0 "$@"
  fi
}
