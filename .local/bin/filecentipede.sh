#!/bin/sh
set -eu

: "${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR not set}"
: "${DBUS_SESSION_BUS_ADDRESS:?DBUS_SESSION_BUS_ADDRESS not set}"

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

spawn /opt/filecentipede/filec -y
sleep 0.2
spawn filecentipede
sleep 0.2
spawn filecentipede

wait
