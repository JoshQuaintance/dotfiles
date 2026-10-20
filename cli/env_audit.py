import os
import shutil
from pathlib import Path
from typing import Optional

from cli.manifest import get_dotfiles_dir
from cli.ui import C_BLUE, C_BOLD, C_GREEN, C_RED, C_RESET, C_YELLOW, format_row, print_header

KEY_BINARIES = ("git", "zsh", "nvim", "python3", "node", "rg", "fd", "fzf", "jq", "gh", "tmux")


def _shorten_home(path_str: str, home_str: str) -> str:
    """Replace leading $HOME prefix with ~ for compact display."""
    if path_str == home_str:
        return "~"
    if path_str.startswith(home_str + os.sep):
        return "~" + path_str[len(home_str):]
    return path_str


def audit_path_entries(path_env: Optional[str] = None) -> list[tuple[str, str, str]]:
    """Audit each entry in $PATH for existence and duplicates.

    Returns a list of (entry_display, status_kind, detail) tuples where
    status_kind is 'ok', 'duplicate', or 'missing'.
    """
    raw = path_env if path_env is not None else os.environ.get("PATH", "")
    entries = [p for p in raw.split(os.pathsep) if p]
    home_str = str(Path.home())
    seen: dict[str, int] = {}
    results: list[tuple[str, str, str]] = []

    for idx, entry in enumerate(entries, start=1):
        disp = _shorten_home(entry, home_str)
        norm = os.path.normpath(entry)
        if norm in seen:
            results.append((f"{idx:2d}. {disp}", "duplicate", f"Duplicate of #{seen[norm]}"))
            continue
        seen[norm] = idx
        p = Path(entry)
        if not p.is_dir():
            results.append((f"{idx:2d}. {disp}", "missing", "Directory does not exist"))
        else:
            results.append((f"{idx:2d}. {disp}", "ok", "Active directory"))
    return results


def find_binary_resolutions(
    binaries: tuple[str, ...] = KEY_BINARIES,
    path_env: Optional[str] = None,
) -> list[tuple[str, list[str]]]:
    """Find all executable matches across $PATH for each binary in `binaries`."""
    raw = path_env if path_env is not None else os.environ.get("PATH", "")
    dirs = [Path(p) for p in raw.split(os.pathsep) if p and Path(p).is_dir()]
    home_str = str(Path.home())
    resolutions: list[tuple[str, list[str]]] = []

    for name in binaries:
        matches: list[str] = []
        seen_paths: set[str] = set()
        for d in dirs:
            candidate = d / name
            if candidate.is_file() and os.access(candidate, os.X_OK):
                norm = os.path.normpath(str(candidate))
                if norm not in seen_paths:
                    seen_paths.add(norm)
                    matches.append(_shorten_home(norm, home_str))
        if matches:
            resolutions.append((name, matches))
    return resolutions


def _audit_env_vars() -> None:
    """Print core shell and workstation environment variable diagnostics."""
    print(f"\n{C_BOLD}1. Core Environment Variables{C_RESET}")
    home_str = str(Path.home())
    dotfiles_dir = str(get_dotfiles_dir())
    editor = os.environ.get("EDITOR", "nvim")
    editor_ok = shutil.which(editor) is not None
    print(
        format_row(
            "EDITOR",
            f"{editor} ({_shorten_home(shutil.which(editor) or 'not found', home_str)})",
            f"{C_GREEN}✔{C_RESET}" if editor_ok else f"{C_YELLOW}⚠{C_RESET}",
        )
    )

    shell_val = os.environ.get("SHELL", "unknown")
    print(format_row("SHELL", shell_val, f"{C_GREEN}✔{C_RESET}"))

    lang_val = os.environ.get("LANG") or os.environ.get("LC_ALL") or "unset"
    lang_ok = "UTF-8" in lang_val.upper() or "UTF8" in lang_val.upper()
    print(format_row("LANG / Locale", lang_val, f"{C_GREEN}✔{C_RESET}" if lang_ok else f"{C_YELLOW}⚠{C_RESET}"))

    term_val = f"{os.environ.get('TERM', 'unknown')} (COLORTERM={os.environ.get('COLORTERM', 'none')})"
    print(format_row("TERM", term_val, f"{C_GREEN}✔{C_RESET}"))

    print(format_row("DOTFILES_DIR", _shorten_home(dotfiles_dir, home_str), f"{C_GREEN}✔{C_RESET}"))

    ssh_sock = os.environ.get("SSH_AUTH_SOCK")
    if ssh_sock:
        sock_exists = Path(ssh_sock).exists()
        print(
            format_row(
                "SSH_AUTH_SOCK",
                _shorten_home(ssh_sock, home_str),
                f"{C_GREEN}✔{C_RESET}" if sock_exists else f"{C_RED}✖{C_RESET}",
            )
        )
    else:
        print(format_row("SSH_AUTH_SOCK", "not set (no active SSH agent)", f"{C_BLUE}➜{C_RESET}"))


def _audit_local_bin_links() -> None:
    """Check ~/.local/bin for broken symlinks."""
    local_bin = Path.home() / ".local" / "bin"
    if not local_bin.is_dir():
        return
    broken = [p.name for p in local_bin.iterdir() if p.is_symlink() and not p.exists()]
    print(f"\n{C_BOLD}4. Local Binary Directory (~/.local/bin){C_RESET}")
    if broken:
        print(format_row("Broken symlinks in ~/.local/bin", ", ".join(broken[:6]), f"{C_YELLOW}⚠{C_RESET}"))
    else:
        print(format_row("~/.local/bin symlinks", "0 broken links", f"{C_GREEN}✔{C_RESET}"))


def run_env_audit(show_all_path: bool = False) -> int:
    """Run a cross-platform environment variable, $PATH, and binary shadowing audit."""
    print_header("Dotfiles Environment \u2014 $PATH & Binary Shadowing Audit")
    _audit_env_vars()

    print(f"\n{C_BOLD}2. $PATH Precedence & Hygiene{C_RESET}")
    path_rows = audit_path_entries()
    dups = [r for r in path_rows if r[1] == "duplicate"]
    missing = [r for r in path_rows if r[1] == "missing"]
    active = [r for r in path_rows if r[1] == "ok"]

    print(
        format_row(
            "$PATH Summary",
            f"{len(active)} active, {len(dups)} duplicate(s), {len(missing)} missing",
            f"{C_GREEN}✔{C_RESET}" if not dups else f"{C_YELLOW}⚠{C_RESET}",
        )
    )

    display_rows = path_rows if show_all_path else path_rows[:12]
    for label, kind, detail in display_rows:
        if kind == "ok":
            icon = f"{C_GREEN}✔{C_RESET}"
        elif kind == "duplicate":
            icon = f"{C_YELLOW}⚠{C_RESET}"
        else:
            icon = f"{C_BLUE}➜{C_RESET}"
        print(format_row(label, detail, icon))

    if not show_all_path and len(path_rows) > 12:
        rem = len(path_rows) - 12
        print(format_row(f"... and {rem} more entries", "Use 'dot env --all' to list all", f"{C_BLUE}➜{C_RESET}"))

    print(f"\n{C_BOLD}3. Binary Resolution & Shadowing{C_RESET}")
    for bin_name, matches in find_binary_resolutions():
        winner = matches[0]
        if len(matches) > 1:
            shadowed = ", ".join(matches[1:3])
            detail = f"{winner} (shadows: {shadowed})"
        else:
            detail = winner
        print(format_row(bin_name, detail, f"{C_GREEN}✔{C_RESET}"))

    _audit_local_bin_links()
    print()
    return 0
