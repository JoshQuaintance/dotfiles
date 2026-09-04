# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Homebrew environment (macOS Apple Silicon & Linuxbrew)
if [ -f "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    export C_INCLUDE_PATH="/opt/homebrew/include:$C_INCLUDE_PATH"
    export LIBRARY_PATH="/opt/homebrew/lib:$LIBRARY_PATH"
elif [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Optional Homebrew tool paths (if installed)
[ -d "/opt/homebrew/opt/openjdk@21/bin" ] && export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"
[ -d "/opt/homebrew/opt/python@3.14/bin" ] && export PATH="/opt/homebrew/opt/python@3.14/bin:$PATH"

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder
zstyle ':omz:plugins:eza' 'icons' yes
zstyle ':omz:plugins:eza' 'git-status' yes
zstyle ':omz:plugins:eza' 'hyperlink' yes

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git eza starship)

if [ -f "$ZSH/oh-my-zsh.sh" ]; then
    source "$ZSH/oh-my-zsh.sh"
else
    # Fallback Git prompt if Oh My Zsh is not yet installed
    autoload -Uz vcs_info
    precmd() { vcs_info }
    zstyle ':vcs_info:git:*' formats ' (%b)'
    setopt PROMPT_SUBST
    PROMPT='%F{cyan}%~%F{yellow}${vcs_info_msg_0_}%F{reset} %# '
fi

# Starship Prompt Initialization
if command -v starship &>/dev/null; then
    eval "$(starship init zsh)"
fi

# ==========================================
# User Configuration & Tools
# ==========================================

# Mise (Polyglot Runtime & Node 24 Manager)
if command -v mise &>/dev/null; then
    eval "$(mise activate zsh)"
fi

# NVM (Fallback if used)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Astral Python Tools (uv & ruff completions)
command -v uv &>/dev/null && eval "$(uv generate-shell-completion zsh 2>/dev/null)"
command -v ruff &>/dev/null && eval "$(ruff generate-shell-completion zsh 2>/dev/null)"

# Angular CLI autocompletion
command -v ng &>/dev/null && source <(ng completion script 2>/dev/null)

export BASE="$HOME/Codes"
[ -d "$HOME/Codes/sentinel-service/bin" ] && export PATH="$HOME/Codes/sentinel-service/bin:$PATH"

export STL_VAULT_PROD_ADDR="https://vault.winsupply.com"
export STL_VAULT_DEV_ADDR="https://vault-test.winsupply.com"

# Bun
export BUN_INSTALL="$HOME/.bun"
[ -d "$BUN_INSTALL/bin" ] && export PATH="$BUN_INSTALL/bin:$PATH"
[ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"

# PNPM
if [ -d "$HOME/Library/pnpm" ]; then
    export PNPM_HOME="$HOME/Library/pnpm"
    export PATH="$PNPM_HOME/bin:$PATH"
elif [ -d "$HOME/.local/share/pnpm" ]; then
    export PNPM_HOME="$HOME/.local/share/pnpm"
    export PATH="$PNPM_HOME/bin:$PATH"
fi

# Atuin (Shell History)
[ -f "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"
command -v atuin &>/dev/null && eval "$(atuin init zsh)"

# Zoxide (Smart directory jumper: 'z <folder>')
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# FZF (Fuzzy finder integration)
if command -v fzf &>/dev/null; then
    [ -f "$HOME/.fzf.zsh" ] && source "$HOME/.fzf.zsh"
    source <(fzf --zsh 2>/dev/null) 2>/dev/null || true
fi

# Preferred editor for local and remote sessions
export EDITOR='nvim'
export VISUAL='nvim'

# ==========================================
# Aliases & Shortcuts
# ==========================================
[ -f "$HOME/.aliases" ] && source "$HOME/.aliases"
[ -f "$DOTFILES_DIR/.aliases" ] && [ ! -f "$HOME/.aliases" ] && source "$DOTFILES_DIR/.aliases"

# ==========================================
# Custom Functions
# ==========================================

# ESLint changed .ts files vs origin/develop
esdiff() {
  local files
  files=($(git diff origin/develop...HEAD --name-only --diff-filter=d | grep '\.ts$'))
  if (( $#files == 0 )); then
    echo "No .ts files changed vs origin/develop"
    return 0
  fi
  echo "Checking $#files file(s):"
  printf '  %s\n' $files
  npx eslint $files
}

# Run specific acceptance test
acceptance() {
  local test=$1
  echo "Running test \"$test\""
  npm run test:acceptance:refactored -- --grep "$test"
}

# Quick git clone helper: clone <org/repo>
clone() {
  local repo=$1
  echo "Cloning $repo - git clone git@github.com:$repo.git"
  git clone git@github.com:$repo.git
}

# Edit configurations and reload automatically only if modified
conf() {
  local target="${1:-shell}"
  local target_file=""
  local is_shell_rc=false

  case "$target" in
    shell|"")
      if [ -n "$ZSH_VERSION" ]; then
        target_file="$HOME/.zshrc"
      elif [ -n "$BASH_VERSION" ]; then
        target_file="$HOME/.bashrc"
      else
        target_file="$HOME/.zshrc"
      fi
      is_shell_rc=true
      ;;
    zsh)
      target_file="$HOME/.zshrc"
      is_shell_rc=true
      ;;
    bash)
      target_file="$HOME/.bashrc"
      is_shell_rc=true
      ;;
    alias|aliases)
      target_file="$HOME/.aliases"
      is_shell_rc=true
      ;;
    nvim|vim)
      target_file="$HOME/.config/nvim"
      ;;
    dotfiles|dots)
      target_file="$HOME/Codes/dotfiles"
      ;;
    git)
      target_file="$HOME/.gitconfig"
      ;;
    starship)
      target_file="$HOME/.config/starship.toml"
      ;;
    *)
      if [ -f "$1" ] || [ -d "$1" ]; then
        target_file="$1"
      else
        echo "Unknown config target: $1"
        echo "Usage: conf [shell|alias|nvim|dotfiles|git|starship|<path>]"
        return 1
      fi
      ;;
  esac

  local editor="${EDITOR:-nvim}"
  command -v "$editor" &>/dev/null || editor="nano"

  # If opening a directory, open directly
  if [ -d "$target_file" ]; then
    "$editor" "$target_file"
    return 0
  fi

  [ ! -f "$target_file" ] && touch "$target_file"

  local before_sum
  before_sum=$(cksum "$target_file" 2>/dev/null)

  "$editor" "$target_file"

  local after_sum
  after_sum=$(cksum "$target_file" 2>/dev/null)

  # Only reload if the file was modified and it's a shell rc file
  if [ "$before_sum" != "$after_sum" ]; then
    if [ "$is_shell_rc" = true ]; then
      echo "Changes detected. Sourcing $target_file..."
      source "$target_file"
      echo "✔ Terminal environment updated!"
    else
      echo "✔ Saved changes to $target_file"
    fi
  else
    echo "No changes made."
  fi
}
