#!/bin/bash
# Dotfiles Installation Script
# Author: シグレ ルイセキ (Shigure Ruiseki)
# Description: Automated installer for desktop environment
# Version: 1.0

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="$SCRIPT_DIR/install.log"
readonly BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d_%H%M%S)"

bootstrap() {
    echo "🔒 Authenticating sudo for installation..."
    sudo -v

    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

    if ! command -v gum >/dev/null 2>&1; then
        echo "  ==> Installing gum..."
        sudo pacman -S --needed --noconfirm gum
    fi

    echo "  ==> Bootstrap complete."
    echo ""
}

# ─── Logging ──────────────────────────────────────────────────────────────────
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" >> "$LOG_FILE"; }

step()    { gum log --level info  "➤  $1"; log "STEP"    "$1"; }
success() { gum log --level info  "✓  $1"; log "SUCCESS" "$1"; }
warning() { gum log --level warn  "$1";    log "WARNING" "$1"; }
err()     { gum log --level error "$1";    log "ERROR"   "$1"; }
info()    { gum log --level debug "$1";    log "INFO"    "$1"; }

# ─── Header ───────────────────────────────────────────────────────────────────
print_header() {
    clear
    gum style \
    --border double \
    --border-foreground 135 \
    --foreground 255 \
    --bold \
    --align center \
    --width 64 \
    --padding "1 4" \
    "⚙ Dotfiles Installer" \
    "シグレ ルイセキ Setup  •  1.0"
    echo
}

# ─── Check system ─────────────────────────────────────────────────────────────
check_system() {
    step "Checking system compatibility..."

    if ! command -v pacman >/dev/null 2>&1; then
        err "This script requires Arch Linux or an Arch-based distribution"
        exit 1
    fi

    if [[ $EUID -eq 0 ]]; then
        err "Do not run this script as root!"
        exit 1
    fi

    success "System check passed — Arch Linux btw detected"
}

