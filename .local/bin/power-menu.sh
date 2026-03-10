#!/bin/bash

options="󰐥 shutdown\n reboot\n󰍃 logout\n󰒲 suspend\n󰋊 hibernate\n󰌾 lock"

export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS
  --reverse --no-input --height=100% --margin '14,63'
  --highlight-line
  --border
  --pointer '>'
  --gutter ' '
  --scrollbar ''
  --separator ''
  --color fg:242,bg:233,hl:65,fg+:222,bg+:234,hl+:108
  --color info:108,prompt:110,spinner:150,pointer:167,marker:65"

choice=$(echo -e "$options" | fzf)

case "$choice" in
    "󰐥 shutdown")
        sudo systemctl poweroff
        ;;
    " reboot")
        sudo systemctl reboot
        ;;
    "󰍃 logout")
        sudo loginctl terminate-session ${XDG_SESSION_ID-}
        ;;
    "󰒲 suspend")
        sudo systemctl suspend
        ;;
    "󰋊 hibernate")
        sudo systemctl hibernate
        ;;
    "󰌾 lock")
        hyprlock
        ;;
esac
