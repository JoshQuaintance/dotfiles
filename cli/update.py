"""`dot update`: check, pull, reconcile, and upgrade dotfiles, Homebrew, and Mise tools."""

import shutil
import subprocess
import sys
from pathlib import Path

from cli.doctor import DoctorReport, check_and_heal_symlinks, check_cli_tools, compile_zsh_sources
from cli.manifest import get_dotfiles_dir
from cli.prune import apply_prune, plan_prune, preview_prune
from cli.test import run_tests
from cli.ui import (
    C_BLUE,
    C_BOLD,
    C_CYAN,
    C_GREEN,
    C_RED,
    C_RESET,
    C_YELLOW,
    run_cmd,
)

GIT_LOG_FMT = "--format=  %C(yellow)%h%Creset %C(cyan)%cr%Creset %C(bold)%s%Creset %C(dim)(%an)%Creset"


def update_brew(auto_apply: bool = False) -> None:
    """Update Homebrew formulas and audit missing CLI tools."""
    if not shutil.which("brew"):
        return
    print(f"\n{C_BLUE}==>{C_RESET} Updating Homebrew formulas and packages...")
    subprocess.run(["brew", "update"], check=False)
    subprocess.run(["brew", "upgrade"], check=False)
    print(f"{C_GREEN}✔{C_RESET} Homebrew packages updated successfully!")

    print(f"\n{C_BLUE}==>{C_RESET} Auditing workstation CLI tools...")
    report = DoctorReport()
    check_cli_tools(report, fix=auto_apply)


def update_mise() -> None:
    """Upgrade Mise-managed tools and runtimes."""
    if not shutil.which("mise"):
        return
    print(f"\n{C_BLUE}==>{C_RESET} Upgrading Mise tools and runtimes...")
    subprocess.run(["mise", "upgrade"], check=False)
    print(f"{C_GREEN}✔{C_RESET} Mise tools upgraded successfully!")


def prompt_user(prompt: str, default: str = "y") -> str:
    """Prompt the user on stdin with a fallback default on EOF/interrupt."""
    try:
        res = input(prompt)
        return res.strip() or default
    except (EOFError, KeyboardInterrupt):
        return default


def _pull_and_reconcile(dotfiles: Path, current_branch: str, prune: bool) -> bool:
    """Pull remote changes with rebase, heal symlinks, compile Zsh, and prune deleted upstream items."""
    print(f"{C_BLUE}==>{C_RESET} Pulling updates via git pull --rebase...")
    _, old_head, _ = run_cmd(["git", "-C", str(dotfiles), "rev-parse", "HEAD"])
    code, _, _ = run_cmd(["git", "-C", str(dotfiles), "pull", "--rebase", "origin", current_branch], timeout=120)
    if code != 0:
        print(f"{C_RED}✖ Git pull failed. Please check {dotfiles}{C_RESET}", file=sys.stderr)
        return False

    _, new_head, _ = run_cmd(["git", "-C", str(dotfiles), "rev-parse", "--short", "HEAD"])
    print(f"{C_GREEN}✔{C_RESET} Dotfiles successfully updated to {C_CYAN}{new_head}{C_RESET}!")

    check_and_heal_symlinks(DoctorReport(), dotfiles, fix=True)
    compile_zsh_sources(dotfiles)
    if prune:
        apply_prune(dotfiles, plan_prune(dotfiles, old_head, "HEAD"))
    return True


def _inspect_git_state(dotfiles: Path) -> tuple[str, str, int, int, bool]:
    """Return (current_branch, upstream, behind, ahead, is_dirty) for the repository."""
    _, current_branch, _ = run_cmd(["git", "-C", str(dotfiles), "branch", "--show-current"])
    current_branch = current_branch or "main"

    _, upstream, _ = run_cmd(["git", "-C", str(dotfiles), "rev-parse", "--abbrev-ref", "@{u}"])
    upstream = upstream or f"origin/{current_branch}"

    _, behind_str, _ = run_cmd(["git", "-C", str(dotfiles), "rev-list", "--count", f"HEAD..{upstream}"])
    _, ahead_str, _ = run_cmd(["git", "-C", str(dotfiles), "rev-list", "--count", f"{upstream}..HEAD"])
    behind = int(behind_str) if behind_str.isdigit() else 0
    ahead = int(ahead_str) if ahead_str.isdigit() else 0

    _, status, _ = run_cmd(["git", "-C", str(dotfiles), "status", "--porcelain"])
    return current_branch, upstream, behind, ahead, bool(status)


def _handle_incoming_commits(
    dotfiles: Path,
    git_state: tuple[str, str, int, int, bool],
    *,
    check_only: bool,
    interactive: bool,
    prune: bool,
) -> tuple[int, bool]:
    """Handle available upstream commits; return (exit_code_or_neg1_to_continue, updated_git)."""
    current_branch, upstream, behind, _ahead, is_dirty = git_state
    print(f"{C_YELLOW}⬇ {behind} update(s) available for your dotfiles from {upstream}:{C_RESET}\n")
    subprocess.run(["git", "-C", str(dotfiles), "log", GIT_LOG_FMT, f"HEAD..{upstream}"], check=False)
    print()

    if check_only:
        if prune:
            _, old_head, _ = run_cmd(["git", "-C", str(dotfiles), "rev-parse", "HEAD"])
            preview_prune(dotfiles, old_head, upstream)
        print("Run 'dot update' to pull and apply these updates.")
        return 0, False

    if is_dirty:
        print(f"{C_YELLOW}⚠ You have uncommitted changes in {dotfiles}. Please commit or stash them before updating.{C_RESET}")
        subprocess.run(["git", "-C", str(dotfiles), "status", "-s"], check=False)
        return 1, False

    if interactive:
        ans = prompt_user("Would you like to pull and apply updates now? [Y/n]: ", default="y")
        if ans.lower().startswith("n"):
            print("Updates postponed.")
            return -1, False

    if not _pull_and_reconcile(dotfiles, current_branch, prune):
        return 1, False
    return -1, True


