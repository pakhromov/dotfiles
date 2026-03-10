#!/usr/bin/env zsh

THEMES_DIR="$HOME/.config/zsh/themes"

print_separator() {
    print "\n\n\n\n\n"
}

print_header() {
    print "\033[1;36m━━━ $1 ━━━\033[0m"
}

# Preview oh-my-posh themes
if [[ -d "$THEMES_DIR/ohmyposh_themes" ]]; then
    for theme in "$THEMES_DIR/ohmyposh_themes"/*.(json|yaml|toml)(N); do
        [[ -f "$theme" ]] || continue
        print_header "Oh-My-Posh: ${theme:t:r}"
        oh-my-posh print primary --config "$theme" 2>&1 || print "\033[1;31m[Config error - skipping]\033[0m"
        print ""
        print_separator
    done
fi

print "\033[1;32mDone previewing all themes!\033[0m"
