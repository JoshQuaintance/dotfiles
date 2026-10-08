import contextlib
import os
import shutil
import socket
import subprocess
from pathlib import Path

from cli.manifest import get_dotfiles_dir
from cli.ui import (
    C_BOLD,
    C_DIM,
    C_GREEN,
    C_RESET,
    C_YELLOW,
    ICON_OK,
    print_header,
)
from cli.ui import (
    ICON_BULLET as ICON_INFO,
)


def path_size(path: Path) -> int:
    """Calculate byte size of a file or directory tree safely."""
    try:
        if path.is_symlink() or path.is_file():
            return path.lstat().st_size
        if path.is_dir():
            total = 0
            for root, _, files in os.walk(path):
                for f in files:
                    fp = Path(root) / f
                    with contextlib.suppress(OSError):
                        total += fp.lstat().st_size
            return total
    except OSError:
        pass
    return 0


def fmt_bytes(num: int) -> str:
    """Format byte count into human-readable string."""
    val = float(num)
    for unit in ["B", "KB", "MB", "GB"]:
        if val < 1024.0 or unit == "GB":
            if unit == "B":
                return f"{int(val)} {unit}"
            return f"{val:.1f} {unit}"
        val /= 1024.0
    return f"{int(num)} B"


def remove_target(target: Path, dry_run: bool) -> int:
    """Remove a file or directory and return reclaimed bytes."""
    sz = path_size(target)
    if not dry_run:
        try:
            if target.is_dir() and not target.is_symlink():
                shutil.rmtree(target, ignore_errors=True)
            else:
                target.unlink(missing_ok=True)
        except OSError:
            return 0
    return sz


