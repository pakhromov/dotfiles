#!/usr/bin/env bash

# Imports
source ~/.config/tmux/scripts/themes.sh

# Auto-determine interface
function find_interface() {
  local interface
  interface=$(awk '$2 == 00000000 {print $1}' /proc/net/route | head -n1)
  echo "$interface"
}

# Detect interface IPv4 and status
function interface_ipv4() {
  local interface="$1"
  local ipv4_addr
  local status="up" # Default assumption

  # Use 'ip' command to check for IPv4 address
  if command -v ip >/dev/null 2>&1; then
    ipv4_addr=$(ip addr show dev "$interface" 2>/dev/null | grep "inet\b" | awk '{sub("/.*", "", $2); print $2}')
    [[ -z $ipv4_addr ]] && status="down"
  # Use 'ifconfig' command to check for IPv4 address
  elif command -v ifconfig >/dev/null 2>&1; then
    ipv4_addr=$(ifconfig "$interface" 2>/dev/null | grep "inet\b" | awk '{print $2}')
    [[ -z $ipv4_addr ]] && status="down"
  # Fallback to operstate
  elif [[ $(cat "/sys/class/net/$interface/operstate" 2>/dev/null) != "up" ]]; then
    status="down"
  fi

  echo "$ipv4_addr"
  [[ $status == "up" ]] && return 0 || return 1
}

# Get WiFi SSID
function get_wifi_ssid() {
  local interface="$1"
  local ssid=""

  if command -v iwctl >/dev/null 2>&1; then
    ssid=$(iwctl station "$interface" show 2>/dev/null | grep "Connected network" | awk '{print $3}')
  elif command -v iwgetid >/dev/null 2>&1; then
    ssid=$(iwgetid -r "$interface" 2>/dev/null)
  fi

  echo "$ssid"
}

# Auto-detect network interface, fallback to wlan0 if no active connection
INTERFACE=$(find_interface)
if [[ -z $INTERFACE ]]; then
  # No active connection, check if wlan0 exists
  if [[ -d /sys/class/net/wlan0 ]]; then
    INTERFACE="wlan0"
  else
    exit 1
  fi
fi

# Icons
declare -A NET_ICONS
NET_ICONS[wifi_up]="#[fg=${THEME[foreground]}]\U000f05a9"  # nf-md-wifi
NET_ICONS[wifi_down]="#[fg=${THEME[red]}]\U000f05aa"       # nf-md-wifi_off
NET_ICONS[wired_up]="#[fg=${THEME[foreground]}]\U000f0318" # nf-md-lan_connect
NET_ICONS[wired_down]="#[fg=${THEME[red]}]\U000f0319"      # nf-md-lan_disconnect

# Interface icon
if [[ -d /sys/class/net/${INTERFACE}/wireless ]]; then
  IFACE_TYPE="wifi"
else
  IFACE_TYPE="wired"
fi

# Detect interface IPv4 and state
if IPV4_ADDR=$(interface_ipv4 "$INTERFACE"); then
  IFACE_STATUS="up"
else
  IFACE_STATUS="down"
fi

NETWORK_ICON=${NET_ICONS[${IFACE_TYPE}_${IFACE_STATUS}]}

# Determine display name
DISPLAY_NAME="$INTERFACE"
if [[ $IFACE_TYPE == "wifi" ]]; then
  if [[ $IFACE_STATUS == "up" ]]; then
    # Connected to WiFi - show SSID
    WIFI_SSID=$(get_wifi_ssid "$INTERFACE")
    if [[ -n $WIFI_SSID ]]; then
      DISPLAY_NAME="$WIFI_SSID"
    fi
  else
    # Not connected - show wlan0 in red
    DISPLAY_NAME="#[fg=${THEME[red]}]wlan0"
  fi
fi

OUTPUT="${RESET} $NETWORK_ICON #[dim]$DISPLAY_NAME "

echo -e "$OUTPUT"
