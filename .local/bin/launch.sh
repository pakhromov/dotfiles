#!/bin/sh
set -eu

[ $# -eq 0 ] && { printf 'Usage: launch <compositor>\n' >&2; exit 1; }
compositor="$1"

dbus_env="/tmp/dbus-$USER.env"
# Create new bus if file doesn't exist
if [ ! -f "$dbus_env" ]; then
    dbus-daemon --session --fork --print-address=1 --print-pid=1 > "$dbus_env"
else
    DBUS_SESSION_BUS_ADDRESS="$(sed -n '1p' "$dbus_env")"
    export DBUS_SESSION_BUS_ADDRESS
    # If bus is dead
    if ! dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.GetId >/dev/null 2>&1; then
        dbus-daemon --session --fork --print-address=1 --print-pid=1 > "$dbus_env"
    fi
fi
DBUS_SESSION_BUS_ADDRESS="$(sed -n '1p' "$dbus_env")"
export DBUS_SESSION_BUS_ADDRESS

export PATH="$HOME/.local/bin:$PATH"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"
export EDITOR="subl"
export VISUAL="$EDITOR"
export TERMINAL="kitty"
export BROWSER="vivaldi"
export XCURSOR_SIZE=24

export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
export GTK2_RC_FILES="$XDG_CONFIG_HOME/gtk-2.0/gtkrc"
export TERMINFO="$XDG_DATA_HOME"/terminfo
export TERMINFO_DIRS="$XDG_DATA_HOME"/terminfo:/usr/share/terminfo
export CODEX_HOME="$XDG_CONFIG_HOME"/codex
export CARGO_HOME="$XDG_DATA_HOME"/cargo
export NPM_CONFIG_USERCONFIG=$XDG_CONFIG_HOME/npm/npmrc
export WGETRC="$XDG_CONFIG_HOME/wgetrc"

export NO_AT_BRIDGE=1
export LIBVIRT_DEFAULT_URI=qemu:///system

export GBM_BACKEND=nvidia-drm
export NVD_BACKEND=direct
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export LIBVA_DRIVER_NAME=nvidia
export MOZ_DISABLE_RDD_SANDBOX=1
export CUDA_DISABLE_PERF_BOOST=1
export ELECTRON_OZONE_PLATFORM_HINT=auto
export VIVALDI_FFMPEG_AUTO=0

export LD_LIBRARY_PATH=/home/pavel/Projects/wayfire-fix/wlroots/build
export WAYFIRE_PLUGIN_PATH=/home/pavel/Projects/wayfire-plugins/wayfire-overview-plugin/references/wayfire/build/plugins/single_plugins
#export WAYFIRE_PLUGIN_PATH=/home/pavel/Projects/wayfire-plugins/wayfire-overview-plugin/build-old-wayfire/src:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/window-rules:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/vswitch:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/expo

#export WAYFIRE_DEFAULT_CONFIG_BACKEND=/home/pavel/Projects/wayfire-fix/wayfire/build/src/libdefault-config-backend.so
#export WAYFIRE_PLUGIN_PATH=/home/pavel/Projects/wayfire-plugins/wayfire-overview-plugin/build-old-wayfire/src/:/home/pavel/Projects/wayfire-fix/wayfire/build/src:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/animate:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/blur:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/cube:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/decor:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/grid:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/ipc:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/ipc-rules:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/protocols:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/scale:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/single_plugins:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/tile:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/vswitch:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/window-rules:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/wm-actions:/home/pavel/Projects/wayfire-fix/wayfire/build/plugins/wobbly
#export WAYFIRE_PLUGIN_XML_PATH=/home/pavel/Projects/wayfire-plugins/wayfire-overview-plugin/metadata:/home/pavel/Projects/wayfire-fix/wayfire/metadata

log="/tmp/$compositor.log"

case "$compositor" in
    kwin)
           # Qt picks its platform theme from XDG_CURRENT_DESKTOP. Without it plasma-integration (KDEPlasmaPlatformTheme6.so) never loads, so KCMs write colour scheme / style / icon settings into kdeglobals and nothing ever applies them - every Qt window stays default white no matter what Breeze Dark says.
           export XDG_CURRENT_DESKTOP=KDE
           export XDG_SESSION_DESKTOP=KDE
           export XDG_SESSION_TYPE=wayland
           # Tell xdg-open (used by Electron apps like Discord/Firebot) that this is a Plasma 6 session, so it calls kde-open instead of the long-removed kfmclient. Without this, URL and folder clicks in Electron apps silently do nothing.
           export KDE_SESSION_VERSION=6
           # Marks this as a full KDE session (startplasma sets this too). KDE apps use it to pick their desktop file identity — e.g. System Settings uses systemsettings.desktop instead of kdesystemsettings.desktop, which is what docks/launchers need to resolve its icon correctly.
           export KDE_FULL_SESSION=true
           # Without this, kbuildsycoca6 fails and KDE tools can't find the application menu database, breaking kglobalacceld shortcut registration and the Application Picker
           export XDG_MENU_PREFIX=plasma-
           exec kwin_wayland --xwayland --no-lockscreen </dev/null >"$log" 2>&1 ;;
    jay)   exec jay run </dev/null >"$log" 2>&1 ;;
    river) exec river -no-xwayland </dev/null >"$log" 2>&1 ;;
    sway)  exec sway --unsupported-gpu </dev/null >"$log" 2>&1 ;;
    wayfire) exec wayfire -d </dev/null >"$log" 2>&1 ;;
    *)     exec "$compositor" </dev/null >"$log" 2>&1 ;;
esac