def get_active_zsh_version() -> str:
    if not shutil.which("zsh"):
        return ""
    try:
        res = subprocess.run(["zsh", "-c", "printf '%s' $ZSH_VERSION"], capture_output=True, text=True, timeout=3, check=False)
        return res.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def run_clean(dry_run: bool = False, clean_all: bool = False) -> int:
    dotfiles = get_dotfiles_dir()
    home = Path.home()
    reclaimed_total = 0
    cleaned_items: list[tuple[str, str]] = []

    mode_tag = " [DRY RUN]" if dry_run else ""
    print_header(f"Dotfiles Cleaner \u2014 Cache & State Pruner{mode_tag}")
    print()

    # 1. Stale ~/.zcompdump* files (keep active host + zsh version dump & its .zwc)
    short_host = socket.gethostname().split(".")[0]
    zsh_ver = get_active_zsh_version()
    active_dump = f".zcompdump-{short_host}-{zsh_ver}" if zsh_ver else ""
    active_keep = {active_dump, f"{active_dump}.zwc"} if active_dump else set()

    zcomp_bytes = 0
    zcomp_count = 0
    for item in home.glob(".zcompdump*"):
        if active_keep and item.name in active_keep:
            continue
        zcomp_bytes += remove_target(item, dry_run)
        zcomp_count += 1

    if zcomp_count > 0:
        reclaimed_total += zcomp_bytes
        cleaned_items.append(("Stale Zsh completion dumps", f"{zcomp_count} file(s) ({fmt_bytes(zcomp_bytes)})"))
    else:
        print(f"  {C_GREEN}{ICON_OK}{C_RESET} {'Zsh completion dumps':<42} {C_DIM}Clean (only active dump present){C_RESET}")

    # 2. Cached completion directories (~/.cache/zsh/zcompcache & ~/.cache/ng_completion.zsh)
    cache_home = Path(os.environ.get("XDG_CACHE_HOME", str(home / ".cache")))
    comp_caches = [
        cache_home / "zsh" / "zcompcache",
        cache_home / "ng_completion.zsh",
    ]
    cache_bytes = 0
    cache_count = 0
    for cpath in comp_caches:
        if cpath.exists():
            cache_bytes += remove_target(cpath, dry_run)
            cache_count += 1

    if cache_count > 0:
        reclaimed_total += cache_bytes
        cleaned_items.append(("Shell completion cache", f"{cache_count} item(s) ({fmt_bytes(cache_bytes)})"))
    else:
        print(f"  {C_GREEN}{ICON_OK}{C_RESET} {'Shell completion cache':<42} {C_DIM}Clean{C_RESET}")

    # 3. Oversized Neovim state logs (> 5 MB)
    nvim_state = Path(os.environ.get("XDG_STATE_HOME", str(home / ".local" / "state"))) / "nvim"
    nvim_bytes = 0
    nvim_logs = 0
    if nvim_state.is_dir():
        for log_file in nvim_state.glob("*.log"):
            sz = path_size(log_file)
            if sz > 5 * 1024 * 1024:
                nvim_bytes += remove_target(log_file, dry_run)
                nvim_logs += 1

    if nvim_logs > 0:
        reclaimed_total += nvim_bytes
        cleaned_items.append(("Oversized Neovim state logs (>5MB)", f"{nvim_logs} log(s) ({fmt_bytes(nvim_bytes)})"))
    else:
        print(f"  {C_GREEN}{ICON_OK}{C_RESET} {'Neovim state logs':<42} {C_DIM}All logs under 5 MB{C_RESET}")

    # 4. Temporary scratch/diff files in /tmp and $TMPDIR
    tmp_dirs = {Path("/tmp")}
    env_tmp = os.environ.get("TMPDIR")
    if env_tmp:
        tmp_dirs.add(Path(env_tmp))

    tmp_bytes = 0
    tmp_count = 0
    for tdir in tmp_dirs:
        if not tdir.is_dir():
            continue
        for pattern in ("strdiff-left.*", "strdiff-right.*", "sdiff-left.*", "sdiff-right.*", "yazi-cwd.*", "test-smoke-*"):
            for match in tdir.glob(pattern):
                tmp_bytes += remove_target(match, dry_run)
                tmp_count += 1

    if tmp_count > 0:
        reclaimed_total += tmp_bytes
        cleaned_items.append(("Orphaned temp scratch buffers", f"{tmp_count} item(s) ({fmt_bytes(tmp_bytes)})"))
    else:
        print(f"  {C_GREEN}{ICON_OK}{C_RESET} {'Temporary scratch files':<42} {C_DIM}Clean{C_RESET}")

    # 5. Legacy ~/.oh-my-zsh directory
    omz_dir = home / ".oh-my-zsh"
    if omz_dir.exists():
        omz_sz = path_size(omz_dir)
        if clean_all:
            reclaimed_total += remove_target(omz_dir, dry_run)
            cleaned_items.append(("Legacy ~/.oh-my-zsh directory", fmt_bytes(omz_sz)))
        else:
            print(
                f"  {C_YELLOW}{ICON_INFO}{C_RESET} {'Legacy ~/.oh-my-zsh present':<42} "
                f"{C_YELLOW}{fmt_bytes(omz_sz)} (pass -a/--all to remove){C_RESET}"
            )

    # 6. Package manager cache pruning (--all)
    if clean_all:
        if shutil.which("uv"):
            if dry_run:
                cleaned_items.append(("Astral uv cache", "Would run 'uv cache prune'"))
            else:
                res = subprocess.run(["uv", "cache", "prune"], capture_output=True, text=True, check=False)
                if res.returncode == 0:
                    cleaned_items.append(("Astral uv cache", "Pruned via 'uv cache prune'"))

        if shutil.which("brew"):
            if dry_run:
                cleaned_items.append(("Homebrew cache", "Would run 'brew cleanup --prune=7'"))
            else:
                res = subprocess.run(["brew", "cleanup", "--prune=7"], capture_output=True, text=True, check=False)
                if res.returncode == 0:
                    cleaned_items.append(("Homebrew cache", "Pruned via 'brew cleanup --prune=7'"))

    # 7. Dotfiles Python __pycache__ (cleaned last)
    pycache_dir = dotfiles / "cli" / "__pycache__"
    if pycache_dir.is_dir():
        py_sz = remove_target(pycache_dir, dry_run)
        reclaimed_total += py_sz
        cleaned_items.append(("Dotfiles CLI __pycache__", fmt_bytes(py_sz)))

    for label, detail in cleaned_items:
        action = "Would clean" if dry_run else "Cleaned"
        print(f"  {C_GREEN}{ICON_OK}{C_RESET} {f'{action}: {label}':<42} {C_GREEN}{detail}{C_RESET}")

    verb = "Would reclaim" if dry_run else "Reclaimed"
    print(f"\n{C_BOLD}Summary:{C_RESET} {len(cleaned_items)} category(s) processed \u2022 {C_GREEN}{verb} {fmt_bytes(reclaimed_total)}{C_RESET}\n")
    return 0
