from dataclasses import dataclass
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

def get_dotfiles_dir() -> Path:
    """Resolve the canonical dotfiles repository root."""
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
        SymlinkEntry(home / ".config" / "starship.toml", "config/starship/starship.toml", "Starship prompt configuration"),
        SymlinkEntry(home / ".config" / "nvim", "config/nvim", "Neovim editor configuration", is_directory=True),
        SymlinkEntry(home / ".config" / "ghostty" / "config", "config/ghostty/config", "Ghostty terminal configuration"),
        SymlinkEntry(home / ".config" / "bat" / "config", "config/bat/config", "Bat syntax viewer configuration"),
        SymlinkEntry(home / ".config" / "eza" / "theme.yml", "config/eza/theme.yml", "Eza modern ls color theme"),
        SymlinkEntry(home / ".config" / "mise" / "config.toml", "config/mise/config.toml", "Mise polyglot runtime manifest"),
        SymlinkEntry(home / ".config" / "yazi", "config/yazi", "Yazi terminal file manager", is_directory=True),
    ]

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
