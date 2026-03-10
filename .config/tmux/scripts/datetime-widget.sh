#!/usr/bin/env bash

source ~/.config/tmux/scripts/themes.sh

date_string="%a,%b-%d"
time_string="%H:%M"

separator1="  "
separator2=" "


echo "${RESET}#[fg=${THEME[foreground]}] ${separator2}${date_string}${separator1}${time_string} "
