#!/bin/bash
# Repoint "EA Desktop\EA Desktop" at the newest installed EA app version.
#
# The EA app updates itself into a versioned folder and then tries to repoint
# that link. Under Wine the repoint fails when the link already exists, so the
# UI ends up running the new version while the background service still runs
# the old one - the app then hangs on "Connecting to the EA app".
#
# Run this after an EA app update, or whenever that hang appears.
# Safe to run at any time: it exits without touching anything if the link is
# already correct. Pass --prune to also delete unused version folders/zips.
set -u

PREFIX=/home/pavel/mnt/nvme0n1p4/ea-app
PROTON=/usr/share/steam/compatibilitytools.d/proton-wineland
UMU=/home/pavel/.local/share/lutris/runtime/umu/umu-run
EADIR="$PREFIX/drive_c/Program Files/Electronic Arts/EA Desktop"
LINK="$EADIR/EA Desktop?"   # Wine stores a reparse point as a dir ending in '?'

prune=0
[ "${1:-}" = "--prune" ] && prune=1

read_target() {
    getfattr --only-values -n user.WINEREPARSE "$LINK" 2>/dev/null |
        python3 -c 'import sys;b=sys.stdin.buffer.read();print(b[20:].decode("utf-16le").split("\x00")[0] if b else "")'
}

# Newest version dir that actually holds the app.
newest=$(for d in "$EADIR"/*/; do
             [ -f "$d/EA Desktop/EADesktop.exe" ] && basename "$d"
         done | sort -V | tail -1)

if [ -z "$newest" ]; then
    echo "error: no version folder with EA Desktop/EADesktop.exe under $EADIR" >&2
    exit 1
fi

current=$(read_target)
want="$newest\\EA Desktop"

echo "installed newest : $newest"
echo "link currently   : ${current:-<missing>}"

if [ "$current" = "$want" ]; then
    echo "link is already correct, nothing to do"
    [ $prune -eq 0 ] && exit 0
fi

if [ "$current" != "$want" ]; then
    if pgrep -x wineserver >/dev/null; then
        echo "stopping running prefix..."
        WINEPREFIX="$PREFIX" "$PROTON/files/bin/wineserver" -k
        sleep 3
    fi

    [ -e "$LINK" ] && rm -rf "$LINK"

    # mklink through a .bat: quoted paths with spaces do not survive being
    # passed as umu-run arguments.
    bat="$EADIR/.relink.bat"
    printf '@echo off\r\ncd /d "C:\\Program Files\\Electronic Arts\\EA Desktop"\r\nmklink /d "EA Desktop" "%s\\EA Desktop"\r\n' "$newest" > "$bat"
    ( cd "$EADIR" && WINEPREFIX="$PREFIX" PROTONPATH="$PROTON" GAMEID=umu-default \
        WINEDEBUG=-all PROTON_LOG=0 DISPLAY= "$UMU" cmd /c .relink.bat >/dev/null 2>&1 )
    rm -f "$bat"

    current=$(read_target)
    if [ "$current" = "$want" ]; then
        echo "link repointed to: $current"
    else
        echo "error: relink failed, link is now: ${current:-<missing>}" >&2
        exit 1
    fi
fi

if [ $prune -eq 1 ]; then
    for d in "$EADIR"/*/; do
        name=$(basename "$d")
        case "$name" in
            "$newest"|"EA Desktop?") continue ;;
        esac
        [ -f "$d/EA Desktop/EADesktop.exe" ] || continue
        echo "pruning old version: $name"
        rm -rf "$d"
    done
    for z in "$EADIR"/*.zip "$EADIR"/*.zip.sig; do
        [ -e "$z" ] || continue
        echo "pruning: $(basename "$z")"
        rm -f "$z"
    done
fi
