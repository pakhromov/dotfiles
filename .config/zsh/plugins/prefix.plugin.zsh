sudo-command-line() {
    [[ -z $BUFFER ]] && zle up-history
    if [[ $BUFFER == sudo\ * ]]; then
        LBUFFER="${LBUFFER#sudo }"
    else
        LBUFFER="sudo $LBUFFER"
    fi
}

man-command-line() {
    [[ -z $BUFFER ]] && zle up-history
    if [[ $BUFFER == man\ * ]]; then
        LBUFFER="${LBUFFER#man }"
    else
        LBUFFER="man $LBUFFER"
    fi
}

zle -N sudo-command-line
zle -N man-command-line
bindkey "^[s" sudo-command-line
bindkey -M vicmd '^[s' sudo-command-line
bindkey "^[m" man-command-line
bindkey -M vicmd '^[m' man-command-line
