#!/usr/bin/env bash

if [[ $EUID -eq 0 ]]; then
    echo "Do not run this script as root"
    exit 1
fi

REPO="pakhromov/dotfiles"
DOTFILES="$HOME/.local/share/postinstall"
GIT_DIR="$HOME/.dotfiles-git"

add_repos() {
    sudo pacman -S --needed --noconfirm curl
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
    sudo pacman -S --needed --noconfirm git
    echo "==> Cloning dotfiles..."
    git clone --bare "https://github.com/$REPO.git" "$GIT_DIR"
    git --git-dir="$GIT_DIR" config core.bare false
    git --git-dir="$GIT_DIR" config core.worktree "$HOME"
    git --git-dir="$GIT_DIR" --work-tree="$HOME" checkout
    git --git-dir="$GIT_DIR" --work-tree="$HOME" config status.showUntrackedFiles no

    #echo "==> Cloning Firefox Lepton theme..."
    #PROFILE_DIR="$HOME/.config/mozilla/firefox/pavel.default"
    #git clone https://github.com/black7375/Firefox-UI-Fix "$PROFILE_DIR/chrome" -b photon-style
    #cp "$PROFILE_DIR/userChrome.css" "$PROFILE_DIR/chrome/userChrome.css"
    #cp "$PROFILE_DIR/prefs-initial.js" "$PROFILE_DIR/prefs.js"

    echo "==> Cloning zsh plugins..."
    git clone https://github.com/zdharma-continuum/fast-syntax-highlighting "$HOME/.config/zsh/plugins/fast-syntax-highlighting"
    git clone https://github.com/pakhromov/zsh-autosuggestions              "$HOME/.config/zsh/plugins/zsh-autosuggestions"

    echo "==> Cloning yazi plugins..."
    git clone https://github.com/alberti42/faster-piper.yazi.git          "$HOME/.config/yazi/plugins/faster-piper.yazi"
    git clone https://github.com/BBOOXX/file-actions.yazi.git             "$HOME/.config/yazi/plugins/file-actions.yazi"
    rm -rf "$HOME/.config/yazi/plugins/file-actions.yazi/actions"
    ln -sf "$HOME/.config/yazi/actions" "$HOME/.config/yazi/plugins/file-actions.yazi/actions"
    git clone https://github.com/boydaihungst/mediainfo.yazi.git          "$HOME/.config/yazi/plugins/mediainfo.yazi"
    git clone https://github.com/uhs-robert/recycle-bin.yazi.git          "$HOME/.config/yazi/plugins/recycle-bin.yazi"
    git clone https://github.com/uhs-robert/sshfs.yazi.git                "$HOME/.config/yazi/plugins/sshfs.yazi"
    git clone https://github.com/simla33/ucp.yazi.git                     "$HOME/.config/yazi/plugins/ucp.yazi"
    git clone https://github.com/imsi32/yatline-gruvbox-material.yazi.git "$HOME/.config/yazi/plugins/yatline-gruvbox-material.yazi"
    git clone https://github.com/wekauwau/yatline-tokyo-night.yazi.git    "$HOME/.config/yazi/plugins/yatline-tokyo-night.yazi"
    git clone https://github.com/imsi32/yatline.yazi.git                  "$HOME/.config/yazi/plugins/yatline.yazi"
    git clone https://github.com/pakhromov/localsend.yazi                 "$HOME/.config/yazi/plugins/localsend.yazi"
    git clone https://github.com/pakhromov/yatline-selected-size.yazi     "$HOME/.config/yazi/plugins/yatline-selected-size.yazi"
    git clone https://github.com/pakhromov/yatline-disk-usage.yazi        "$HOME/.config/yazi/plugins/yatline-disk-usage.yazi"
    git clone https://github.com/pakhromov/smart-tab.yazi                 "$HOME/.config/yazi/plugins/smart-tab.yazi"
    git clone https://github.com/pakhromov/batch-rename-gui.yazi          "$HOME/.config/yazi/plugins/batch-rename-gui.yazi"
    git clone https://github.com/pakhromov/goto-file-dir.yazi             "$HOME/.config/yazi/plugins/goto-file-dir.yazi"
    git clone https://github.com/pakhromov/to-pdf-preview.yazi            "$HOME/.config/yazi/plugins/to-pdf-preview.yazi"
    git clone https://github.com/pakhromov/autosave.yazi                  "$HOME/.config/yazi/plugins/autosave.yazi"
    git clone https://github.com/pakhromov/paste-navigate.yazi            "$HOME/.config/yazi/plugins/paste-navigate.yazi"
    git clone https://github.com/pakhromov/xcursor-preview.yazi           "$HOME/.config/yazi/plugins/xcursor-preview.yazi"

    echo "==> Cloning Sublime Text plugins..."
    git clone --branch personal https://github.com/pakhromov/TabBarTools  "$HOME/.config/sublime-text/Packages/TabBarTools"
    git clone https://github.com/pakhromov/WordHighlight                  "$HOME/.config/sublime-text/Packages/WordHighlight"
    git clone https://github.com/pakhromov/QColor                         "$HOME/.config/sublime-text/Packages/QColor"

    sudo pacman -Syyu
}

