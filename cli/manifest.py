import os
import platform
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class SymlinkEntry:
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


def get_cli_tool_manifest() -> list[ToolEntry]:
    """Return the canonical catalog of CLI tools audited by `dot doctor`."""
    return [
        ToolEntry("git", "Git version control", ["git", "--version"], "git"),
        ToolEntry("delta", "git-delta syntax diff pager", ["delta", "--version"], "git-delta"),
        ToolEntry("zsh", "Zsh shell", ["zsh", "--version"]),
        ToolEntry("rg", "ripgrep search", ["rg", "--version"], "ripgrep"),
        ToolEntry("fd", "fd file finder", ["fd", "--version"], "fd"),
        ToolEntry("fzf", "fzf fuzzy finder", ["fzf", "--version"], "fzf"),
        ToolEntry("zoxide", "zoxide smart cd", ["zoxide", "--version"], "zoxide"),
        ToolEntry("eza", "eza modern ls", ["eza", "--version"], "eza"),
        ToolEntry("atuin", "Atuin shell history", ["atuin", "--version"], "atuin"),
        ToolEntry("bat", "bat syntax viewer", ["bat", "--version"], "bat"),
        ToolEntry("jq", "jq JSON processor", ["jq", "--version"], "jq"),
        ToolEntry("yq", "yq YAML/TOML processor", ["yq", "--version"], "yq"),
        ToolEntry("ouch", "ouch archive compressor", ["ouch", "--version"], "ouch"),
        ToolEntry("7zz", "7-Zip archiver (Yazi previews)", ["7zz", "--help"], "sevenzip"),
        ToolEntry("mise", "Mise polyglot runtime", ["mise", "--version"]),
        ToolEntry("nvim", "Neovim editor", ["nvim", "--version"], "neovim"),
        ToolEntry("yazi", "Yazi file manager", ["yazi", "--version"], "yazi"),
        ToolEntry("dust", "dust disk analyzer", ["dust", "--version"], "dust"),
        ToolEntry("btop", "btop system monitor", ["btop", "--version"], "btop"),
        ToolEntry("tldr", "tlrc cheat sheets (tldr)", ["tldr", "--version"], "tlrc"),
        ToolEntry("tokei", "tokei codebase statistics", ["tokei", "--version"], "tokei"),
        ToolEntry("hyperfine", "hyperfine CLI benchmark", ["hyperfine", "--version"], "hyperfine"),
        ToolEntry("lazygit", "lazygit git terminal UI", ["lazygit", "--version"], "lazygit"),
        ToolEntry("glow", "glow Markdown renderer", ["glow", "--version"], "glow"),
        ToolEntry("shellcheck", "shellcheck static analyzer", ["shellcheck", "--version"], "shellcheck"),
        ToolEntry("shfmt", "shfmt shell formatter", ["shfmt", "--version"], "shfmt"),
        ToolEntry("trash", "trash (del alias)", ["sh", "-c", "command -v trash"]),
        ToolEntry("uv", "uv Astral Python manager", ["uv", "--version"]),
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
    os_type = platform.system()

    entries: list[SymlinkEntry] = [
        # Shell & Git core
        SymlinkEntry(home / ".zshrc", "zsh/.zshrc", "Zsh interactive configuration"),
        SymlinkEntry(home / ".zshenv", "zsh/.zshenv", "Zsh global environment (UTF-8)"),
        SymlinkEntry(home / ".aliases", "zsh/.aliases", "Zsh aliases and shortcuts"),
        SymlinkEntry(home / ".gitconfig", "config/git/.gitconfig", "Global Git configuration"),
        SymlinkEntry(home / ".gitignore_global", "config/git/.gitignore_global", "Global Git ignore"),

        # ~/.config tools
        SymlinkEntry(home / ".config" / "spaceship.zsh", "config/spaceship/spaceship.zsh", "Spaceship prompt configuration", required=False),
        SymlinkEntry(home / ".config" / "nvim", "config/nvim", "Neovim editor configuration", is_directory=True),
        SymlinkEntry(home / ".config" / "ghostty" / "config", "config/ghostty/config", "Ghostty terminal configuration"),
        SymlinkEntry(home / ".config" / "bat" / "config", "config/bat/config", "Bat syntax viewer configuration"),
        SymlinkEntry(home / ".config" / "eza" / "theme.yml", "config/eza/theme.yml", "Eza modern ls color theme"),
        SymlinkEntry(home / ".config" / "mise" / "config.toml", "config/mise/config.toml", "Mise polyglot runtime manifest"),
        SymlinkEntry(home / ".config" / "yazi", "config/yazi", "Yazi terminal file manager", is_directory=True),
        SymlinkEntry(home / ".config" / "atuin" / "config.toml", "config/atuin/config.toml", "Atuin shell history settings"),
    ]

    # lazygit ignores ~/.config on macOS unless XDG_CONFIG_HOME is set
    xdg_config = os.environ.get("XDG_CONFIG_HOME")
    if os_type == "Darwin" and not xdg_config:
        lazygit_dir = home / "Library" / "Application Support" / "lazygit"
    else:
        lazygit_dir = Path(xdg_config) if xdg_config else home / ".config"
        lazygit_dir = lazygit_dir / "lazygit"
    entries.append(SymlinkEntry(lazygit_dir / "config.yml", "config/lazygit/config.yml", "lazygit terminal UI settings"))

    # Visual Studio Code configurations
    if os_type == "Darwin":
        vscode_dir = home / "Library" / "Application Support" / "Code" / "User"
        entries.extend([
            SymlinkEntry(vscode_dir / "settings.json", "config/vscode/settings.json", "VS Code user settings"),
            SymlinkEntry(vscode_dir / "keybindings.json", "config/vscode/keybindings.json", "VS Code custom keybindings"),
            SymlinkEntry(vscode_dir / "snippets", "config/vscode/snippets", "VS Code user snippets", is_directory=True),
            # Ghostty macOS application support fallback
            SymlinkEntry(
                home / "Library" / "Application Support" / "com.mitchellh.ghostty" / "config",
                "config/ghostty/config",
                "Ghostty Application Support config",
                required=False
            ),
        ])
    elif os_type == "Linux":
        vscode_dir = home / ".config" / "Code" / "User"
        entries.extend([
            SymlinkEntry(vscode_dir / "settings.json", "config/vscode/settings.json", "VS Code user settings"),
            SymlinkEntry(vscode_dir / "keybindings.json", "config/vscode/keybindings.json", "VS Code custom keybindings"),
            SymlinkEntry(vscode_dir / "snippets", "config/vscode/snippets", "VS Code user snippets", is_directory=True),
        ])

    return entries
