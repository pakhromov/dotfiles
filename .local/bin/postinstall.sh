#!/usr/bin/env bash

if [[ $EUID -eq 0 ]]; then
    echo "Do not run this script as root"
    exit 1
fi

REPO="pakhromov/dotfiles"
DOTFILES="$HOME/.local/bin/postinstall"
GIT_DIR="$HOME/.dotfiles-git"

add_repos() {
    echo "==> Adding Chaotic-AUR repo..."
    curl -sS 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x3056513887B78AEB' | sudo pacman-key --add -
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
    sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

    echo "==> Adding CachyOS repo..."
    curl -sS 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF3B607488DB35A47' | sudo pacman-key --add -
    sudo pacman-key --lsign-key F3B607488DB35A47
    sudo pacman -U --noconfirm \
        'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' \
        'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-22-1-any.pkg.tar.zst' \
        'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v3-mirrorlist-22-1-any.pkg.tar.zst' \
        'https://mirror.cachyos.org/repo/x86_64/cachyos/pacman-7.1.0.r9.g54d9411-2-x86_64.pkg.tar.zst'
}

clone_dotfiles() {
    echo "==> Cloning dotfiles..."
    git clone --bare "https://github.com/$REPO.git" "$GIT_DIR"
    git --git-dir="$GIT_DIR" config core.bare false
    git --git-dir="$GIT_DIR" config core.worktree "$HOME"
    git --git-dir="$GIT_DIR" --work-tree="$HOME" checkout
    git --git-dir="$GIT_DIR" --work-tree="$HOME" config status.showUntrackedFiles no
    update-mime-database ~/.local/share/mime

    echo "==> Cloning zsh plugins..."
    git clone https://github.com/Skylor-Tang/auto-venv                     "$HOME/.config/zsh/plugins/auto-venv"
    git clone https://github.com/zdharma-continuum/fast-syntax-highlighting "$HOME/.config/zsh/plugins/fast-syntax-highlighting"

    echo "==> Cloning yazi plugins..."
    git clone https://github.com/alberti42/faster-piper.yazi.git          "$HOME/.config/yazi/plugins/faster-piper.yazi"
    git clone https://github.com/BBOOXX/file-actions.yazi.git             "$HOME/.config/yazi/plugins/file-actions.yazi"
    for d in checksum chmod_executable open_git_remote zip_archive_1; do
        ln -sf "$HOME/.config/yazi/actions/$d" \
               "$HOME/.config/yazi/plugins/file-actions.yazi/actions/$d"
    done
    git clone https://github.com/boydaihungst/mediainfo.yazi.git          "$HOME/.config/yazi/plugins/mediainfo.yazi"
    git clone https://github.com/uhs-robert/recycle-bin.yazi.git          "$HOME/.config/yazi/plugins/recycle-bin.yazi"
    git clone https://github.com/uhs-robert/sshfs.yazi.git                "$HOME/.config/yazi/plugins/sshfs.yazi"
    git clone https://github.com/simla33/ucp.yazi.git                     "$HOME/.config/yazi/plugins/ucp.yazi"
    git clone https://github.com/imsi32/yatline-gruvbox-material.yazi.git "$HOME/.config/yazi/plugins/yatline-gruvbox-material.yazi"
    git clone https://github.com/wekauwau/yatline-tokyo-night.yazi.git    "$HOME/.config/yazi/plugins/yatline-tokyo-night.yazi"
    git clone https://github.com/imsi32/yatline.yazi.git                  "$HOME/.config/yazi/plugins/yatline.yazi"

    echo "==> Copying system config files..."
    sudo cp -rT "$DOTFILES/root" /
    sudo pacman -Sy
}

install_official() {
    echo "==> Installing official packages..."
    sudo pacman -S --needed --noconfirm - < "$DOTFILES/packages-repo.txt"
}

install_aur() {
    echo "==> Installing AUR packages..."
    yay -S --needed --noconfirm - < "$DOTFILES/packages-aur.txt"
}

