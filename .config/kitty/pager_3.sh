#!/bin/bash
# Strip ALL escape sequences (ANSI colors, OSC, shell integration markers, etc.)
sed -e 's/\x1b\[[0-9;:?]*[a-zA-Z]//g' \
    -e 's/\x1b\][^\x07\x1b]*\(\x07\|\x1b\\\)//g' \
    -e 's/\x1b\][^\]*\\//g' \
    -e 's/\x1b[()][AB012]//g' \
    | subl -
