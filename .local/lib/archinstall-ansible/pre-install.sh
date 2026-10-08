#!/usr/bin/env bash

set -Eo pipefail
errors=()
trap 'errors+=("line $LINENO: $BASH_COMMAND (exit $?)")' ERR

pacman -S --needed --noconfirm curl
echo "==> Adding Chaotic-AUR repo..."
curl -sS 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x3056513887B78AEB' | pacman-key --add -
pacman-key --lsign-key 3056513887B78AEB
pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

echo "==> Adding CachyOS repo..."
curl -sS 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF3B607488DB35A47' | pacman-key --add -
pacman-key --lsign-key F3B607488DB35A47
pacman -U --noconfirm \
    'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' \
    'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-27-1-any.pkg.tar.zst' \
    'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v3-mirrorlist-27-1-any.pkg.tar.zst' \
    'https://mirror.cachyos.org/repo/x86_64/cachyos/pacman-7.1.0.r9.g54d9411-4-x86_64.pkg.tar.zst'


pacman -S --needed --noconfirm git
echo "==> Cloning dotfiles..."
git clone -q https://github.com/pakhromov/dotfiles /tmp/dotfiles
cp -rT "/tmp/dotfiles/.local/lib/archinstall-ansible/root" /
rm -rf /tmp/dotfiles

if (( ${#errors[@]} )); then
    printf '%s\n' "${errors[@]}" >&2
    exit 1
fi