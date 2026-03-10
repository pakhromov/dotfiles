#!/usr/bin/env bash
set -e

# Clear the terminal
clear

# Check if we have any files to send
if [ $# -eq 0 ]; then
    echo "No files to send"
    exit 1
fi

# If single file/folder, send directly
if [ $# -eq 1 ]; then
    localsend-go send "$1"
else
    # Multiple files: create temp folder, copy files, send folder
    tmpdir=$(mktemp -d /tmp/localsend.XXXXXX)
    cp -r "$@" "$tmpdir/"
    localsend-go send "$tmpdir"
fi
