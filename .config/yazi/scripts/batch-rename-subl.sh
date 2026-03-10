#!/bin/bash
set -e

# Create temp file
tmp=$(mktemp)

# Write selected filenames to temp file
for file in "$@"; do
	basename "$file" >> "$tmp"
done

# Open with blocking sublime text
subl -w "$tmp"

# Read new names and rename files
i=1
for old in "$@"; do
	new=$(sed -n "${i}p" "$tmp")
	old_name=$(basename "$old")

	if [ -n "$new" ] && [ "$old_name" != "$new" ]; then
		dir=$(dirname "$old")
		mv "$old" "$dir/$new"
	fi
	i=$((i + 1))
done

rm "$tmp"
