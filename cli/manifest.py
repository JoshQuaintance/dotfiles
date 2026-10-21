"""Declarative manifests for CLI tools, symlinks, and `$PATH` resolution."""

import os
import platform
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

DOT_CONFIG = ".config"
APP_SUPPORT = "Application Support"


@dataclass
class SymlinkEntry:
    """Declarative configuration symlink managed by `dot doctor` and `dot link`."""

    link_path: Path
    rel_target: str
    description: str
    is_directory: bool = False
    required: bool = True


@dataclass
class ToolEntry:
    """Declarative CLI tool entry consumed by `dot doctor` and `dot test`.

    `brew_formula` maps the binary name back to its Homebrew formula in `Brewfile`
    (None when managed outside Homebrew, e.g. system zsh, uv, mise, or macOS /usr/bin/trash).
    """

    bin_name: str
    label: str
    version_cmd: list[str]
    brew_formula: Optional[str] = None
    alt_bin_names: tuple[str, ...] = ()


def _resolve_sevenzip_bin() -> str:
    """Resolve the preferred 7-Zip binary name for the current environment."""
    if shutil.which("7zz"):
        return "7zz"
    if shutil.which("7z"):
        return "7z"
    return "7z" if platform.system() == "Linux" else "7zz"


def get_cli_tool_manifest() -> list[ToolEntry]:
    """Return the canonical catalog of CLI tools audited by `dot doctor`."""
    sevenzip_bin = _resolve_sevenzip_bin()

    return [
        # 1. Core Version Control & Interactive Shell
        ToolEntry("git",        "Git version control",            ["git", "--version"],        "git"),
        ToolEntry("delta",      "git-delta syntax diff pager",    ["delta", "--version"],      "git-delta"),
        ToolEntry("dura",       "dura git snapshot daemon",       ["dura", "--version"],       "dura"),
        ToolEntry("zsh",        "Zsh shell",                      ["zsh", "--version"]),

        # 2. Search, Navigation & Fuzzy Finders
        ToolEntry("rg",         "ripgrep search",                 ["rg", "--version"],         "ripgrep"),
        ToolEntry("fd",         "fd file finder",                 ["fd", "--version"],         "fd"),
        ToolEntry("fzf",        "fzf fuzzy finder",               ["fzf", "--version"],        "fzf"),
        ToolEntry("zoxide",     "zoxide smart cd",                ["zoxide", "--version"],     "zoxide"),
        ToolEntry("eza",        "eza modern ls",                  ["eza", "--version"],        "eza"),
        ToolEntry("atuin",      "Atuin shell history",            ["atuin", "--version"],      "atuin"),

        # 3. File Viewers, Structured Data & Archives
        ToolEntry("bat",        "bat syntax viewer",              ["bat", "--version"],        "bat"),
        ToolEntry("jq",         "jq JSON processor",              ["jq", "--version"],         "jq"),
        ToolEntry("yq",         "yq YAML/TOML processor",         ["yq", "--version"],         "yq"),
        ToolEntry("ouch",       "ouch archive compressor",        ["ouch", "--version"],       "ouch"),
        ToolEntry(
            sevenzip_bin,
            "7-Zip archiver (Yazi previews)",
            [sevenzip_bin, "--help"],
            "sevenzip",
            alt_bin_names=("7z", "7zz", "/usr/bin/7z"),
        ),

        # 4. Runtimes, Editors & TUI Dashboards
        ToolEntry("mise",       "Mise polyglot runtime",          ["mise", "--version"]),
        ToolEntry("nvim",       "Neovim editor",                  ["nvim", "--version"],       "neovim"),
        ToolEntry("yazi",       "Yazi file manager",              ["yazi", "--version"],       "yazi"),
        ToolEntry("lazygit",    "lazygit git terminal UI",        ["lazygit", "--version"],    "lazygit"),
        ToolEntry("btop",       "btop system monitor",            ["btop", "--version"],       "btop"),
        ToolEntry("dust",       "dust disk analyzer",             ["dust", "--version"],       "dust"),

        # 5. Documentation, Benchmarks & Static Analysis
        ToolEntry("tldr",       "tlrc cheat sheets (tldr)",       ["tldr", "--version"],       "tlrc"),
        ToolEntry("tokei",      "tokei codebase statistics",      ["tokei", "--version"],      "tokei"),
        ToolEntry("hyperfine",  "hyperfine CLI benchmark",        ["hyperfine", "--version"],  "hyperfine"),
        ToolEntry("glow",       "glow Markdown renderer",         ["glow", "--version"],       "glow"),
        ToolEntry("shellcheck", "shellcheck static analyzer",     ["shellcheck", "--version"], "shellcheck"),
        ToolEntry("shfmt",      "shfmt shell formatter",          ["shfmt", "--version"],      "shfmt"),
        ToolEntry("trash",      "trash (del alias)",              ["sh", "-c", "command -v trash"]),
        ToolEntry("uv",         "uv Astral Python manager",       ["uv", "--version"]),
        ToolEntry("lefthook",   "lefthook git hooks manager",     ["lefthook", "version"]),
        ToolEntry("typos",      "typos source spell checker",     ["typos", "--version"]),
        ToolEntry("actionlint", "actionlint workflow linter",     ["actionlint", "--version"]),
    ]


