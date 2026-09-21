# Brewfile - Unified declarative package manifest
# Compatible with macOS, Linux (Linuxbrew), and WSL.
#
# Usage:
#   brew bundle                     # Install all packages
#   brew bundle check               # Verify all dependencies are installed
#   brew bundle --file=Brewfile     # Run explicitly

# ----------------------------------------------------------------------
# Core CLI Utilities (Universal: macOS, Linux, WSL)
# ----------------------------------------------------------------------
brew "ripgrep"      # Fast line-oriented regex search tool
brew "fd"           # User-friendly alternative to find
brew "fzf"          # Command-line fuzzy finder
brew "bat"          # Cat clone with syntax highlighting
brew "eza"          # Modern replacement for ls
brew "zoxide"       # Smarter cd command
brew "starship"     # Cross-shell prompt
brew "atuin"        # Magical shell history

# ----------------------------------------------------------------------
# Modern TUI & Terminal Productivity
# ----------------------------------------------------------------------
brew "yazi"         # Terminal file manager
brew "btop"         # Resource monitor (CPU, memory, disks, network)
brew "dust"         # More intuitive du in Rust
brew "fzf-tab"      # Interactive zsh completion menu

# ----------------------------------------------------------------------
# Git & Version Control
# ----------------------------------------------------------------------
brew "git"          # Fast distributed version control
brew "lazygit"      # Terminal UI for git
brew "dura"         # Background automated snapshot daemon for git
brew "neovim"       # Extensible text editor

# ----------------------------------------------------------------------
# macOS GUI Applications & Fonts (Ignored on Linux & WSL)
# ----------------------------------------------------------------------
if OS.mac?
  # GUI Applications (skipped if HOMEBREW_BUNDLE_NO_CASKS=1)
  unless ENV["HOMEBREW_BUNDLE_NO_CASKS"] == "1"
    cask "ghostty"
    cask "visual-studio-code"
  end

  # Developer Fonts (skipped if HOMEBREW_BUNDLE_NO_FONTS=1)
  unless ENV["HOMEBREW_BUNDLE_NO_FONTS"] == "1"
    cask "font-jetbrains-mono-nerd-font"
  end
end
