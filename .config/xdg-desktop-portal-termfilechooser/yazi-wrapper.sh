#!/usr/bin/env sh
# This wrapper script is invoked by xdg-desktop-portal-termfilechooser.
#
# For more information about input/output arguments read `xdg-desktop-portal-termfilechooser(5)`

set -e

if [ "$6" -ge 4 ]; then
    set -x
fi

multiple="$1"
directory="$2"
save="$3"
path="$4"
out="$5"

cmd="yazi"
termcmd="${TERMCMD:-kitty --title 'termfilechooser'}"

if [ "$save" = "1" ]; then
    # save a file - create suggested file in /tmp/termfilechooser/
    save_dir="/tmp/termfilechooser"
    mkdir -p "$save_dir"
    filename=$(basename "$path")
    if [ -n "$filename" ] && [ "$filename" != "." ]; then
        touch "$save_dir/$filename"
    fi

    # Open /tmp/termfilechooser/ in a new yazi tab via session.json
    session_file="$HOME/.local/state/yazi/session.json"
    if [ -f "$session_file" ] && command -v jq >/dev/null 2>&1; then
        tab_idx=$(jq -r --arg cwd "$save_dir" '.tabs[] | select(.cwd == $cwd) | .idx' "$session_file" 2>/dev/null | head -1)

        if [ -n "$tab_idx" ]; then
            jq --argjson idx "$tab_idx" '.active_idx = $idx' "$session_file" > "$session_file.tmp" \
                && mv "$session_file.tmp" "$session_file"
        else
            max_idx=$(jq '[.tabs[].idx] | max // 0' "$session_file" 2>/dev/null)
            new_idx=$((max_idx + 1))
            jq --arg cwd "$save_dir" --argjson idx "$new_idx" \
                '.tabs += [{"idx": $idx, "cwd": $cwd}] | .active_idx = $idx' "$session_file" > "$session_file.tmp" \
                && mv "$session_file.tmp" "$session_file"
        fi
    fi

    set -- --chooser-file="$out"
elif [ "$directory" = "1" ]; then
    # upload files from a directory
    set -- --chooser-file="$out" --cwd-file="$out"".1" "$path"
elif [ "$multiple" = "1" ]; then
    # upload multiple files
    set -- --chooser-file="$out" "$path"
else
    # upload only 1 file
    set -- --chooser-file="$out" "$path"
fi

command="$termcmd $cmd"
for arg in "$@"; do
    # escape double quotes
    escaped=$(printf "%s" "$arg" | sed 's/"/\\"/g')
    # escape special
    command="$command \"$escaped\""
done

sh -c "$command"

if [ "$directory" = "1" ]; then
    if [ ! -s "$out" ] && [ -s "$out"".1" ]; then
        cat "$out"".1" > "$out"
        rm "$out"".1"
    else
        rm "$out"".1"
    fi
fi
