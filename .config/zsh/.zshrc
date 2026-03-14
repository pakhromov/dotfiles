[[ "$PWD" == "$HOME" ]] && cd /tmp
stty -ixon < /dev/tty

setopt HIST_FIND_NO_DUPS   #everything else is handled by per-directory-history
setopt HIST_IGNORE_DUPS
setopt EXTENDED_GLOB
setopt NOMATCH
setopt NO_CASE_GLOB
setopt NO_CASE_MATCH
setopt PRINT_EXIT_VALUE
setopt GLOB_DOTS
zle_highlight+=(paste:none)

export HISTFILE=~/.zsh_history
export HISTSIZE=500000
export HISTORY_START_WITH_GLOBAL=true
export HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=true
export HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND=false
export HISTORY_SUBSTRING_SEARCH_FUZZY=false
export HISTORY_SUBSTRING_SEARCH_PREFIXED=true
export FZF_DEFAULT_OPTS="
  --exact --reverse --no-hscroll --height=80%
  --preview-window=right:50%:noinfo
  --highlight-line
  --scroll-off 7
  --info=inline-right
  --border
  --input-border
  --info-command='echo -e \"\$FZF_POS/\$FZF_MATCH_COUNT\"'
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
export FZF_CTRL_T_COMMAND="fd --type f --hidden --follow"
export FZF_CTRL_T_OPTS="--preview 'bat -n --color=always {}' --border-label ' FIND FILES '"
export FZF_ALT_C_COMMAND='{ zoxide query -l 2>/dev/null; fd --type d --hidden --follow . ~ 2>/dev/null; } | sed "s:/$::" | awk "!seen[\$0]++"'
export FZF_ALT_C_OPTS="--tiebreak=index --preview 'eza -1a --icons=always --color=always --group-directories-first {}' --border-label ' JUMP '"
export FZF_CTRL_R_OPTS="--no-sort --border-label ' HISTORY '"
export ZSH_AUTOSUGGEST_STRATEGY=(history completion)
export ZSH_AUTOSUGGEST_COMPLETION_IGNORE_CASE=true
export BAT_THEME="ansi"
export BAT_PAGER="ov --jump-target 50% --section-delimiter '^[^\s]' --section-header"
#export BAT_PAGER="/home/pavel/.config/kitty/pager.sh"
export MANPAGER="sh -c 'col -bx | bat -l man --wrap=never --color=always --style=plain --paging=always'"
export PYTHON_AUTO_VRUN=true
export MAGIC_ENTER_COMMAND='cd .'
export ZPWR_EXPAND_BLACKLIST=(ls)
export ZPWR_EXPAND=true
export ZPWR_EXPAND_SECOND_POSITION=true
export CHPWD_LS_BLACKLIST=("$HOME" "/tmp")

fpath=(~/.config/zsh/completions $fpath)
autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
_comp_options+=(globdots)
autoload -U colors && colors

export STARSHIP_CONFIG=/home/pavel/.config/zsh/themes/starship.toml
eval "$(starship init zsh)"
#eval "$(oh-my-posh init zsh --config ~/.config/zsh/themes/ohmyposh_themes/night-owl.omp.json)"

source ~/.config/zsh/plugins/auto-venv/auto-venv.zsh
source ~/.config/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh
source ~/.config/zsh/plugins/fzf-tab-completion/fzf-zsh-completion.sh
source <(fzf --zsh)
eval "$(zoxide init zsh)"
source ~/.config/zsh/plugins/zsh-expand/zsh-expand.plugin.zsh
source ~/.config/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh #make PR to fix upstream
source ~/.config/zsh/plugins/zsh-history-substring-search.plugin.zsh
source ~/.config/zsh/plugins/per-directory-history.plugin.zsh
source ~/.config/zsh/plugins/dirhistory.plugin.zsh
source ~/.config/zsh/plugins/magic-enter.plugin.zsh
source ~/.config/zsh/plugins/prefix.plugin.zsh
source ~/.config/zsh/plugins/man-pages.plugin.zsh

subl() {
  for arg in "$@"; do
    local expanded_path="${arg:A}"
    if [[ ! -e "$expanded_path" ]]; then
      mkdir -p "${expanded_path:h}"
      touch "$expanded_path"
    fi
  done
  command subl "$@"
}