install_gpu_drivers() {
    echo "Which GPU drivers to install?"
    echo "  1) NVIDIA"
    echo "  2) AMD"
    read -rp "Choice: " gpu </dev/tty

    case "$gpu" in
        1)
            echo "==> Installing NVIDIA drivers..."
            sudo pacman -S --needed --noconfirm nvidia-open nvidia-utils libva-nvidia-driver-git egl-wayland lib32-nvidia-utils
            ;;
        2)
            echo "==> Installing AMD drivers..."
            sudo pacman -S --needed --noconfirm mesa vulkan-radeon lib32-mesa lib32-vulkan-radeon
            ;;
        *)
            echo "Invalid choice, skipping GPU drivers."
            ;;
    esac
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
    sudo cp -rT "$DOTFILES/root" /
    sudo usermod -s /usr/bin/zsh pavel
    sudo usermod -aG i2c pavel
    d=$(mktemp -d) && printf "[org/gnome/desktop/interface]\ngtk-theme='Materia-dark-compact'\ncursor-theme='LiOSV'\ncursor-size=24\nfont-name='ComicShannsLigaMod Nerd Font 12'\n" > "$d/settings" && mkdir -p ~/.config/dconf && dconf compile ~/.config/dconf/user "$d" && rm -r "$d"
    update-mime-database ~/.local/share/mime

    #sudo systemctl mask systemd-journald systemd-journald.socket systemd-journald-dev-log.socket systemd-journal-flush systemd-journald-audit.socket
    sudo systemctl disable systemd-networkd.service systemd-networkd.socket systemd-networkd-resolve-hook.socket systemd-networkd-varlink.socket
    sudo systemctl disable systemd-resolved.service systemd-resolved-monitor.socket systemd-resolved-varlink.socket
    sudo rm -f /etc/resolv.conf
    sudo ln -s /run/resolvconf/resolv.conf /etc/resolv.conf
    sudo systemctl enable iwd
    sudo rfkill block bluetooth
    sudo systemctl disable bluetooth.service
    sudo systemctl disable getty@tty1.service
    sudo systemctl enable lidm

    sudo systemctl disable systemd-timesyncd.service
    sudo systemctl enable chronyd-sync
    sudo systemctl disable systemd-userdbd.service systemd-userdbd.socket
    sudo systemctl mask user@.service
    sudo systemctl mask rtkit-daemon

    sudo mkinitcpio -P
}

echo "What do you want to do?"
echo "  1) Add repos (Chaotic-AUR + CachyOS)"
echo "  2) Clone dotfiles and copy system config"
echo "  3) Install GPU drivers"
echo "  4) Install official packages"
echo "  5) Install AUR packages"
echo "  6) System configuration"
read -rp "Choice: " choice </dev/tty

case "$choice" in
    1) add_repos ;;
    2) clone_dotfiles ;;
    3) install_gpu_drivers ;;
    4) install_official ;;
    5) install_aur ;;
    6) configure_system ;;
    *) echo "Invalid choice"; exit 1 ;;
esac
