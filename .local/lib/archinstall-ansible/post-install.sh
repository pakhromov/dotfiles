#!/usr/bin/env bash

set -Eo pipefail
errors=()
trap 'errors+=("line $LINENO: $BASH_COMMAND (exit $?)")' ERR
export GIT_TERMINAL_PROMPT=0
clone() { [[ -d "${@: -1}" ]] || git clone -q "$@"; }

REPO="pakhromov/dotfiles"
DOTFILES="$HOME/.local/lib/archinstall-ansible"
GIT_DIR="$HOME/.dotfiles-git"


sudo pacman -S --needed --noconfirm git
echo "==> Cloning dotfiles..."
clone --bare "https://github.com/$REPO.git" "$GIT_DIR"
git --git-dir="$GIT_DIR" config core.bare false
git --git-dir="$GIT_DIR" config core.worktree "$HOME"
git --git-dir="$GIT_DIR" --work-tree="$HOME" checkout
git --git-dir="$GIT_DIR" --work-tree="$HOME" config status.showUntrackedFiles no

echo "==> Cloning zsh plugins..."
clone https://github.com/zdharma-continuum/fast-syntax-highlighting "$HOME/.config/zsh/plugins/fast-syntax-highlighting"
clone https://github.com/pakhromov/zsh-autosuggestions              "$HOME/.config/zsh/plugins/zsh-autosuggestions"

echo "==> Cloning yazi plugins..."
clone https://github.com/alberti42/faster-piper.yazi.git          "$HOME/.config/yazi/plugins/faster-piper.yazi"
clone https://github.com/BBOOXX/file-actions.yazi.git             "$HOME/.config/yazi/plugins/file-actions.yazi"
rm -rf "$HOME/.config/yazi/plugins/file-actions.yazi/actions"
ln -sf "$HOME/.config/yazi/actions" "$HOME/.config/yazi/plugins/file-actions.yazi/actions"
clone https://github.com/boydaihungst/mediainfo.yazi.git          "$HOME/.config/yazi/plugins/mediainfo.yazi"
clone https://github.com/uhs-robert/recycle-bin.yazi.git          "$HOME/.config/yazi/plugins/recycle-bin.yazi"
clone https://github.com/uhs-robert/sshfs.yazi.git                "$HOME/.config/yazi/plugins/sshfs.yazi"
clone https://github.com/simla33/ucp.yazi.git                     "$HOME/.config/yazi/plugins/ucp.yazi"
clone https://github.com/imsi32/yatline-gruvbox-material.yazi.git "$HOME/.config/yazi/plugins/yatline-gruvbox-material.yazi"
clone https://github.com/wekauwau/yatline-tokyo-night.yazi.git    "$HOME/.config/yazi/plugins/yatline-tokyo-night.yazi"
clone https://github.com/imsi32/yatline.yazi.git                  "$HOME/.config/yazi/plugins/yatline.yazi"
clone https://github.com/pakhromov/localsend.yazi                 "$HOME/.config/yazi/plugins/localsend.yazi"
clone https://github.com/pakhromov/yatline-selected-size.yazi     "$HOME/.config/yazi/plugins/yatline-selected-size.yazi"
clone https://github.com/pakhromov/yatline-disk-usage.yazi        "$HOME/.config/yazi/plugins/yatline-disk-usage.yazi"
clone https://github.com/pakhromov/smart-tab.yazi                 "$HOME/.config/yazi/plugins/smart-tab.yazi"
clone https://github.com/pakhromov/batch-rename-gui.yazi          "$HOME/.config/yazi/plugins/batch-rename-gui.yazi"
clone https://github.com/pakhromov/goto-file-dir.yazi             "$HOME/.config/yazi/plugins/goto-file-dir.yazi"
clone https://github.com/pakhromov/to-pdf-preview.yazi            "$HOME/.config/yazi/plugins/to-pdf-preview.yazi"
clone https://github.com/pakhromov/autosave.yazi                  "$HOME/.config/yazi/plugins/autosave.yazi"
clone https://github.com/pakhromov/paste-navigate.yazi            "$HOME/.config/yazi/plugins/paste-navigate.yazi"
clone https://github.com/pakhromov/xcursor-preview.yazi           "$HOME/.config/yazi/plugins/xcursor-preview.yazi"

echo "==> Cloning Sublime Text plugins..."
clone --branch personal https://github.com/pakhromov/TabBarTools  "$HOME/.config/sublime-text/Packages/TabBarTools"
clone https://github.com/pakhromov/QColor                         "$HOME/.config/sublime-text/Packages/QColor"

echo "==> Installing AUR packages..."
yay -S --needed --noconfirm - <<'EOF'
acestream-engine
alsa-switch
calendar-git
cclip
ccstatusline
clock-rs-git
dulcepan-git
flow-control-nightly-bin
focus-bin
fsel
ghgrab-bin
grabit-bin
iwmenu-bin
lazydlp-bin
lidm-bin
lidm-systemd
localsend-go-bin
lore-bin
mako-daemonless
mark-shot
mcat-bin
monstar
mousam
pdf2img-c
python-undervolt
python-xlsx2csv
pywayfire-git
rar
rich-cli
scrop-bin
seekey
shanns-liga-nerd-font
shmooz
sidex-bin
surge-bin
tparted-bin
vala-rofi-polkit
vpn-shell
wayfire-plugins-extra-git
wayscriber-bin
wcm-git
wlrctl
xytz-bin
yzf
zzzclip
EOF

#broken packages
#btop-gpu-git
#mal

d=$(mktemp -d) && printf "[org/gnome/desktop/interface]\ngtk-theme='Materia-dark-compact'\ncursor-theme='LiOSV'\ncursor-size=24\nfont-name='ComicShannsLigaMod Nerd Font 12'\n" > "$d/settings" && mkdir -p ~/.config/dconf && dconf compile ~/.config/dconf/user "$d" && rm -r "$d"

sudo cp -rT "$DOTFILES/root" /

if (( ${#errors[@]} )); then
    printf '%s\n' "${errors[@]}" >&2
    exit 1
fi