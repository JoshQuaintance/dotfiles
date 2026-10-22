# Dotfiles & Dev Setup

A modern, fast, and modular developer workstation setup for macOS, Linux, and WSL.

## Quick Install (Latest Main)

`install.sh` is the unified entry point. Run:

```bash
curl -fsSL https://raw.githubusercontent.com/JoshQuaintance/dotfiles/main/install.sh | bash
```

Follow the interactive prompts to choose your profile (Full Workstation, Server/Minimal, or Custom).

Add `--dry-run` (`-n`) to preview a profile first: it lists each install step, which tools are missing, and which config links would be created, without changing anything:

```bash
./install.sh --dry-run        # or: curl ... | bash -s -- --dry-run
```

---

## Installing from a Specific Branch

To install or test a feature branch (e.g. `feat/python-cli`):

### Option 1: Remote One-Liner (curl)
```bash
curl -fsSL https://raw.githubusercontent.com/JoshQuaintance/dotfiles/<branch>/install.sh | bash -s -- -b <branch>
```
*Or with environment variable:*
```bash
curl -fsSL https://raw.githubusercontent.com/JoshQuaintance/dotfiles/<branch>/install.sh | DOTFILES_BRANCH=<branch> bash
```

### Option 2: Local Git Clone
When run from an existing local clone, `install.sh` automatically detects your active Git branch:
```bash
git clone -b <branch> https://github.com/JoshQuaintance/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

---

## Workstation CLI (`dot`)

The repository includes a Python-powered CLI:

```bash
dot                   # Quick workstation, repo, symlink, and runtime overview (alias: dot status / .s)
dot doctor            # Comprehensive health check across symlinks, tools, and locale (.doctor)
dot doctor --fix      # Auto-heals broken/dangling symlinks (including VS Code configs)
dot test              # Deep integration test suite (JSONC, TOML, headless Neovim, Zsh latency, zsh unit tests) (.test)
dot bench [-n N]      # Profile interactive Zsh startup latency by phase (.bench)
dot clean [-n] [-a]   # Prune stale completion dumps, caches, and old scratch notes (.clean)
dot prune [REF] [-n]  # Remove links, caches & packages deleted since REF (default: before last pull) (.prune)
dot prune --orphans   # ...and offer to uninstall brew packages & mise versions the dotfiles don't declare
dot update --all      # Upstream Git sync + Homebrew & Mise updates + automated test run (.update)
dot link --fix        # Reconcile all declarative configuration symlinks
dot env [-a]          # Audit environment variables, $PATH precedence & shadowed binaries (.env)
dot backup [-l] [-n]  # Snapshot untracked local machine overrides, scratchpads & state (.backup)
dot restore [ARC]     # Restore untracked local machine overrides & state from snapshot (.restore)
```

*Pruning:* after pulling, `dot update` removes what upstream deleted since your previous commit. Symlinks into removed repo files and stale zsh caches (`.zwc`, compdumps) are removed automatically. Homebrew formulae/casks dropped from the `Brewfile` and tools dropped from `config/mise/config.toml` are listed and only uninstalled after you confirm, even with `-y`. `dot update -c` previews the list; `--no-prune` skips it. Run the same cleanup on its own with `dot prune` (e.g. after a manual `git pull`).

*Shell function tests:* `zsh tests/zsh/run.zsh [filter]` runs the unit tests in `tests/zsh/` (each test gets a throwaway `$HOME`); CI runs them along with strict `shellcheck` and `ruff`.

*Note: Shorthand aliases (`.status`, `.doctor`, `.test`, `.bench`, `.clean`, `.prune`, `.check`, `.update`, `.branch`, `.env`, `.backup`, `.restore`) and standalone scripts (`dotdoctor`, `dottest`, `dotcheck`, `dotupdate`) are also available.*

---

## Comma Command Palette (`,`) & Interactive Shell Tools

Every custom shell function is accessible via the `,` prefix convention (with Fish-like autosuggestions, live syntax highlighting, and tab completion whether typed as `,<cmd>` or `, <cmd>`):

```bash
,                     # Open modal-Vim FZF palette of all custom dotfiles commands
, <cmd> [args...]     # Run any custom command directly (e.g. `, pkg`, `, port`, `, gwts`)
,hash <path...>       # Compute MD5, SHA-1, SHA-256 & SHA-512 for files or directories (checksum)
,hashc <p1> <p2>...   # Compare 2+ files/folders for byte-for-byte identity or verify digest (hashc)
,net                  # Network, DNS, gateway, VPN & latency diagnostic card (netinfo)
,pkg / ,brew          # Inspect, upgrade, or uninstall Homebrew, Mise & system packages (fpkg)
,kill / ,ports        # Interactive process & listening TCP port inspector/killer (fkill / port)
wt / gwts / gwtn      # Interactive Git worktree switcher, fleet status table & creator
```

Helper Python executables invoked by shell functions live in `libexec/` (`checksum.py`, `clip_transform.py`, `decode.py`, `strdiff.py`, `wsl_terminal_settings.py`) and are linted alongside `cli/` via `ruff` and `lefthook`.

---

## Bare Linux Install / Containers

On a fresh or minimal Linux install (Ubuntu, Debian, Fedora, or container), ensure `curl` and `sudo` are installed first:

### Ubuntu / Debian
```bash
apt-get update && apt-get install -y curl sudo
curl -fsSL https://raw.githubusercontent.com/JoshQuaintance/dotfiles/main/install.sh | bash
```

### Fedora
```bash
dnf install -y curl sudo
curl -fsSL https://raw.githubusercontent.com/JoshQuaintance/dotfiles/main/install.sh | bash
```

---

## Credits & Attributions

This dotfiles framework builds upon and integrates with numerous exceptional open-source tools, shell libraries, themes, and community projects. Sincere gratitude to all authors and maintainers.

### Upstream Patches & Adaptations

- **[zsh-async](https://github.com/mafredri/zsh-async)** (Mathias Fredriksson) — [BSD-2-Clause / MIT](https://github.com/mafredri/zsh-async/blob/master/LICENSE)
  - `zsh/spaceship-patches.zsh` adapts `async_process_results` to provide a WSL2 pty buffer drain fix and installs a file descriptor 2 (stderr) leak guard ([mafredri/zsh-async#35](https://github.com/mafredri/zsh-async/issues/35)).
- **[Spaceship Prompt](https://github.com/spaceship-prompt/spaceship-prompt)** (Denys Dovhan) — [MIT](https://github.com/spaceship-prompt/spaceship-prompt/blob/master/LICENSE.md)
  - `zsh/spaceship-patches.zsh` includes a subshell and `set -e` directory change hardening patch for `prompt_spaceship_chpwd`.
- **[Catppuccin](https://github.com/catppuccin)** — [MIT](https://github.com/catppuccin/catppuccin/blob/main/LICENSE)
  - The soothing Catppuccin Mocha color palette powers terminal themes across Ghostty (`config/ghostty/config`), Windows Terminal (`config/windows-terminal/settings.json`), Yazi (`config/yazi/theme.toml`), Neovim (`config/nvim/lua/plugins/colorscheme.lua`), Bat (`config/bat/config`), and Eza (`config/eza/theme.yml`).
- **[gitignore.io](https://www.toptal.com/developers/gitignore)** (Toptal) — [MIT / CC BY 3.0](https://github.com/toptal/gitignore.io)
  - Powers interactive `.gitignore` template generation in `bin/genignore` (`gi`).

### Open-Source Tools & Libraries

| Tool / Project | Upstream Repository | License | Role / Description |
|---|---|---|---|
| **Spaceship Prompt** | [spaceship-prompt/spaceship-prompt](https://github.com/spaceship-prompt/spaceship-prompt) | MIT | Powerful, customizable Zsh prompt framework |
| **zsh-async** | [mafredri/zsh-async](https://github.com/mafredri/zsh-async) | BSD-2-Clause / MIT | Asynchronous worker library for Zsh |
| **Catppuccin** | [catppuccin/catppuccin](https://github.com/catppuccin) | MIT | Soothing pastel theme collection for terminal applications |
| **Homebrew** | [Homebrew/brew](https://github.com/Homebrew/brew) | BSD-2-Clause | Package manager for macOS and Linux (`Brewfile`) |
| **ripgrep** | [BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep) | MIT / Unlicense | Ultra-fast recursive line-oriented regex search (`rg`) |
| **fd** | [sharkdp/fd](https://github.com/sharkdp/fd) | Apache-2.0 / MIT | Fast, user-friendly alternative to `find` |
| **fzf** | [junegunn/fzf](https://github.com/junegunn/fzf) | MIT | General-purpose command-line fuzzy finder |
| **bat** | [sharkdp/bat](https://github.com/sharkdp/bat) | Apache-2.0 / MIT | Modern `cat` clone with syntax highlighting and Git integration |
| **eza** | [eza-community/eza](https://github.com/eza-community/eza) | EUPL-1.2 | Feature-rich modern replacement for `ls` |
| **zoxide** | [ajeetdsouza/zoxide](https://github.com/ajeetdsouza/zoxide) | MIT | Smarter `cd` command tracking directory frequency |
| **yazi** | [sxyazi/yazi](https://github.com/sxyazi/yazi) | MIT | Blazing fast asynchronous terminal file manager in Rust |
| **jq** | [jqlang/jq](https://github.com/jqlang/jq) | MIT / CC BY 3.0 | Lightweight and flexible JSON processor |
| **yq** | [mikefarah/yq](https://github.com/mikefarah/yq) | MIT | Portable YAML, JSON, XML, and TOML processor |
| **delta** | [dandavison/delta](https://github.com/dandavison/delta) | MIT | Syntax-highlighting pager for git, diff, and grep output |
| **atuin** | [atuinsh/atuin](https://github.com/atuinsh/atuin) | MIT | SQLite-backed magical shell history with sync capabilities |
| **lazygit** | [jesseduffield/lazygit](https://github.com/jesseduffield/lazygit) | MIT | Terminal UI for git commands |
| **neovim** | [neovim/neovim](https://github.com/neovim/neovim) | Apache-2.0 / Vim | Modern, extensible Vim-based text editor |
| **mise** | [jdx/mise](https://github.com/jdx/mise) | MIT | Polyglot development environment & runtime manager |
| **btop** | [aristocratos/btop](https://github.com/aristocratos/btop) | Apache-2.0 | Responsive terminal resource monitor (CPU, memory, disks) |
| **dust** | [bootandy/dust](https://github.com/bootandy/dust) | Apache-2.0 | Intuitive graphical disk usage analyzer (`du` alternative) |
| **tlrc** | [tldr-pages/tlrc](https://github.com/tldr-pages/tlrc) | MIT | Fast official `tldr` client in Rust for community cheat sheets |
| **tokei** | [XAMPPRocky/tokei](https://github.com/XAMPPRocky/tokei) | Apache-2.0 / MIT | Fast codebase line-of-code and language statistics |
| **hyperfine** | [sharkdp/hyperfine](https://github.com/sharkdp/hyperfine) | Apache-2.0 / MIT | Statistical command-line benchmarking tool |
| **glow** | [charmbracelet/glow](https://github.com/charmbracelet/glow) | MIT | Markdown renderer for the terminal |
| **ouch** | [ouch-org/ouch](https://github.com/ouch-org/ouch) | MIT | Painless compression and decompression CLI |
| **dura** | [tkellogg/dura](https://github.com/tkellogg/dura) | Apache-2.0 / MIT | Background Git snapshot daemon preventing uncommitted work loss |
| **uv** | [astral-sh/uv](https://github.com/astral-sh/uv) | Apache-2.0 / MIT | High-performance Python package and environment manager |
| **shellcheck** | [koalaman/shellcheck](https://github.com/koalaman/shellcheck) | GPL-3.0 | Static analysis and linter for shell scripts |
| **shfmt** | [mvdan/sh](https://github.com/mvdan/sh) | BSD-3-Clause | Shell script parser, formatter, and interpreter |
| **lefthook** | [evilmartians/lefthook](https://github.com/evilmartians/lefthook) | MIT | Fast parallel Git hooks manager |
| **typos** | [crate-ci/typos](https://github.com/crate-ci/typos) | Apache-2.0 / MIT | Low-false-positive source code spell checker |
| **actionlint** | [rhysd/actionlint](https://github.com/rhysd/actionlint) | MIT | Static checker for GitHub Actions workflow files |
| **fzf-tab** | [Aloxaf/fzf-tab](https://github.com/Aloxaf/fzf-tab) | MIT | Rich fzf-driven completion popup for Zsh |
| **zsh-autosuggestions** | [zsh-users/zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) | MIT | Fast Fish-like autosuggestions for Zsh |
| **zsh-syntax-highlighting** | [zsh-users/zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) | BSD-3-Clause | Fish-like real-time syntax highlighting for Zsh |
| **Miracode** | [IdreesInc/Miracode](https://github.com/IdreesInc/Miracode) | OFL-1.1 | Monospaced programming font with pixel aesthetics |
| **Monocraft** | [IdreesInc/Monocraft](https://github.com/IdreesInc/Monocraft) | OFL-1.1 | Pixelated programming font for coding |
| **Fira Code Nerd Font** | [ryanoasis/nerd-fonts](https://github.com/ryanoasis/nerd-fonts) | OFL-1.1 | Monospaced font with programming ligatures & glyphs |
| **JetBrains Mono Nerd Font** | [JetBrains/JetBrainsMono](https://github.com/JetBrains/JetBrainsMono) | Apache-2.0 | Typeface made for developers, patched with Nerd Font glyphs |
