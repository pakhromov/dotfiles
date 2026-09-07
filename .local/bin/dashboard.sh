#!/bin/sh
while [ $# -gt 0 ]; do
    case "$1" in
        --class)
            CLASS="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

TABS=$(kitty @ --to unix:@mykitty ls 2>/dev/null | jq -r ".[] | select(.wm_class == \"$CLASS\") | .tabs[].id")
if [ -n "$TABS" ]; then
    echo "$TABS" | xargs -I{} kitty @ --to unix:@mykitty close-tab --match "id:{}"
else
    kitty --single-instance --listen-on=unix:@mykitty -o initial_window_width=768 -o initial_window_height=864 --class "$CLASS" "$@" &
    #kitty --single-instance --listen-on=unix:@mykitty --class "$CLASS" "$@" &
fi
