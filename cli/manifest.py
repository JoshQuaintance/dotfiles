from dataclasses import dataclass
import os
from pathlib import Path
import platform
from typing import List

@dataclass
class SymlinkEntry:
    link_path: Path
    rel_target: str
    description: str
    is_directory: bool = False
    required: bool = True

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

def get_symlink_manifest() -> List[SymlinkEntry]:
    """Return the complete list of declarative symlinks for the current OS."""
    dotfiles = get_dotfiles_dir()
    home = Path.home()
    os_type = platform.system()

    entries: List[SymlinkEntry] = [
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
