#!/bin/bash

options="󰐥 shutdown\n reboot\n󰍃 logout\n UEFI\n󰒲 suspend\n󰋊 hibernate\n󰌾 lock"

choice=$(printf '%b\n' "$options" | rofi -dmenu -matching normal -p ' POWER MENU ')

case "$choice" in
    "󰐥 shutdown")
        systemctl poweroff
        ;;
    " reboot")
        systemctl reboot
        ;;
    "󰍃 logout")
        loginctl terminate-session ${XDG_SESSION_ID-}
        ;;
    " UEFI")
        systemctl reboot --firmware-setup
        ;;
    "󰒲 suspend")
        systemctl suspend
        ;;
    "󰋊 hibernate")
        systemctl hibernate
        ;;
    "󰌾 lock")
        hyprlock -q
        ;;
esac