configure_system() {
    sudo ln -sfT /usr/bin/dash /usr/bin/sh
    sudo usermod -s /usr/bin/zsh pavel

    sudo systemctl disable systemd-networkd.service systemd-networkd.socket systemd-networkd-resolve-hook.socket systemd-networkd-varlink.socket
    sudo systemctl disable systemd-resolved.service systemd-resolved-monitor.socket systemd-resolved-varlink.socket
    sudo rm -f /etc/resolv.conf
    sudo ln -s /run/resolvconf/resolv.conf /etc/resolv.conf
    sudo systemctl start iwd
    sudo systemctl enable iwd
    sudo rfkill block bluetooth
    sudo systemctl disable bluetooth.service

    sudo systemctl mask rtkit-daemon
    sudo systemctl mask polkit.service
    sudo systemctl mask polkit-agent-helper.socket
    sudo systemctl mask polkit-agent-helper@.service
    sudo systemctl disable systemd-timesyncd.service
    sudo systemctl disable systemd-userdbd.service
    sudo systemctl disable systemd-userdbd.socket
    sudo systemctl mask upower.service
    sudo systemctl mask user@.service
    sudo systemctl mask systemd-journald.socket
    sudo systemctl mask systemd-journald-dev-log.socket
    sudo systemctl mask systemd-journald
    sudo systemctl mask systemd-journal-flush
    sudo systemctl mask systemd-journald-audit.socket
    sudo systemctl enable greetd.service

    sudo mkdir -p /etc/dbus-1/system-services
    sudo tee /etc/dbus-1/system-services/org.freedesktop.UPower.service >/dev/null <<'EOF'
[D-BUS Service]
Name=org.freedesktop.UPower
Exec=/bin/false
EOF

    sudo tee /etc/sudoers.d/power >/dev/null <<'EOF'
pavel ALL=(root) NOPASSWD: /usr/bin/systemctl poweroff, /usr/bin/systemctl reboot, /usr/bin/systemctl suspend, /usr/bin/systemctl hibernate, /usr/bin/shutdown, /usr/bin/reboot, /usr/bin/chvt
EOF
    sudo chmod 440 /etc/sudoers.d/power

    sudo tee /etc/sudoers.d/mount-mkdir >/dev/null <<'EOF'
pavel ALL=(root) NOPASSWD: /usr/bin/mount, /usr/bin/umount, /usr/bin/mkdir, /usr/bin/rmdir
EOF
    sudo chmod 440 /etc/sudoers.d/mount-mkdir

    echo 'pavel ALL=(root) NOPASSWD: /usr/bin/systemctl stop greetd, /usr/bin/systemctl start greetd' | sudo tee /etc/sudoers.d/greetd >/dev/null
    sudo chmod 0440 /etc/sudoers.d/greetd

    echo 'pavel ALL=(root) NOPASSWD: /usr/bin/chronyd' | sudo tee /etc/sudoers.d/chrony >/dev/null
    sudo chmod 0440 /etc/sudoers.d/chrony

    sudo tee /etc/sudoers.d/vpn-shell >/dev/null <<'EOF'
Cmnd_Alias VPN_CMDS = \
    /usr/bin/ip, \
    /usr/bin/mkdir -p /etc/netns/vpn*, \
    /usr/bin/tee /etc/netns/vpn*/resolv.conf, \
    /usr/bin/rm -rf /etc/netns/vpn*
pavel ALL=(root) NOPASSWD: VPN_CMDS
EOF
    sudo chmod 0440 /etc/sudoers.d/vpn-shell

    echo 'ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chmod g+w /sys/class/backlight/%k/brightness", RUN+="/bin/chgrp video /sys/class/backlight/%k/brightness"' | sudo tee /etc/udev/rules.d/90-backlight.rules >/dev/null
    sudo modprobe i2c-dev
    sudo usermod -aG i2c pavel

    sudo tee /etc/modprobe.d/nobeep.conf >/dev/null <<EOF
blacklist pcspkr
blacklist snd_pcsp
EOF
    sudo mkinitcpio -P
}

