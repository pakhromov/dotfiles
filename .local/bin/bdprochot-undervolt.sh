#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -ne 0 ]] && exec sudo "$0" "$@"

/sbin/modprobe msr

RDMSR=/usr/sbin/rdmsr
WRMSR=/usr/sbin/wrmsr

for dev in /dev/cpu/[0-9]*/msr; do
  cpu=${dev#/dev/cpu/}
  cpu=${cpu%/msr}

  old_hex=$("$RDMSR" -p "$cpu" 0x1FC)
  old_dec=$((0x$old_hex))
  new_dec=$((old_dec & ~1))
  new_hex=$(printf "0x%X" "$new_dec")

  "$WRMSR" -p "$cpu" 0x1FC "$new_hex"
done

undervolt --gpu -100 --core -150 --cache -150 --uncore -100 --analogio -100
