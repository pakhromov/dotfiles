#!/usr/bin/env bash

# Imports
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."

# Battery settings
BATTERY_NAME="BAT0"
BATTERY_LOW=21
RESET="#[fg=brightwhite,bg=#15161e,nobold,noitalics,nounderscore,nodim]"

DISCHARGING_ICONS=("󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹")
CHARGING_ICONS=("󰢜" "󰂆" "󰂇" "󰂈" "󰢝" "󰂉" "󰢞" "󰂊" "󰂋" "󰂅")
NOT_CHARGING_ICON="󰚥"
NO_BATTERY_ICON="󱉝"

# Check if battery exists
battery_exists() {
  [[ -d "/sys/class/power_supply/$BATTERY_NAME" ]]
}

# Exit if no battery is found
if ! battery_exists; then
  exit 0
fi

# Get battery stats
get_battery_stats() {
  local battery_name=$1
  local battery_status=""
  local battery_percentage=""

  if [[ -f "/sys/class/power_supply/${battery_name}/status" && -f "/sys/class/power_supply/${battery_name}/capacity" ]]; then
    battery_status=$(<"/sys/class/power_supply/${battery_name}/status")
    battery_percentage=$(<"/sys/class/power_supply/${battery_name}/capacity")
  else
    battery_status="Unknown"
    battery_percentage="0"
  fi

  echo "$battery_status $battery_percentage"
}

# Fetch the battery status and percentage
read -r BATTERY_STATUS BATTERY_PERCENTAGE < <(get_battery_stats "$BATTERY_NAME")

# Ensure percentage is a number
if ! [[ $BATTERY_PERCENTAGE =~ ^[0-9]+$ ]]; then
  BATTERY_PERCENTAGE=0
fi

# Determine icon and color based on battery status and percentage
case "$BATTERY_STATUS" in
"Charging" | "Charged" | "charging" | "Charged")
  ICON="${CHARGING_ICONS[$((BATTERY_PERCENTAGE / 10))]}"
  ;;
"Discharging" | "discharging")
  ICON="${DISCHARGING_ICONS[$((BATTERY_PERCENTAGE / 10))]}"
  ;;
"Full" | "charged" | "full" | "AC")
  ICON="$NOT_CHARGING_ICON"
  ;;
*)
  ICON="$NO_BATTERY_ICON"
  ;;
esac

# Set color based on battery percentage
if [[ $BATTERY_PERCENTAGE -lt $BATTERY_LOW ]]; then
  color="#[fg=red,bg=default,bold]"
elif [[ $BATTERY_PERCENTAGE -ge 100 ]]; then
  color="#[fg=green,bg=default]"
else
  color="#[fg=yellow,bg=default]"
fi

# Print the battery status with some extra spaces for padding
echo " ${color}${ICON}${RESET}#[bg=default] ${BATTERY_PERCENTAGE}% "