check_system() {
    local ok="\033[32m✓\033[0m"
    local fail="\033[31m✗\033[0m"
    local total failed

    echo ""
    echo "==> Repos"
    for repo in cachyos cachyos-v3 cachyos-core-v3 cachyos-extra-v3 chaotic-aur; do
        if pacman -Sl "$repo" &>/dev/null; then
            echo -e "  $ok $repo"
        else
            echo -e "  $fail $repo"
        fi
    done

    echo ""
    echo "==> Native packages"
    total=0; failed=0
    while IFS= read -r pkg; do
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue
        ((total++))
        if ! pacman -Qi "$pkg" &>/dev/null; then
            echo -e "  $fail $pkg"
            ((failed++))
        fi
    done < "$DOTFILES/packages-repo.txt"
    echo "    $((total - failed))/$total installed"

    echo ""
    echo "==> AUR packages"
    total=0; failed=0
    while IFS= read -r pkg; do
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue
        ((total++))
        if ! pacman -Qi "$pkg" &>/dev/null; then
            echo -e "  $fail $pkg"
            ((failed++))
        fi
    done < "$DOTFILES/packages-aur.txt"
    echo "    $((total - failed))/$total installed"

    echo ""
    echo "==> Root dotfiles"
    while IFS= read -r f; do
        system_path="/${f#$DOTFILES/root/}"
        if [[ ! -f "$system_path" ]]; then
            echo -e "  $fail missing: $system_path"
        elif ! sudo diff -q "$f" "$system_path" &>/dev/null; then
            echo -e "  $fail differs: $system_path"
        else
            echo -e "  $ok $system_path"
        fi
    done < <(find "$DOTFILES/root" -type f)

    echo ""
    echo "==> Local dotfiles"
    for d in "$DOTFILES" "$HOME/.config" "$HOME/.local/bin"; do
        if [[ -d "$d" ]]; then
            echo -e "  $ok $d"
        else
            echo -e "  $fail $d"
        fi
    done

    echo ""
    echo "==> System configuration"

    if [[ "$(getent passwd pavel | cut -d: -f7)" == "/usr/bin/zsh" ]]; then
        echo -e "  $ok default shell: zsh"
    else
        echo -e "  $fail default shell: $(getent passwd pavel | cut -d: -f7)"
    fi

    if [[ "$(readlink /usr/bin/sh)" == "/usr/bin/dash" ]]; then
        echo -e "  $ok /usr/bin/sh -> dash"
    else
        echo -e "  $fail /usr/bin/sh -> $(readlink /usr/bin/sh)"
    fi

    if [[ "$(readlink /etc/resolv.conf)" == "/run/resolvconf/resolv.conf" ]]; then
        echo -e "  $ok /etc/resolv.conf symlink"
    else
        echo -e "  $fail /etc/resolv.conf -> $(readlink /etc/resolv.conf)"
    fi

    for svc in iwd greetd; do
        if systemctl is-enabled "$svc" &>/dev/null; then
            echo -e "  $ok $svc enabled"
        else
            echo -e "  $fail $svc not enabled"
        fi
    done

    for svc in rtkit-daemon polkit.service upower.service \
               systemd-journald systemd-journald.socket \
               systemd-journald-dev-log.socket systemd-journald-audit.socket; do
        if [[ "$(systemctl is-enabled "$svc" 2>/dev/null)" == "masked" ]]; then
            echo -e "  $ok $svc masked"
        else
            echo -e "  $fail $svc not masked"
        fi
    done

    for svc in systemd-networkd systemd-resolved systemd-timesyncd bluetooth.service; do
        if ! systemctl is-enabled "$svc" &>/dev/null; then
            echo -e "  $ok $svc disabled"
        else
            echo -e "  $fail $svc still enabled"
        fi
    done

    for f in power mount-mkdir greetd chrony vpn-shell; do
        if sudo test -f "/etc/sudoers.d/$f"; then
            echo -e "  $ok sudoers: $f"
        else
            echo -e "  $fail sudoers: $f missing"
        fi
    done

    for f in /etc/udev/rules.d/90-backlight.rules /etc/modprobe.d/nobeep.conf; do
        if [[ -f "$f" ]]; then
            echo -e "  $ok $f"
        else
            echo -e "  $fail $f missing"
        fi
    done
}

echo "What do you want to do?"
echo "  1) Add repos (Chaotic-AUR + CachyOS)"
echo "  2) Clone dotfiles and copy system config"
echo "  3) Install official packages"
echo "  4) Install AUR packages"
echo "  5) System configuration"
echo "  6) System check"
read -rp "Choice: " choice </dev/tty

case "$choice" in
    1) add_repos ;;
    2) clone_dotfiles ;;
    3) install_official ;;
    4) install_aur ;;
    5) configure_system ;;
    6) check_system ;;
    *) echo "Invalid choice"; exit 1 ;;
esac
