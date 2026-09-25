#!/bin/bash
# Launch the EA app under proton-wineland via umu, forcing native Wayland.
#
# Any arguments are passed to EALauncher.exe, which is how browser protocol
# links arrive, e.g.
#   ea-app-wayland.sh 'origin2://game/launch/?offerIds=...&authCode=...'
# See ~/.local/lib/ea-protocol-handler.sh for the origin2:// registration.
set -u

sudo mount /dev/nvme0n1p4 /home/pavel/mnt/nvme0n1p4

PREFIX=/home/pavel/mnt/nvme0n1p4/ea-app
LIB=/home/pavel/.local/lib
LOGDIR="$PREFIX/logs"
# Set KEEPLOGS=1 to give each launch its own log dir, for comparing runs.
if [ -n "${KEEPLOGS:-}" ]; then
    LOGDIR="$LOGDIR/run-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$LOGDIR"

UMU=/home/pavel/.local/share/lutris/runtime/umu/umu-run
stamp=$(date +%H%M%S)

# An EA app self-update leaves "EA Desktop\EA Desktop" pointing at the previous
# version, which makes the app hang on "Connecting to the EA app". Repoint it
# before launching; this is a no-op when the link is already correct.
"$LIB/fix-ea-link.sh" || exit 1

# That link lives on disk as a directory named "EA Desktop?", which no unix path
# can traverse, so resolve the versioned dir instead.
EA=$(ls -d "$PREFIX/drive_c/Program Files/Electronic Arts/EA Desktop"/*/"EA Desktop"/EALauncher.exe 2>/dev/null | sort -V | tail -1)
if [ -z "$EA" ]; then
    echo "error: no EALauncher.exe found under $PREFIX" >&2
    exit 1
fi

export WINEPREFIX="$PREFIX"
export PROTONPATH=/usr/share/steam/compatibilitytools.d/proton-wineland
export GAMEID=umu-default
export STORE=ea
export PROTON_ENABLE_WAYLAND=1
unset DISPLAY                       # no X11 fallback: native Wayland or nothing
export PROTON_LOG=1
export PROTON_LOG_DIR="$LOGDIR"
export WINEDEBUG="${WINEDEBUG:-+seh,+loaddll,+process,err+all,fixme-all,+waylanddrv}"
export DXVK_LOG_LEVEL=info
export DXVK_LOG_PATH="$LOGDIR"
export VKD3D_DEBUG=warn

# gamemode switches the CPU governor to performance while the game runs (needs
# membership of the "gamemode" group). Set NOGAMEMODE=1 to launch without it.
GM=()
if [ -z "${NOGAMEMODE:-}" ] && command -v gamemoderun >/dev/null; then
    GM=(gamemoderun)
fi

bdprochot-undervolt.sh

exec "${GM[@]}" "$UMU" "$EA" "$@" >"$LOGDIR/ea-$stamp.out" 2>&1