function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  local session_file="$HOME/.local/state/yazi/session.json"
  local target_dir="${1:-$PWD}"

  # Resolve to absolute path
  target_dir="${target_dir:A}"

  if [[ -f "$session_file" ]] && command -v jq &>/dev/null; then
    local tab_idx
    tab_idx=$(jq -r --arg cwd "$target_dir" '.tabs[] | select(.cwd == $cwd) | .idx' "$session_file" 2>/dev/null | head -1)

    if [[ -n "$tab_idx" ]]; then
      # Directory exists in a tab, set it as active
      jq --argjson idx "$tab_idx" '.active_idx = $idx' "$session_file" > "$session_file.tmp" \
        && mv "$session_file.tmp" "$session_file"
    else
      # Directory doesn't exist, add new tab
      local max_idx
      max_idx=$(jq '[.tabs[].idx] | max // 0' "$session_file" 2>/dev/null)
      local new_idx=$((max_idx + 1))
      jq --arg cwd "$target_dir" --argjson idx "$new_idx" \
        '.tabs += [{"idx": $idx, "cwd": $cwd}] | .active_idx = $idx' "$session_file" > "$session_file.tmp" \
        && mv "$session_file.tmp" "$session_file"
    fi
  fi

  yazi --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp"
  [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}

yay() {
  command yay "$@"
  rehash
}

yzf() {
  command yzf "$@"
  rehash
}


fancy-alt-z () {
  if [[ $#BUFFER -eq 0 ]]; then
    BUFFER="fg"
    zle accept-line -w
  else
    zle push-input -w
    zle clear-screen -w
  fi
}
zle -N fancy-alt-z
bindkey '^[z' fancy-alt-z

alt-tab-fzf-widget() {
  local cmd="fd --type d --hidden --follow"
  local opts='--preview "eza -1a --icons=always --color=always --group-directories-first {}"'
  local result="$(eval "$cmd" | FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS $opts" fzf)"
  [[ -n "$result" ]] && LBUFFER+="$result"
  zle reset-prompt
}
zle -N alt-tab-fzf-widget
bindkey '^[^I' alt-tab-fzf-widget

#for tab on empty prompt and fallback to --help completions
_fzf_complete_commands() {
    if [[ -z "$BUFFER" ]]; then
        local selected
        selected=$(print -l ${(ok)commands} ${(ok)aliases} ${(ok)functions} ${(ok)builtins} | fzf)
        if [[ -n "$selected" ]]; then
            LBUFFER="$selected "
        fi
        zle reset-prompt
    else
        local orig_buffer="$BUFFER"
        local current_word="${${(z)LBUFFER}[-1]}"

        zle fzf_completion

        # Fallback to --help if no completions and completing an option
        if [[ "$BUFFER" == "$orig_buffer" && "$current_word" == -* ]]; then
            local -a words
            words=(${(z)BUFFER})
            local cmd="${words[1]}"
            [[ -z "$cmd" ]] && return

            local options
            options=$(command "$cmd" --help 2>&1 | grep -E '^[[:space:]]*-')
            [[ -z "$options" ]] && options=$(command "$cmd" -h 2>&1 | grep -E '^[[:space:]]*-')
            [[ -z "$options" ]] && return

            local selected
            selected=$(echo "$options" | fzf)
            [[ -z "$selected" ]] && { zle reset-prompt; return; }

            # Extract option, strip leading - since one is already typed
            local opt
            opt=$(echo "$selected" | sed 's/^[[:space:]]*//' | cut -d' ' -f1 | cut -d',' -f1)
            opt="${opt#-}"

            [[ -n "$opt" ]] && LBUFFER+="$opt"
            zle reset-prompt
        fi
    fi
}
zle -N _fzf_complete_commands

chpwd-ls() {
    (( ZSH_SUBSHELL )) && return
    for dir in "${CHPWD_LS_BLACKLIST[@]}"; do
        [[ "$PWD" == "$dir" ]] && return
    done
    eza -1a --icons=always --group-directories-first --hyperlink
}
add-zsh-hook -Uz chpwd chpwd-ls

_newline_before_prompt() { (( _PROMPT_COUNT++ > 0 )) && print; }
add-zsh-hook precmd _newline_before_prompt

clear-scrollback() { printf '\x1b[2J\x1b[3J\x1b[H'; _PROMPT_COUNT=0; zle reset-prompt; _PROMPT_COUNT=1; }
zle -N clear-scrollback
bindkey '^L' clear-scrollback

bindkey '^I' _fzf_complete_commands
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey '^H' backward-kill-word
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^Z' undo
bindkey '^[[122;6u' redo
bindkey '^[[127;6u' kill-whole-line
paste-from-clipboard() { LBUFFER+="$(wl-paste -n)"; }
zle -N paste-from-clipboard
bindkey '^V' paste-from-clipboard


unalias -a
alias clear="printf '\x1b[2J\x1b[3J\x1b[H'; _PROMPT_COUNT=0"
alias f="fastfetch"
alias r="sudo pacman -Rns"
alias i="yay -S"
alias l="launch"
alias rr="yzf -x"
alias ro="yzf -o"
alias ls="eza -1a --icons=always --group-directories-first --hyperlink"
alias -g dn='2>/dev/null'
alias dotfiles='git --git-dir=$HOME/.dotfiles-git --work-tree=$HOME'
