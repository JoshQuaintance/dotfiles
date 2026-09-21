#!/usr/bin/env bash
# ==============================================================================
# install-fonts.sh — Universal Developer Font Installer (macOS, Linux, & WSL)
# Installs: Miracode (primary), FiraCode Nerd Font (fallback), & Monocraft (pixel)
# ==============================================================================
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$DOTFILES_DIR/install/common.sh" ] && source "$DOTFILES_DIR/install/common.sh" || {
    info() { printf "\033[38;2;137;180;250m[INFO]\033[0m %s\n" "$*"; }
    success() { printf "\033[38;2;166;227;161m[✔]\033[0m %s\n" "$*"; }
    warn() { printf "\033[38;2;249;226;175m[WARN]\033[0m %s\n" "$*"; }
    error() { printf "\033[38;2;243;139;168m[ERROR]\033[0m %s\n" "$*"; }
}

# Detect environment
IS_MAC=false
IS_WSL=false
IS_LINUX=false

if [[ "$OSTYPE" == darwin* ]] || [ "$(uname -s)" = "Darwin" ]; then
    IS_MAC=true
elif [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
    IS_LINUX=true
elif [ "$(uname -s)" = "Linux" ]; then
    IS_LINUX=true
fi

info "Detected environment: $( $IS_MAC && echo "macOS" || ($IS_WSL && echo "WSL (Windows Subsystem for Linux)" || echo "Native Linux") )"

# ------------------------------------------------------------------------------
# 1. macOS (Homebrew Cask)
# ------------------------------------------------------------------------------
if [ "$IS_MAC" = true ]; then
    if command -v brew &>/dev/null; then
        info "Installing fonts via Homebrew Casks..."
        brew install --cask font-miracode font-fira-code-nerd-font font-monocraft 2>/dev/null || true
        success "Fonts installed on macOS via Homebrew!"
        exit 0
    else
        warn "Homebrew not found on macOS, falling back to manual font download..."
    fi
fi

# ------------------------------------------------------------------------------
# 2. Linux & WSL (Direct Download & Fontconfig)
# ------------------------------------------------------------------------------
FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
mkdir -p "$FONT_DIR/Miracode" "$FONT_DIR/FiraCode" "$FONT_DIR/Monocraft"

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# 2a. Miracode
info "Downloading Miracode font..."
if curl -fsSL "https://github.com/IdreesInc/Miracode/releases/latest/download/Miracode.ttf" -o "$FONT_DIR/Miracode/Miracode.ttf"; then
    success "Miracode installed to $FONT_DIR/Miracode"
else
    warn "Failed to download Miracode, continuing..."
fi

# 2b. FiraCode Nerd Font
info "Downloading FiraCode Nerd Font..."
if curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.tar.xz" -o "$TMP_DIR/FiraCode.tar.xz"; then
    tar -xJf "$TMP_DIR/FiraCode.tar.xz" -C "$FONT_DIR/FiraCode" "*.ttf" 2>/dev/null || tar -xJf "$TMP_DIR/FiraCode.tar.xz" -C "$FONT_DIR/FiraCode"
    success "FiraCode Nerd Font installed to $FONT_DIR/FiraCode"
else
    warn "Failed to download FiraCode Nerd Font, continuing..."
fi

# 2c. Monocraft (with Nerd Font patches)
info "Downloading Monocraft..."
if curl -fsSL "https://github.com/IdreesInc/Monocraft/releases/latest/download/Monocraft-nerd-fonts-patched.ttc" -o "$FONT_DIR/Monocraft/Monocraft-nerd-fonts-patched.ttc"; then
    success "Monocraft installed to $FONT_DIR/Monocraft"
else
    warn "Failed to download Monocraft, continuing..."
fi

# Refresh Fontconfig cache on Linux
if command -v fc-cache &>/dev/null; then
    info "Rebuilding Fontconfig cache..."
    fc-cache -f "$FONT_DIR" 2>/dev/null || true
    success "Linux font cache refreshed!"
fi

# ------------------------------------------------------------------------------
# 3. WSL: Automatic Windows Host Font Registration
# ------------------------------------------------------------------------------
if [ "$IS_WSL" = true ]; then
    info "Detected WSL environment. Registering fonts into Windows host..."

    if command -v powershell.exe &>/dev/null; then
        # Retrieve Windows User Profile directory
        WIN_USERPROFILE=$(powershell.exe -NoProfile -Command '$env:USERPROFILE' 2>/dev/null | tr -d '\r')
        if [ -n "$WIN_USERPROFILE" ] && command -v wslpath &>/dev/null; then
            WIN_USER_MOUNT="$(wslpath "$WIN_USERPROFILE")"
            WIN_FONT_DIR="$WIN_USER_MOUNT/AppData/Local/Microsoft/Windows/Fonts"
            mkdir -p "$WIN_FONT_DIR"

            info "Copying fonts to Windows font directory ($WIN_FONT_DIR)..."
            cp -f "$FONT_DIR/Miracode/"* "$WIN_FONT_DIR/" 2>/dev/null || true
            cp -f "$FONT_DIR/FiraCode/"*.ttf "$WIN_FONT_DIR/" 2>/dev/null || true
            cp -f "$FONT_DIR/Monocraft/"* "$WIN_FONT_DIR/" 2>/dev/null || true

            info "Registering fonts in Windows Registry via PowerShell..."
            powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '
                $fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
                $regPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
                if (Test-Path $fontDir) {
                    Get-ChildItem -Path $fontDir -Include *.ttf,*.otf,*.ttc -Recurse | ForEach-Object {
                        $regName = "$($_.BaseName) (TrueType)"
                        New-ItemProperty -Path $regPath -Name $regName -Value $_.FullName -PropertyType String -Force | Out-Null
                    }
                }
            ' 2>/dev/null || true

            success "Fonts registered in Windows for Windows Terminal, WezTerm, and VS Code!"
        fi
    else
        warn "powershell.exe not accessible from WSL. You can manually install fonts from $FONT_DIR."
    fi
fi

success "Developer font installation complete!"
