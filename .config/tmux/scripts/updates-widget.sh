#!/usr/bin/env bash

source ~/.config/tmux/scripts/themes.sh

CACHE_FILE="${XDG_RUNTIME_DIR:-/tmp}/tmux_updates_cache"
CACHE_DURATION=1800

# Get number of available updates
get_updates_count() {
  local count=0

  if command -v paru >/dev/null 2>&1; then
    count=$(paru -Qu 2>/dev/null | wc -l)
  fi

  echo "$count"
}

# Check if cache is valid
if [[ -f "$CACHE_FILE" ]]; then
  CACHE_AGE=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
  if [[ $CACHE_AGE -lt $CACHE_DURATION ]]; then
    # Use cached value
    UPDATES=$(cat "$CACHE_FILE")
  else
    # Cache expired, update it
    UPDATES=$(get_updates_count)
    echo "$UPDATES" > "$CACHE_FILE"
  fi
else
  # No cache, create it
  UPDATES=$(get_updates_count)
  echo "$UPDATES" > "$CACHE_FILE"
fi

# If no updates, don't display anything
if [[ $UPDATES -eq 0 ]]; then
  exit 0
fi

# Arch Linux logo icon (nf-md-arch)
ICON="#[fg=${THEME[foreground]}]󰣇"

echo "${RESET} ${ICON} #[dim]${UPDATES} "
