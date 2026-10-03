# ==============================================================================
# Spaceship Prompt Configuration (Native Zsh Async Prompt)
# Docs: https://spaceship-prompt.sh/config/prompt/
# ==============================================================================

# Core Prompt Behavior
SPACESHIP_PROMPT_ASYNC=true
SPACESHIP_PROMPT_ADD_NEWLINE=true
SPACESHIP_PROMPT_SEPARATE_LINE=true
SPACESHIP_PROMPT_FIRST_PREFIX_SHOW=false
SPACESHIP_PROMPT_PREFIXES_SHOW=true
SPACESHIP_PROMPT_SUFFIXES_SHOW=true
SPACESHIP_PROMPT_DEFAULT_PREFIX="via "
SPACESHIP_PROMPT_DEFAULT_SUFFIX=" "

# Curated Section Order — only sections actually used; trimmed to reduce async worker queue
# (single zpty worker serialises all jobs, so fewer jobs = faster streaming)
SPACESHIP_PROMPT_ORDER=(
  user           # Username (only when root or SSH)
  dir            # Current directory (repo-root aware)
  host           # Hostname (only when SSH)
  git            # Git branch + git status + git commit
  package        # Package version (npm, cargo, maven, gradle, pyproject)
  node           # Node.js runtime
  bun            # Bun runtime
  python         # Python runtime
  venv           # Python virtualenv
  java           # Java runtime
  kotlin         # Kotlin runtime
  rust           # Rust toolchain
  aws            # AWS profile
  gcloud         # Google Cloud configuration
  exec_time      # Execution time of last command (>= 2s)
  async          # Subtle indicator (…) while background sections are still loading
  line_sep       # Line break
  battery        # Battery indicator (when low)
  jobs           # Background jobs indicator (✦)
  exit_code      # Non-zero exit code
  sudo           # Active sudo indicator
  char           # Prompt character (❯ in Insert mode, ❮ in Normal mode)
)

# Directory
SPACESHIP_DIR_TRUNC=3
SPACESHIP_DIR_TRUNC_REPO=true
SPACESHIP_DIR_COLOR="blue"
SPACESHIP_DIR_LOCK_SYMBOL=" 󰌾"

# Git
SPACESHIP_GIT_SYMBOL="  "
SPACESHIP_GIT_BRANCH_COLOR="magenta"
SPACESHIP_GIT_STATUS_COLOR="red"

# Package (enable version display even in private package.json repos)
SPACESHIP_PACKAGE_SYMBOL="󰏗 "
SPACESHIP_PACKAGE_SHOW_PRIVATE=true

# Runtimes & Languages (Nerd Font glyphs)
SPACESHIP_NODE_SYMBOL="󰎙 "
SPACESHIP_BUN_SYMBOL=" "
SPACESHIP_PYTHON_SYMBOL="󰌠 "
SPACESHIP_JAVA_SYMBOL=" "
SPACESHIP_KOTLIN_SYMBOL=" "
SPACESHIP_RUST_SYMBOL="󱘗 "

# Cloud (Nerd Font glyphs)
SPACESHIP_AWS_SYMBOL="󰼪 "
SPACESHIP_GCLOUD_SYMBOL="󱇶 "

# Prompt Character (integrated with zsh/vi-mode.zsh cursor & mode toggle)
SPACESHIP_CHAR_SYMBOL="❯ "
SPACESHIP_CHAR_SYMBOL_SUCCESS="❯ "
SPACESHIP_CHAR_SYMBOL_FAILURE="❯ "
SPACESHIP_CHAR_COLOR_SUCCESS="green"
SPACESHIP_CHAR_COLOR_FAILURE="red"
