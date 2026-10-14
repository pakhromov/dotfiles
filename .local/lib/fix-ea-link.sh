#!/bin/bash
# Repair the EA app's "EA Desktop\EA Desktop" link inside a Wine/Proton prefix.
#
# The EA app installs itself as a versioned folder plus a Windows symlink
#   Electronic Arts/EA Desktop/EA Desktop  ->  <version>/EA Desktop
# and on update it stages a new versioned folder and repoints that link.
# Under Wine the repoint fails whenever the name already exists ("File already
# exists", error 183), so the app keeps running the old files - or, once the
# old folder is gone, hangs on "Connecting to the EA app" because the UI and
# the background service end up on different versions.
#
# This repoints the link at the newest staged version. It is safe to run before
# every launch: with the link already correct it changes nothing.
#
# Usage:
#   fix-ea-link.sh [PREFIX] [--dry-run] [--prune] [--force]
#
#   PREFIX     wine prefix to repair; defaults to $WINEPREFIX, then to
#              autodetection (Faugus games, common prefix locations)
#   --dry-run  report what would change, touch nothing
#   --prune    also delete superseded version folders and their .zip/.sig
#   --force    act even while the prefix has processes running (they are killed)
#
# Proton and umu are found automatically; set PROTONPATH to override.
set -u

prefix=""; prune=0; dry=0; force=0
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) prefix=${2:-}; shift 2 ;;
        --dry-run|-n) dry=1; shift ;;
        --prune) prune=1; shift ;;
        --force) force=1; shift ;;
        -h|--help) sed -n '2,28p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) prefix=$1; shift ;;
    esac
done

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- locate the prefix ------------------------------------------------------
# A prefix qualifies when it contains an Electronic Arts/EA Desktop directory.
ea_dir_of() {
    local p=$1 d
    for d in "$p/drive_c/Program Files/Electronic Arts/EA Desktop" \
             "$p/drive_c/Program Files (x86)/Electronic Arts/EA Desktop"; do
        [ -d "$d" ] && { printf '%s\n' "$d"; return 0; }
    done
    return 1
}

