#!/bin/sh
TABS=$(kitty @ --to unix:@mykitty ls 2>/dev/null | jq -r '.[] | select(.wm_class == "float-time") | .tabs[].id')
if [ -n "$TABS" ]; then
    echo "$TABS" | xargs -I{} kitty @ --to unix:@mykitty close-tab --match "id:{}"
else
    kitty --single-instance --listen-on=unix:@mykitty --class float-time --session ~/.config/kitty/session.conf &
fi
