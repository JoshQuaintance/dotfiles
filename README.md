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
```

*Pruning:* after pulling, `dot update` removes what upstream deleted since your previous commit. Symlinks into removed repo files and stale zsh caches (`.zwc`, compdumps) are removed automatically. Homebrew formulae/casks dropped from the `Brewfile` and tools dropped from `config/mise/config.toml` are listed and only uninstalled after you confirm, even with `-y`. `dot update -c` previews the list; `--no-prune` skips it. Run the same cleanup on its own with `dot prune` (e.g. after a manual `git pull`).

*Shell function tests:* `zsh tests/zsh/run.zsh [filter]` runs the unit tests in `tests/zsh/` (each test gets a throwaway `$HOME`); CI runs them along with strict `shellcheck` and `ruff`.

*Note: Shorthand aliases (`.status`, `.doctor`, `.test`, `.bench`, `.clean`, `.prune`, `.check`, `.update`, `.branch`) and standalone scripts (`dotdoctor`, `dottest`, `dotcheck`, `dotupdate`) are also available.*

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