candidates=()
[ -n "$prefix" ] && candidates=("$prefix")
[ ${#candidates[@]} -eq 0 ] && [ -n "${WINEPREFIX:-}" ] && candidates=("$WINEPREFIX")

if [ ${#candidates[@]} -eq 0 ]; then
    # Prefixes known to Faugus, then the usual places launchers put them.
    games=$HOME/.local/share/faugus-launcher/games.json
    if [ -f "$games" ] && command -v python3 >/dev/null; then
        while IFS= read -r p; do
            [ -n "$p" ] && candidates+=("$p")
        done < <(python3 -I -c '
import json, sys
try:
    for g in json.load(open(sys.argv[1])):
        p = g.get("prefix")
        if p:
            print(p)
except Exception:
    pass' "$games" 2>/dev/null | sort -u)
    fi
    for p in "$HOME"/Faugus/*/ "$HOME"/Games/*/ "$HOME"/.local/share/lutris/prefixes/*/ \
             "$HOME"/.local/share/Steam/steamapps/compatdata/*/pfx /home/*/mnt/*/*/; do
        [ -d "$p" ] && candidates+=("${p%/}")
    done
fi

found=()
for p in "${candidates[@]:-}"; do
    [ -n "$p" ] && [ -d "$p" ] || continue
    ea_dir_of "$p" >/dev/null 2>&1 || continue
    case " ${found[*]:-} " in *" $p "*) continue ;; esac
    found+=("$p")
done

[ ${#found[@]} -eq 0 ] && die "no prefix with an EA app install found; pass one explicitly"
if [ ${#found[@]} -gt 1 ]; then
    printf 'error: several prefixes have an EA app install, pick one:\n' >&2
    printf '  %s\n' "${found[@]}" >&2
    exit 1
fi

PREFIX=${found[0]}
EADIR=$(ea_dir_of "$PREFIX") || die "no EA Desktop directory under $PREFIX"
LINK="$EADIR/EA Desktop?"      # wine stores a reparse point as a dir named '<name>?'
REAL="$EADIR/EA Desktop"       # a plain directory of the same name, if any

say "prefix   : $PREFIX"

# --- state ------------------------------------------------------------------
read_target() {
    getfattr --only-values -n user.WINEREPARSE "$LINK" 2>/dev/null |
        python3 -I -c 'import sys
b = sys.stdin.buffer.read()
print(b[20:].decode("utf-16le").split("\x00")[0] if b else "")' 2>/dev/null
}

# Version folders are the ones holding a nested "EA Desktop/EADesktop.exe".
newest=$(for d in "$EADIR"/*/; do
             [ -f "$d/EA Desktop/EADesktop.exe" ] && basename "$d"
         done | sort -V | tail -1)

current=$(read_target)
real_is_dir=0
[ -d "$REAL" ] && [ ! -L "$REAL" ] && [ -f "$REAL/EADesktop.exe" ] && real_is_dir=1

if [ -z "$newest" ]; then
    if [ $real_is_dir -eq 1 ]; then
        say "no staged version folders; app lives in a plain EA Desktop directory"
        say "nothing to do"
        exit 0
    fi
    die "no EA app install found under $EADIR"
fi

want="$newest\\EA Desktop"
say "newest   : $newest"
say "link     : ${current:-<none>}"
[ $real_is_dir -eq 1 ] && say "note     : 'EA Desktop' is a real directory, which blocks the link"

if [ "$current" = "$want" ] && [ $real_is_dir -eq 0 ]; then
    say "link is already correct, nothing to do"
    [ $prune -eq 0 ] && exit 0
fi

# --- tools ------------------------------------------------------------------
find_proton() {
    [ -n "${PROTONPATH:-}" ] && [ -x "$PROTONPATH/files/bin/wineserver" ] && {
        printf '%s\n' "$PROTONPATH"; return 0; }
    local d best=""
    for d in /usr/share/steam/compatibilitytools.d/*/ \
             "$HOME"/.local/share/Steam/compatibilitytools.d/*/ \
             "$HOME"/.steam/root/compatibilitytools.d/*/ \
             "$HOME"/.local/share/faugus-launcher/components/*/ \
             "$HOME"/.local/share/lutris/runners/wine/*/; do
        [ -x "${d}files/bin/wineserver" ] || continue
        case "$d" in *wineland*) printf '%s\n' "${d%/}"; return 0 ;; esac
        [ -z "$best" ] && best=${d%/}
    done
    [ -n "$best" ] && { printf '%s\n' "$best"; return 0; }
    return 1
}

PROTON=$(find_proton) || die "no Proton build found; set PROTONPATH"
UMU=""
for u in "$(command -v umu-run 2>/dev/null)" "$HOME/.local/share/faugus-launcher/umu-run" \
         "$HOME/.local/share/lutris/runtime/umu/umu-run"; do
    [ -n "$u" ] && [ -x "$u" ] && { UMU=$u; break; }
done
say "proton   : $PROTON"
say "runner   : ${UMU:-$PROTON/files/bin/wine (direct)}"

# The staged folder must be complete, or we would link to a broken install.
for exe in EADesktop.exe EALauncher.exe EABackgroundService.exe; do
    [ -f "$EADIR/$newest/EA Desktop/$exe" ] || die "staged $newest is incomplete (no $exe)"
done

if [ $dry -eq 1 ]; then
    say "--- dry run, no changes ---"
    [ $real_is_dir -eq 1 ] && say "would move '$REAL' aside"
    [ -e "$LINK" ] && say "would remove stale link stub"
    say "would link 'EA Desktop' -> $want"
    [ $prune -eq 1 ] && say "would prune other version folders and zips"
    exit 0
fi

# --- stop anything using the prefix ----------------------------------------
busy=$(pgrep -x wineserver 2>/dev/null | while read -r p; do
           tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null |
               grep -qx "WINEPREFIX=$PREFIX" && echo "$p"
       done)
if [ -n "$busy" ]; then
    if [ $force -eq 0 ]; then
        die "the prefix is in use (wineserver pid $busy); close the EA app/game, or pass --force"
    fi
    say "stopping the running prefix..."
    WINEPREFIX="$PREFIX" "$PROTON/files/bin/wineserver" -k
    sleep 3
fi

# --- relink -----------------------------------------------------------------
if [ $real_is_dir -eq 1 ]; then
    backup="$EADIR/EA Desktop.replaced-$(date +%Y%m%d-%H%M%S)"
    mv "$REAL" "$backup" || die "could not move the old directory aside"
    say "moved old directory to: $(basename "$backup")"
fi
[ -e "$LINK" ] && rm -rf "$LINK"
[ -e "$REAL" ] && rm -rf "$REAL"

# mklink via a .bat: quoted paths with spaces do not survive argument passing.
bat="$EADIR/.relink.bat"
win_dir=$(printf '%s' "${EADIR#*/drive_c}" | tr '/' '\\')
printf '@echo off\r\ncd /d "C:%s"\r\nmklink /d "EA Desktop" "%s\\EA Desktop"\r\n' \
    "$win_dir" "$newest" > "$bat"
if [ -n "$UMU" ]; then
    ( cd "$EADIR" && WINEPREFIX="$PREFIX" PROTONPATH="$PROTON" GAMEID=umu-default \
        WINEDEBUG=-all PROTON_LOG=0 DISPLAY= "$UMU" cmd /c .relink.bat >/dev/null 2>&1 )
else
    ( cd "$EADIR" && WINEPREFIX="$PREFIX" WINEDEBUG=-all DISPLAY= \
        "$PROTON/files/bin/wine" cmd /c .relink.bat >/dev/null 2>&1 )
fi
rm -f "$bat"

current=$(read_target)
[ "$current" = "$want" ] || die "relink failed, link is now: ${current:-<none>}"
say "linked   : EA Desktop -> $current"

# --- prune ------------------------------------------------------------------
if [ $prune -eq 1 ]; then
    for d in "$EADIR"/*/; do
        name=$(basename "$d")
        [ "$name" = "$newest" ] && continue
        [ -f "$d/EA Desktop/EADesktop.exe" ] || continue
        say "pruning version: $name"
        rm -rf "$d"
    done
    for z in "$EADIR"/*.zip "$EADIR"/*.zip.sig; do
        [ -e "$z" ] || continue
        say "pruning: $(basename "$z")"
        rm -f "$z"
    done
fi
