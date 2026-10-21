import socket
from pathlib import Path
from typing import Optional

from cli.manifest import get_dotfiles_dir
from cli.ui import (
    C_BLUE,
    C_BOLD,
    C_CYAN,
    C_DIM,
    C_GREEN,
    C_MAUVE,
    C_RED,
    C_RESET,
    C_YELLOW,
    ICON_FAIL,
    ICON_OK,
    ICON_WARN,
    print_header,
    run_cmd,
)


def _stage_and_commit_local(dotfiles: Path, message: Optional[str], dry_run: bool) -> None:
    """Inspect local working tree and optionally stage + commit tracked changes."""
    _, status_raw, _ = run_cmd(["git", "-C", str(dotfiles), "status", "--porcelain"])
    dirty_lines = [line for line in status_raw.splitlines() if line.strip()]

    if not dirty_lines:
        print(f"\n{C_BOLD}2. Local Status:{C_RESET} {C_GREEN}{ICON_OK} Clean working tree{C_RESET}")
        return

    print(f"\n{C_BOLD}2. Local Uncommitted Changes:{C_RESET} ({len(dirty_lines)} files)")
    for line in dirty_lines:
        parts = line.strip().split(maxsplit=1)
        st = parts[0] if parts else ""
        path = parts[1] if len(parts) > 1 else ""
        st_color = C_GREEN if "A" in st else (C_YELLOW if "M" in st else C_RED)
        print(f"  {st_color}{st:<2}{C_RESET} {path}")

    if dry_run:
        print(f"\n{C_BLUE}• Dry-run mode: Would stage and commit these changes.{C_RESET}")
        return

    host = socket.gethostname().split(".")[0]
    commit_msg = message or f"chore(sync): update dotfiles [{host}]"
    print(f"\n  {C_DIM}==> Staging tracked & configuration files...{C_RESET}")
    run_cmd(["git", "-C", str(dotfiles), "add", "-u"])
    for folder in ("zsh", "config", "bin", "cli", "install", "tests"):
        if (dotfiles / folder).is_dir():
            run_cmd(["git", "-C", str(dotfiles), "add", folder])

    code, commit_out, err = run_cmd(["git", "-C", str(dotfiles), "commit", "-m", commit_msg])
    if code == 0:
        print(f"  {C_GREEN}{ICON_OK}{C_RESET} Committed: {C_BOLD}{commit_msg}{C_RESET}")
    else:
        notice = err.strip() or commit_out.strip()
        if notice:
            print(f"  {C_DIM}Notice: {notice}{C_RESET}")


def _pull_and_push_remote(dotfiles: Path, branch: str, auto_push: bool) -> int:
    """Fetch origin, rebase incoming commits, and push outgoing commits if requested."""
    code, _, err = run_cmd(["git", "-C", str(dotfiles), "fetch", "origin", branch])
    if code != 0:
        print(f"  {C_YELLOW}{ICON_WARN} Could not reach remote origin: {err.strip()}{C_RESET}")
        return 1

    _, rev_count, _ = run_cmd(
        ["git", "-C", str(dotfiles), "rev-list", "--left-right", "--count", f"HEAD...origin/{branch}"]
    )
    parts = rev_count.strip().split()
    ahead = int(parts[0]) if len(parts) >= 1 and parts[0].isdigit() else 0
    behind = int(parts[1]) if len(parts) >= 2 and parts[1].isdigit() else 0

    print(f"  Commits ahead: {C_CYAN}{ahead}{C_RESET} │ Commits behind: {C_CYAN}{behind}{C_RESET}")

    if behind > 0:
        print(f"  {C_DIM}==> Pulling {behind} remote commit(s) via rebase...{C_RESET}")
        code, out, err = run_cmd(["git", "-C", str(dotfiles), "pull", "--rebase", "origin", branch])
        if code != 0:
            print(f"  {C_RED}{ICON_FAIL} Rebase conflict encountered:{C_RESET}\n{err or out}")
            print(f"  {C_YELLOW}Resolve conflicts in {dotfiles} and run 'git rebase --continue'.{C_RESET}")
            return 1
        print(f"  {C_GREEN}{ICON_OK}{C_RESET} Successfully rebased onto latest origin/{branch}")
    else:
        print(f"  {C_GREEN}{ICON_OK}{C_RESET} Up to date with origin/{branch}")

    if ahead > 0 and auto_push:
        print(f"\n{C_BOLD}4. Pushing {ahead} Local Commit(s)...{C_RESET}")
        code, out, err = run_cmd(["git", "-C", str(dotfiles), "push", "origin", branch])
        if code != 0:
            print(f"  {C_RED}{ICON_FAIL} Push failed: {err.strip() or out.strip()}{C_RESET}")
            return 1
        print(f"  {C_GREEN}{ICON_OK}{C_RESET} Successfully pushed to origin/{branch}")
    elif ahead > 0:
        print(f"\n{C_DIM}Local branch is ahead by {ahead} commit(s). Push with: git push origin {branch}{C_RESET}")

    return 0


def run_sync(
    message: Optional[str] = None,
    dry_run: bool = False,
    auto_push: bool = True,
) -> int:
    dotfiles = get_dotfiles_dir()
    print_header("Dotfiles Synchronizer — Git Repository Sync")

    _, branch, _ = run_cmd(["git", "-C", str(dotfiles), "branch", "--show-current"])
    branch = branch.strip() or "main"
    print(f"\n{C_BOLD}1. Repository & Branch:{C_RESET} {C_MAUVE}{branch}{C_RESET}")

    _stage_and_commit_local(dotfiles, message, dry_run)

    print(f"\n{C_BOLD}3. Checking Remote Updates...{C_RESET}")
    if dry_run:
        print(f"  {C_BLUE}• Dry-run mode: Would fetch and rebase against origin/{branch}.{C_RESET}")
        return 0

    if _pull_and_push_remote(dotfiles, branch, auto_push) != 0:
        return 1

    print(f"\n{C_BOLD}5. Reconciling Configuration Symlinks...{C_RESET}")
    from cli.doctor import compile_zsh_sources, run_doctor
    compile_zsh_sources(dotfiles)
    run_doctor(fix=True)

    print(f"\n{C_GREEN}{ICON_OK} Dotfiles synchronization complete!{C_RESET}\n")
    return 0
