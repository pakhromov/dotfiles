#!/bin/bash
# Strip ALL escape sequences for clean text in Sublime
perl -pe '
    s/\e\[[0-9;:?]*[a-zA-Z]//g;      # CSI sequences (colors, cursor, etc.)
    s/\e\][^\a\e]*(?:\a|\e\\)//g;    # OSC sequences (shell integration)
    s/\e[()][AB012]//g;               # Character set sequences
    s/\e.//g;                         # Any remaining escapes
' | subl -