def _run_post_update_hooks(auto_apply: bool, update_all: bool, test_after: bool, updated_git: bool) -> None:
    """Run optional Homebrew/Mise upgrades and post-update integration tests."""
    if update_all:
        update_brew(auto_apply=True)
        update_mise()
        run_tests()
    elif not auto_apply:
        ans = prompt_user("\nWould you also like to update Homebrew packages and Mise runtimes? [y/N]: ", default="n")
        if ans.lower().startswith("y"):
            update_brew(auto_apply=False)
            update_mise()
            run_tests()
    elif test_after:
        run_tests()

    if updated_git:
        print(f"\n{C_CYAN}💡 Run 'sz' to reload your active shell session.{C_RESET}")


def _preview_incoming_diff(dotfiles: Path, upstream: str, behind: int) -> int:
    """Preview commit log and full diff for incoming changes without applying."""
    if behind == 0:
        print(f"{C_GREEN}✔ Dotfiles are already up to date with {C_BOLD}{upstream}{C_RESET}. No incoming changes.")
        return 0
    print(f"\n{C_BOLD}Incoming Commits from {upstream} ({behind} new):{C_RESET}")
    subprocess.run(["git", "-C", str(dotfiles), "log", GIT_LOG_FMT, f"HEAD..{upstream}"], check=False)
    print(f"\n{C_BOLD}File Changes Summary:{C_RESET}")
    subprocess.run(["git", "-C", str(dotfiles), "diff", "--stat", f"HEAD..{upstream}"], check=False)
    print(f"\n{C_BOLD}Detailed Patch Preview:{C_RESET}")
    subprocess.run(["git", "-C", str(dotfiles), "diff", f"HEAD..{upstream}"], check=False)
    return 0


def _tools_update(auto_apply: bool, update_all: bool, test_after: bool) -> int:
    """Run Homebrew and Mise updates with optional testing."""
    update_brew(auto_apply=auto_apply or update_all)
    update_mise()
    if test_after or update_all:
        run_tests()
    return 0


def run_update(
    check_only: bool = False,
    auto_apply: bool = False,
    update_all: bool = False,
    tools_only: bool = False,
    test_after: bool = False,
    prune: bool = True,
    show_diff: bool = False,
) -> int:
    """Fetch, apply, and reconcile dotfiles updates and optional Homebrew/Mise upgrades."""
    dotfiles = get_dotfiles_dir()

    if tools_only:
        return _tools_update(auto_apply, update_all, test_after)

    print(f"{C_BLUE}==>{C_RESET} Checking for dotfiles updates in {C_BOLD}{dotfiles}{C_RESET}...")

    code, _, _ = run_cmd(["git", "-C", str(dotfiles), "fetch", "--quiet", "origin"], timeout=120)
    if code != 0:
        print(f"{C_YELLOW}⚠ Warning: Failed to fetch from origin. Check network or credentials.{C_RESET}", file=sys.stderr)
        return 1

    git_state = _inspect_git_state(dotfiles)
    _current_branch, upstream, behind, ahead, is_dirty = git_state
    updated_git = False

    if show_diff:
        return _preview_incoming_diff(dotfiles, upstream, behind)

    if behind == 0 and ahead == 0:
        _, head_short, _ = run_cmd(["git", "-C", str(dotfiles), "rev-parse", "--short", "HEAD"])
        print(f"{C_GREEN}✔{C_RESET} Dotfiles are up to date with {C_BOLD}{upstream}{C_RESET} (commit {C_CYAN}{head_short}{C_RESET}).")
        if is_dirty:
            print(f"{C_YELLOW}⚠ Note: You have local uncommitted changes in {dotfiles}{C_RESET}")
    elif behind > 0 and ahead > 0:
        print(f"{C_RED}✖ Dotfiles branch has diverged from {upstream} ({ahead} ahead, {behind} behind).{C_RESET}")
        subprocess.run(["git", "-C", str(dotfiles), "log", "--graph", "--oneline", "-n", "10", "HEAD", upstream], check=False)
        return 1
    elif ahead > 0 and behind == 0:
        print(f"{C_GREEN}✔{C_RESET} Local dotfiles are ahead of {C_BOLD}{upstream}{C_RESET} by {ahead} commit(s) (unpushed).")
    else:
        early_rc, updated_git = _handle_incoming_commits(
            dotfiles,
            git_state,
            check_only=check_only,
            interactive=not auto_apply and not update_all,
            prune=prune,
        )
        if early_rc >= 0:
            return early_rc

    if not check_only:
        _run_post_update_hooks(auto_apply, update_all, test_after, updated_git)

    return 0
