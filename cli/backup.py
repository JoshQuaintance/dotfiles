"""`dot backup` / `dot restore`: snapshot and restore untracked local machine overrides and state."""

import datetime
import os
import socket
import tarfile
from pathlib import Path
from typing import Optional

from cli.ui import C_BLUE, C_BOLD, C_GREEN, C_RED, C_RESET, C_YELLOW, format_row, print_header


def get_backup_dir(home: Optional[Path] = None) -> Path:
    """Return the default directory where local state backups are stored."""
    base_home = home or Path.home()
    xdg_data = os.environ.get("XDG_DATA_HOME")
    data_root = Path(xdg_data) if xdg_data and home is None else (base_home / ".local" / "share")
    return data_root / "dotfiles" / "backups"


def get_backup_candidates(home: Optional[Path] = None) -> list[tuple[str, Path]]:
    """Return existing untracked local override and state paths eligible for snapshot backup."""
    base_home = home or Path.home()
    candidates = [
        ("Zsh local overrides (~/.zshrc.local)", base_home / ".zshrc.local"),
        ("Local aliases (~/.aliases.local)", base_home / ".aliases.local"),
        ("Git local identity (~/.gitconfig.local)", base_home / ".gitconfig.local"),
        ("SSH client config (~/.ssh/config)", base_home / ".ssh" / "config"),
        ("Dotfiles user preferences (~/.config/dotfiles)", base_home / ".config" / "dotfiles"),
        ("Terminal scratchpads (~/.local/share/scratch)", base_home / ".local" / "share" / "scratch"),
        ("Zoxide directory database (~/.local/share/zoxide)", base_home / ".local" / "share" / "zoxide"),
    ]
    return [(label, path) for label, path in candidates if path.exists()]


def _format_size(num_bytes: int) -> str:
    """Format byte size into human-readable string."""
    if num_bytes < 1024:
        return f"{num_bytes} B"
    if num_bytes < 1024 * 1024:
        return f"{num_bytes / 1024:.1f} KB"
    return f"{num_bytes / (1024 * 1024):.1f} MB"


def _path_size(path: Path) -> int:
    """Calculate total size of a file or directory tree."""
    if path.is_file():
        return path.stat().st_size
    total = 0
    for child in path.rglob("*"):
        if child.is_file() and not child.is_symlink():
            total += child.stat().st_size
    return total


def list_backups(backup_dir: Path) -> int:
    """Print available backup archives in reverse chronological order."""
    print_header("Dotfiles Backup \u2014 Local State Archives")
    archives = sorted(backup_dir.glob("dotfiles-backup-*.tar.gz"), reverse=True) if backup_dir.is_dir() else []
    if not archives:
        print(f"  {C_YELLOW}⚠{C_RESET} No backup archives found in {backup_dir}")
        return 0
    for arc in archives:
        sz = _format_size(arc.stat().st_size)
        print(format_row(arc.name, sz, f"{C_GREEN}✔{C_RESET}"))
    return 0


def run_backup(
    output_path: Optional[str] = None,
    dry_run: bool = False,
    list_only: bool = False,
    home: Optional[Path] = None,
) -> int:
    """Create a timestamped .tar.gz snapshot of untracked local machine overrides and state."""
    base_home = home or Path.home()
    backup_dir = get_backup_dir(base_home)
    if list_only:
        return list_backups(backup_dir)

    mode_tag = " [DRY RUN]" if dry_run else ""
    print_header(f"Dotfiles Backup \u2014 Local State Snapshot{mode_tag}")

    items = get_backup_candidates(base_home)
    if not items:
        print(f"  {C_YELLOW}⚠{C_RESET} No local override or state files found to back up.")
        return 0

    print(f"\n{C_BOLD}1. Local State Items{C_RESET}")
    for label, path in items:
        rel = path.relative_to(base_home)
        sz = _format_size(_path_size(path))
        print(format_row(label, f"~/{rel} ({sz})", f"{C_GREEN}✔{C_RESET}"))

    host = socket.gethostname().split(".")[0] or "host"
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = Path(output_path).expanduser() if output_path else (backup_dir / f"dotfiles-backup-{host}-{ts}.tar.gz")

    print(f"\n{C_BOLD}2. Archive Target{C_RESET}")
    if dry_run:
        print(format_row("Would create archive", str(dest), f"{C_BLUE}➜{C_RESET}"))
        return 0

    dest.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(dest, "w:gz") as tar:
        for _label, path in items:
            rel_name = str(path.relative_to(base_home))
            tar.add(path, arcname=rel_name, recursive=True)
    os.chmod(dest, 0o600)

    arc_size = _format_size(dest.stat().st_size)
    print(format_row("Created snapshot (0600)", f"{dest} ({arc_size})", f"{C_GREEN}✔{C_RESET}"))
    return 0


def _validate_tar_members(members: list[tarfile.TarInfo], base_home: Path) -> bool:
    """Ensure no tar archive member escapes base_home via path traversal."""
    resolved_home = base_home.resolve()
    for member in members:
        if member.name.startswith("/") or ".." in Path(member.name).parts:
            return False
        target = (resolved_home / member.name).resolve()
        if resolved_home not in target.parents and target != resolved_home:
            return False
    return True


def run_restore(
    archive_path: Optional[str] = None,
    dry_run: bool = False,
    home: Optional[Path] = None,
) -> int:
    """Restore local overrides and state from the latest or specified backup archive."""
    base_home = home or Path.home()
    backup_dir = get_backup_dir(base_home)

    if archive_path:
        src = Path(archive_path).expanduser()
    else:
        archives = sorted(backup_dir.glob("dotfiles-backup-*.tar.gz"), reverse=True) if backup_dir.is_dir() else []
        if not archives:
            print(f"{C_RED}✖ No backup archives found in {backup_dir}.{C_RESET}")
            return 1
        src = archives[0]

    if not src.is_file():
        print(f"{C_RED}✖ Backup archive not found: {src}{C_RESET}")
        return 1

    mode_tag = " [DRY RUN]" if dry_run else ""
    print_header(f"Dotfiles Restore \u2014 Local State Snapshot{mode_tag}")
    print(format_row("Source archive", str(src), f"{C_BLUE}➜{C_RESET}"))

    with tarfile.open(src, "r:gz") as tar:
        members = tar.getmembers()
        if not _validate_tar_members(members, base_home):
            print(f"{C_RED}✖ Refusing to extract archive with unsafe relative paths.{C_RESET}")
            return 1
        for member in members:
            action = "Would restore" if dry_run else "Restored"
            print(format_row(action, f"~/{member.name}", f"{C_GREEN}✔{C_RESET}"))
        if not dry_run:
            tar.extractall(path=base_home)  # nosec B202 - validated by _validate_tar_members

    return 0
