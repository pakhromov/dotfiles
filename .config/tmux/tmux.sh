#!/usr/bin/env bash

#+--- General Settings ---+
tmux set -g mouse on
tmux set -g default-terminal "tmux-256color"
tmux set -ga terminal-overrides ",*:RGB"
tmux set -g base-index 1
tmux set -g pane-border-lines double
tmux set -g renumber-windows on
tmux set -g status-position top
tmux set -g history-limit 50000
tmux set -g status-interval 1
tmux setw -g mode-keys vi
tmux setw -g aggressive-resize on
tmux set -g automatic-rename on
tmux set -g allow-rename off
tmux set -g set-titles on
tmux set -g exit-unattached on
tmux set -g default-shell /usr/bin/zsh

#+--- Key Bindings ---+
tmux set -g prefix C-Space
#unbind-key -a
tmux bind -n C-S-Left  previous-window
tmux bind -n C-S-Right next-window
tmux bind-key -n DoubleClick1StatusDefault new-window
tmux bind-key -n MouseDown2Status kill-window -t =
tmux bind -n C-f copy-mode \; command-prompt -p "search:" "send-keys -X search-backward '%%'"
tmux bind-key -T copy-mode-vi Up send-keys -X search-again
tmux bind-key -T copy-mode-vi Down send-keys -X search-reverse
tmux bind-key -T copy-mode Up send-keys -X search-again
tmux bind-key -T copy-mode Down send-keys -X search-reverse
tmux bind-key -T copy-mode-vi Escape send-keys -X cancel
tmux bind-key -T copy-mode Escape send-keys -X cancel

#+--- Theme ---+
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_PATH="$CURRENT_DIR/scripts"

source $SCRIPTS_PATH/themes.sh

tmux set -g status-left-length 80
tmux set -g status-right-length 150

RESET="#[fg=${THEME[foreground]},bg=${THEME[background]},nobold,noitalics,nounderscore,nodim]"

# Highlight colors
tmux set -g mode-style "fg=${THEME[bgreen]},bg=${THEME[bblack]}"

tmux set -g message-style "bg=${THEME[blue]},fg=${THEME[background]}"
tmux set -g message-command-style "fg=${THEME[white]},bg=${THEME[black]}"

tmux set -g pane-border-style "fg=${THEME[bblack]}"
tmux set -g pane-active-border-style "fg=${THEME[blue]}"
tmux set -g pane-border-status off

tmux set -g status-style bg="${THEME[background]}"

TMUX_VARS="$(tmux show -g)"

window_number="#(f='🯰🯱🯲🯳🯴🯵🯶🯷🯸🯹'; id=#I; for ((i=0;i<\${#id};i++)); do echo -n \"\${f:\${id:i:1}:1} \"; done)"
custom_pane="#(f='󰎢󰎥󰎨󰎫󰎲󰎯󰎴󰎷󰎺󰎽'; id=#I; for ((i=0;i<\${#id};i++)); do echo -n \"\${f:\${id:i:1}:1} \"; done)"
#pane_count="#(c=#{window_panes}; if [ \$c -eq 2 ]; then echo 󰎨 ; elif [ \$c -eq 3 ]; then echo 󰎫 ; elif [ \$c -eq 4 ]; then echo 󰎲 ; elif [ \$c -eq 5 ]; then echo 󰎯 ; elif [ \$c -eq 6 ]; then echo 󰎴 ; elif [ \$c -eq 7 ]; then echo 󰎷 ; elif [ \$c -eq 8 ]; then echo 󰎺 ; elif [ \$c -eq 9 ]; then echo 󰎽 ; else echo \$c; fi)"
#🯰🯱🯲🯳🯴🯵🯶🯷🯸🯹
#󰎣󰎦󰎩󰎬󰎮󰎰󰎵󰎸󰎻󰎾
#󰎢󰎥󰎨󰎫󰎲󰎯󰎴󰎷󰎺󰎽
rarrow=''
larrow=''
active_terminal_icon=''
terminal_icon=''
ssh='󰣀'
previous_window='󰁯'
custom_pane=""
zoom_number=""
updates="#($SCRIPTS_PATH/updates-widget.sh)"
keyboard_layout="#($SCRIPTS_PATH/keyboard-widget.sh)"
netspeed="#($SCRIPTS_PATH/netspeed.sh)"
date_and_time="$($SCRIPTS_PATH/datetime-widget.sh)"
battery_status="#($SCRIPTS_PATH/battery-widget.sh)"


tmux set -g status-left "#[fg=${THEME[bblack]},bg=${THEME[blue]},bold] #{?client_prefix,󰠠,} #S #[fg=${THEME[blue]},bg=${THEME[background]}]$rarrow"

tmux set -g window-status-current-format "$RESET#[fg=${THEME[bblack]}]$larrow#[fg=${THEME[green]},bg=${THEME[bblack]}] $terminal_icon #[fg=${THEME[foreground]},bold,nodim]$window_number#W#[nobold]#{?window_zoomed_flag, $zoom_number, $custom_pane}#{?window_last_flag,,}#[fg=${THEME[bblack]},bg=default]$rarrow"
# Unfocused
tmux set -g window-status-format "$RESET#[fg=#0D1117]$larrow#[fg=${THEME[foreground]}] $terminal_icon ${RESET}$window_number#W#[nobold,dim]#{?window_zoomed_flag, $zoom_number, $custom_pane}#[fg=${THEME[yellow]}]#{?window_last_flag,󰁯 ,#[fg=${THEME[foreground]},bg=default] $rarrow}"




#+--- Bars RIGHT ---+
tmux set -g status-right "$updates$keyboard_layout$netspeed$date_and_time"
tmux set -g window-status-separator ""



