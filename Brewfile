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
brew "spaceship"    # Zsh prompt with native async section rendering
brew "atuin"        # Magical shell history

# ----------------------------------------------------------------------
# Modern TUI & Terminal Productivity
# ----------------------------------------------------------------------
brew "yazi"         # Terminal file manager
brew "btop"         # Resource monitor (CPU, memory, disks, network)
brew "dust"         # More intuitive du in Rust
brew "tlrc"         # Official tldr client in Rust (community cheat sheets)
brew "tokei"        # Fast codebase line-of-code & language statistics
brew "hyperfine"    # Statistical command-line benchmarking tool
brew "fzf-tab"      # Interactive zsh completion menu
brew "zsh-autosuggestions"     # Fish-like fast/unobtrusive autosuggestions for zsh
brew "zsh-syntax-highlighting" # Fish-like syntax highlighting for zsh

# ----------------------------------------------------------------------
# Git & Version Control
# ----------------------------------------------------------------------
brew "git"          # Fast distributed version control
brew "git-delta"    # Syntax-highlighting pager for git, diff, and grep output
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
    cask "font-miracode"
    cask "font-fira-code-nerd-font"
    cask "font-monocraft"
    cask "font-jetbrains-mono-nerd-font"
  end
end
