#!/bin/sh
# Start the pieces screen sharing needs, on demand. Nothing here runs in the
# background otherwise - kill this script and it takes its children with it.
#
# The desktop portal backend is chosen from XDG_CURRENT_DESKTOP (a colon
# separated list, e.g. "Wayfire:wlroots"):
#   hyprland -> xdg-desktop-portal-hyprland
#   wayfire  -> xdg-desktop-portal-wlr
#
# Routing is separate from starting: xdg-desktop-portal decides which backend
# serves ScreenCast from portals.conf(5). Per-desktop files
# (~/.config/xdg-desktop-portal/DESKTOP-portals.conf) take precedence over the
# plain portals.conf, so each compositor gets the matching backend.
set -eu

: "${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR not set}"
: "${DBUS_SESSION_BUS_ADDRESS:?DBUS_SESSION_BUS_ADDRESS not set}"

current_desktop() {
    case ":$(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]'):" in
        *:hyprland:*) echo hyprland ;;
        *:wayfire:*)  echo wayfire ;;
        *)            echo unknown ;;
    esac
}

case "$(current_desktop)" in
    hyprland) BACKEND=/usr/lib/xdg-desktop-portal-hyprland ;;
    wayfire)  BACKEND=/usr/lib/xdg-desktop-portal-wlr ;;
    *)
        echo "start-portal.sh: unsupported XDG_CURRENT_DESKTOP='${XDG_CURRENT_DESKTOP:-}'" >&2
        echo "start-portal.sh: expected a list containing Hyprland or Wayfire" >&2
        exit 1
        ;;
esac

[ -x "$BACKEND" ] || { echo "start-portal.sh: $BACKEND not installed" >&2; exit 1; }

pids=""
spawn() {
    "$@" &
    pids="$pids $!"
}

cleanup() {
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null
    wait $pids 2>/dev/null
}
trap cleanup EXIT INT TERM

# pgrep -x matches comm, which the kernel truncates to 15 characters, so it can
# never match names like "xdg-desktop-portal-wlr". Match the full command line
# instead, exactly, so the -wlr backend is not mistaken for the -hyprland one.
running() { pgrep -fx "$1" >/dev/null 2>&1; }

start_once() { running "$1" || spawn "$1"; }

pgrep -x pipewire     >/dev/null 2>&1 || spawn /usr/bin/pipewire
sleep 0.2
pgrep -x wireplumber  >/dev/null 2>&1 || spawn /usr/bin/wireplumber
sleep 0.2

start_once /usr/lib/xdg-permission-store
sleep 0.1
start_once /usr/lib/xdg-document-portal
sleep 0.1
start_once "$BACKEND"
sleep 0.1
start_once /usr/lib/xdg-desktop-portal

echo "start-portal.sh: backend $(basename "$BACKEND") for $(current_desktop)" >&2
wait