# ─── Backup ───────────────────────────────────────────────────────────────────
create_backup() {
    step "Checking for existing configurations..."

    local configs=(
        ".config/fastfetch" 
        ".config/kitty"
    )

    local found=()
    for c in "${configs[@]}"; do
        [[ -e "$HOME/$c" ]] && found+=("$c")
    done

    if [[ ${#found[@]} -eq 0 ]]; then
        info "No existing configs found — backup skipped"
        return 0
    fi

    gum style --foreground 220 --bold "Found existing configs:"
    printf '  • %s\n' "${found[@]}"
    echo

    # gum confirm: exit 0 = Yes, exit 1 = No
    if ! gum confirm "Create backup before overwriting?"; then
        warning "Backup skipped by user"
        return 0
    fi

    mkdir -p "$BACKUP_DIR"
    for c in "${found[@]}"; do
        cp -r "$HOME/$c" "$BACKUP_DIR/" 2>/dev/null || true
        info "Backed up: $c"
    done

    success "Backup saved to: $BACKUP_DIR"
}

# ─── AUR helper ───────────────────────────────────────────────────────────────
install_aur_helper() {
    step "Checking for AUR helper..."

    for helper in paru yay trizen pikaur; do
        if command -v "$helper" >/dev/null 2>&1; then
            success "Found AUR helper: $helper"
            echo "$helper"
            return 0
        fi
    done

    info "No AUR helper found."

    local choice
    choice=$(gum choose \
        --header "Select AUR helper to install:" \
    "paru" "yay" "trizen" "pikaur")

    gum confirm "Install $choice now?" || { err "AUR helper installation cancelled"; exit 1; }

    local tmp_dir
    tmp_dir=$(mktemp -d)

    gum spin --spinner globe --title "Cloning $choice from AUR..." -- \
    git clone "https://aur.archlinux.org/${choice}-bin.git" "$tmp_dir/${choice}-bin" 2>/dev/null \
    || git clone "https://aur.archlinux.org/${choice}.git" "$tmp_dir/${choice}"

    local build_dir="$tmp_dir/${choice}-bin"
    [[ -d "$build_dir" ]] || build_dir="$tmp_dir/${choice}"

    gum spin --spinner moon --title "Building & installing $choice..." -- \
    bash -c "cd '$build_dir' && makepkg -si --noconfirm"

    rm -rf "$tmp_dir"
    success "$choice installed successfully"
    echo "$choice"
}

# ─── Install packages ─────────────────────────────────────────────────────────
install_packages() {
    local aur_helper="$1"
    step "Reading packages from pkgs.txt..."

    if [[ ! -f "$SCRIPT_DIR/pkgs.txt" ]]; then
        err "pkgs.txt not found in $SCRIPT_DIR"
        return 1
    fi

    local packages=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | sed 's/#.*$//' | xargs)
        [[ -n "$line" ]] && packages+=("$line")
    done < "$SCRIPT_DIR/pkgs.txt"

    if [[ ${#packages[@]} -eq 0 ]]; then
        warning "No valid packages found in pkgs.txt"
        return 0
    fi

    info "Found ${#packages[@]} packages to install"

    gum style --foreground 220 --bold "Packages to install:"
    printf '  • %s\n' "${packages[@]}"
    echo

    gum confirm "Install all ${#packages[@]} packages with $aur_helper?" \
    || { err "Installation cancelled by user"; exit 1; }

    echo "🔄 Installing packages via $aur_helper..."
    "$aur_helper" -S --needed --noconfirm "${packages[@]}"

    success "All packages installed successfully"
}

# ─── Install configs ──────────────────────────────────────────────────────────
install_configs() {
    step "Installing configuration files..."

    local source_dir=""

    if [[ -d "$SCRIPT_DIR/home/username" ]]; then
        source_dir="$SCRIPT_DIR/home/username"
    elif [[ -d "$SCRIPT_DIR/.config" ]] || [[ -f "$SCRIPT_DIR/.xinitrc" ]]; then
        source_dir="$SCRIPT_DIR"
    elif [[ -d "$SCRIPT_DIR/config" ]]; then
        source_dir="$SCRIPT_DIR"
    else
        source_dir="$SCRIPT_DIR"
    fi

    info "Source directory detected: $source_dir"

    mkdir -p "$HOME/.config"

    if [[ -d "$source_dir/.config" ]]; then
        gum spin --spinner dot --title "Syncing .config to $HOME..." -- \
        cp -rf "$source_dir/.config"/. "$HOME/.config/"
    elif [[ -d "$source_dir/config" ]]; then
        gum spin --spinner dot --title "Syncing config folders to $HOME/.config..." -- \
        cp -rf "$source_dir/config"/. "$HOME/.config/"
    fi

    [[ -f "$source_dir/.xinitrc" ]] && cp -f "$source_dir/.xinitrc" "$HOME/"
    [[ -f "$source_dir/xinitrc" ]] && cp -f "$source_dir/xinitrc" "$HOME/.xinitrc"
    [[ -f "$source_dir/.zshrc" ]] && cp -f "$source_dir/.zshrc" "$HOME/"

    if [[ -f "$SCRIPT_DIR/etc/pam.d/awesome" ]]; then
        echo "🔒 Updating PAM config..."
        sudo cp "$SCRIPT_DIR/etc/pam.d/awesome" "/etc/pam.d/"
    fi

    chmod +x "$HOME/.config/awesome/lock.sh" 2>/dev/null || true
    chmod +x "$HOME/.xinitrc" 2>/dev/null || true

    success "Configuration files installed & permissions set"
}

# ─── Post install ─────────────────────────────────────────────────────────────
post_install() {
    step "Running post-installation tasks..."

    if command -v fc-cache >/dev/null 2>&1; then
        gum spin --spinner dot --title "Updating font cache..." -- fc-cache -fv
        success "Font cache updated"
    fi

    success "Post-installation tasks completed"
}

# ─── Final message ────────────────────────────────────────────────────────────
show_final_message() {
    echo
    gum style \
    --border rounded \
    --border-foreground 76 \
    --foreground 255 \
    --bold \
    --align center \
    --width 64 \
    --padding "1 4" \
    "✅  Installation Complete!"
    echo

    gum style --foreground 69 "📄 Log  : $LOG_FILE"
    [[ -d "$BACKUP_DIR" ]] && gum style --foreground 69 "💾 Backup: $BACKUP_DIR"
    echo
    gum style --foreground 135 --align center --width 64 "Made with 💙 by シグレ ルイセキ"
    echo
}

# ─── Cleanup ──────────────────────────────────────────────────────────────────
cleanup() {
    local code=$?
    [[ $code -ne 0 ]] && err "Installation failed! Check $LOG_FILE for details."
    exit $code
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    trap cleanup EXIT
    : > "$LOG_FILE"

    bootstrap

    print_header
    check_system
    create_backup

    local aur_helper
    aur_helper=$(install_aur_helper)

    install_packages "$aur_helper"
    install_configs
    post_install
    show_final_message

    success "Installation completed successfully!"
}

# Run main function
main "$@"