def ensure_standard_path() -> None:
    """Ensure Homebrew, Linuxbrew, Mise, Atuin, and ~/.local/bin are in PATH even in non-interactive shells."""
    home = Path.home()
    candidates = [
        home / ".local" / "bin",
        home / "bin",
        Path("/usr/local/bin"),
        Path("/opt/homebrew/bin"),
        Path("/opt/homebrew/sbin"),
        Path("/home/linuxbrew/.linuxbrew/bin"),
        Path("/home/linuxbrew/.linuxbrew/sbin"),
        home / ".atuin" / "bin",
        home / ".cargo" / "bin",
        home / ".local" / "share" / "mise" / "shims",
    ]
    current_parts = os.environ.get("PATH", "").split(os.pathsep)
    prepend = [str(p) for p in candidates if p.is_dir() and str(p) not in current_parts]
    if prepend:
        os.environ["PATH"] = os.pathsep.join(prepend + current_parts)


def get_dotfiles_dir() -> Path:
    """Resolve the canonical dotfiles repository root."""
    ensure_standard_path()
    return Path(__file__).resolve().parent.parent


def get_symlink_manifest() -> list[SymlinkEntry]:
    """Return the complete list of declarative symlinks for the current OS."""
    get_dotfiles_dir()
    home = Path.home()
    config_dir = home / DOT_CONFIG
    app_support_dir = home / "Library" / APP_SUPPORT
    os_type = platform.system()

    entries: list[SymlinkEntry] = [
        # Shell & Git core
        SymlinkEntry(home / ".zshrc",            "zsh/.zshrc",                  "Zsh interactive configuration"),
        SymlinkEntry(home / ".zshenv",           "zsh/.zshenv",                 "Zsh global environment (UTF-8)"),
        SymlinkEntry(home / ".aliases",          "zsh/.aliases",                "Zsh aliases and shortcuts"),
        SymlinkEntry(home / ".gitconfig",        "config/git/.gitconfig",       "Global Git configuration"),
        SymlinkEntry(home / ".gitignore_global", "config/git/.gitignore_global", "Global Git ignore"),

        # ~/.config tools
        SymlinkEntry(config_dir / "spaceship.zsh",      "config/spaceship/spaceship.zsh", "Spaceship prompt configuration", required=False),
        SymlinkEntry(config_dir / "nvim",               "config/nvim",                    "Neovim editor configuration", is_directory=True),
        SymlinkEntry(config_dir / "ghostty" / "config", "config/ghostty/config",          "Ghostty terminal configuration"),
        SymlinkEntry(config_dir / "bat" / "config",     "config/bat/config",              "Bat syntax viewer configuration"),
        SymlinkEntry(config_dir / "eza" / "theme.yml",  "config/eza/theme.yml",           "Eza modern ls color theme"),
        SymlinkEntry(config_dir / "mise" / "config.toml", "config/mise/config.toml",      "Mise polyglot runtime manifest"),
        SymlinkEntry(config_dir / "yazi",               "config/yazi",                    "Yazi terminal file manager", is_directory=True),
        SymlinkEntry(config_dir / "atuin" / "config.toml", "config/atuin/config.toml",    "Atuin shell history settings"),
    ]

    # lazygit ignores ~/.config on macOS unless XDG_CONFIG_HOME is set
    xdg_config = os.environ.get("XDG_CONFIG_HOME")
    if os_type == "Darwin" and not xdg_config:
        lazygit_dir = app_support_dir / "lazygit"
    else:
        lazygit_base = Path(xdg_config) if xdg_config else config_dir
        lazygit_dir = lazygit_base / "lazygit"
    entries.append(SymlinkEntry(lazygit_dir / "config.yml", "config/lazygit/config.yml", "lazygit terminal UI settings"))

    # Visual Studio Code & macOS Ghostty Application Support paths
    if os_type == "Darwin":
        vscode_dir = app_support_dir / "Code" / "User"
        entries.extend([
            SymlinkEntry(vscode_dir / "settings.json",    "config/vscode/settings.json",    "VS Code user settings"),
            SymlinkEntry(vscode_dir / "keybindings.json", "config/vscode/keybindings.json", "VS Code custom keybindings"),
            SymlinkEntry(vscode_dir / "snippets",         "config/vscode/snippets",         "VS Code user snippets", is_directory=True),
            SymlinkEntry(
                app_support_dir / "com.mitchellh.ghostty" / "config",
                "config/ghostty/config",
                "Ghostty Application Support config",
                required=False,
            ),
        ])
    elif os_type == "Linux":
        vscode_dir = config_dir / "Code" / "User"
        entries.extend([
            SymlinkEntry(vscode_dir / "settings.json",    "config/vscode/settings.json",    "VS Code user settings"),
            SymlinkEntry(vscode_dir / "keybindings.json", "config/vscode/keybindings.json", "VS Code custom keybindings"),
            SymlinkEntry(vscode_dir / "snippets",         "config/vscode/snippets",         "VS Code user snippets", is_directory=True),
        ])

    return entries
