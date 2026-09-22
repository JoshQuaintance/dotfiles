# Dotfiles & Dev Setup

A modern, fast, and modular developer workstation setup for macOS, Linux, and WSL.

## Quick Install (Latest Main)

`install.sh` is the unified entry point. Run:

```bash
curl -fsSL https://raw.githubusercontent.com/JoshQuaintance/dotfiles/main/install.sh | bash
```

Follow the interactive prompts to choose your profile (Full Workstation, Server/Minimal, or Custom).

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

The repository includes a Python-powered CLI running in an isolated `uv` virtual environment (`~/.dotfiles/.venv`):

```bash
dot doctor            # Comprehensive health check across symlinks, tools, and locale
dot doctor --fix      # Auto-heals broken/dangling symlinks (including VS Code configs)
dot test              # Deep integration test suite (JSONC, TOML, headless Neovim, Zsh latency)
dot update --all      # Upstream Git sync + Homebrew & Mise updates + automated test run
```

*Note: Backward-compatible aliases `dotdoctor`, `dottest`, and `dotupdate` are also available.*

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
