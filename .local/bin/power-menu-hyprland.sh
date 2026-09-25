#!/bin/bash

options="󰐥 shutdown\n reboot\n󰍃 logout\n UEFI\n cleanup\n󰒲 suspend\n󰋊 hibernate\n lock"

choice=$(printf '%b\n' "$options" | rofi -dmenu -matching normal -p ' POWER MENU ')

case "$choice" in
    "󰐥 shutdown")
        hyprshutdown -t 'Shutting down...' --post-cmd 'systemctl poweroff'
        ;;
    " reboot")
        hyprshutdown -t 'Rebooting...' --post-cmd 'systemctl reboot'
        ;;
    "󰍃 logout")
        hyprshutdown -t 'Logging out...'
        ;;
    " UEFI")
        hyprshutdown -t 'Rebooting to UEFI...' --post-cmd 'systemctl reboot --firmware-setup'
        ;;
    " cleanup")
        hyprshutdown --no-exit -t 'Closing everything...'
        ;;
    "󰒲 suspend")
        systemctl suspend
        ;;
    "󰋊 hibernate")
        systemctl hibernate
        ;;
    " lock")
        hyprlock -q
        ;;
esac