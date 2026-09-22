import shutil
import subprocess
import sys
from pathlib import Path
from cli.manifest import get_dotfiles_dir
from cli.test import run_tests

C_GREEN = "\033[38;2;166;227;161m"
C_YELLOW = "\033[38;2;249;226;175m"
C_RED = "\033[38;2;243;139;168m"
C_BLUE = "\033[1;34m"
C_CYAN = "\033[38;2;137;220;235m"
C_BOLD = "\033[1m"
C_RESET = "\033[0m"

def run_cmd(cmd: list[str], cwd: Path = None) -> tuple[int, str]:
    try:
        res = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
        return res.returncode, res.stdout.strip()
    except Exception as e:
        return 1, str(e)

def update_brew():
    if shutil.which("brew"):
        print(f"\n{C_BLUE}==>{C_RESET} Updating Homebrew formulas and packages...")
        subprocess.run(["brew", "update"])
        subprocess.run(["brew", "upgrade"])
        print(f"{C_GREEN}✔{C_RESET} Homebrew packages updated successfully!")

def update_mise():
    if shutil.which("mise"):
        print(f"\n{C_BLUE}==>{C_RESET} Upgrading Mise tools and runtimes...")
        subprocess.run(["mise", "upgrade"])
        print(f"{C_GREEN}✔{C_RESET} Mise tools upgraded successfully!")

def prompt_user(prompt: str, default: str = "y") -> str:
    try:
        res = input(prompt)
        return res.strip() or default
    except (EOFError, KeyboardInterrupt):
        return default

def run_update(check_only: bool = False, auto_apply: bool = False, update_all: bool = False, tools_only: bool = False, test_after: bool = False) -> int:
    dotfiles = get_dotfiles_dir()

    if tools_only:
        update_brew()
        update_mise()
        if test_after or update_all:
            run_tests()
        return 0

    print(f"{C_BLUE}==>{C_RESET} Checking for dotfiles updates in {C_BOLD}{dotfiles}{C_RESET}...")

    # Fetch from origin
    code, _ = run_cmd(["git", "-C", str(dotfiles), "fetch", "--quiet", "origin"])
    if code != 0:
        print(f"{C_YELLOW}⚠ Warning: Failed to fetch from origin. Check network or credentials.{C_RESET}", file=sys.stderr)
        return 1

    code, current_branch = run_cmd(["git", "-C", str(dotfiles), "branch", "--show-current"])
    current_branch = current_branch or "main"

    code, upstream = run_cmd(["git", "-C", str(dotfiles), "rev-parse", "--abbrev-ref", "@{u}"])
    upstream = upstream or f"origin/{current_branch}"

    code, behind_str = run_cmd(["git", "-C", str(dotfiles), "rev-list", "--count", f"HEAD..{upstream}"])
    code, ahead_str = run_cmd(["git", "-C", str(dotfiles), "rev-list", "--count", f"{upstream}..HEAD"])

    behind = int(behind_str) if behind_str.isdigit() else 0
    ahead = int(ahead_str) if ahead_str.isdigit() else 0

    code, status = run_cmd(["git", "-C", str(dotfiles), "status", "--porcelain"])
    is_dirty = bool(status)

    updated_git = False

    if behind == 0 and ahead == 0:
        code, head_short = run_cmd(["git", "-C", str(dotfiles), "rev-parse", "--short", "HEAD"])
        print(f"{C_GREEN}✔{C_RESET} Dotfiles are up to date with {C_BOLD}{upstream}{C_RESET} (commit {C_CYAN}{head_short}{C_RESET}).")
        if is_dirty:
            print(f"{C_YELLOW}⚠ Note: You have local uncommitted changes in {dotfiles}{C_RESET}")
    elif behind > 0 and ahead > 0:
        print(f"{C_RED}✖ Dotfiles branch has diverged from {upstream} ({ahead} ahead, {behind} behind).{C_RESET}")
        subprocess.run(["git", "-C", str(dotfiles), "log", "--graph", "--oneline", "-n", "10", "HEAD", upstream])
        return 1
    elif ahead > 0 and behind == 0:
        print(f"{C_GREEN}✔{C_RESET} Local dotfiles are ahead of {C_BOLD}{upstream}{C_RESET} by {ahead} commit(s) (unpushed).")
    else:
        print(f"{C_YELLOW}⬇ {behind} update(s) available for your dotfiles from {upstream}:{C_RESET}\n")
        subprocess.run(["git", "-C", str(dotfiles), "log", "--format=  %C(yellow)%h%Creset %C(cyan)%cr%Creset %C(bold)%s%Creset %C(dim)(%an)%Creset", f"HEAD..{upstream}"])
        print()

        if check_only:
            print("Run 'dot update' to pull and apply these updates.")
            return 0

        if is_dirty:
            print(f"{C_YELLOW}⚠ You have uncommitted changes in {dotfiles}. Please commit or stash them before updating.{C_RESET}")
            subprocess.run(["git", "-C", str(dotfiles), "status", "-s"])
            return 1

        do_apply = True
        if not auto_apply and not update_all:
            ans = prompt_user("Would you like to pull and apply updates now? [Y/n]: ", default="y")
            if ans.lower().startswith("n"):
                print("Updates postponed.")
                do_apply = False

        if do_apply:
            print(f"{C_BLUE}==>{C_RESET} Pulling updates via git pull --rebase...")
            code, _ = run_cmd(["git", "-C", str(dotfiles), "pull", "--rebase", "origin", current_branch])
            if code == 0:
                code, new_head = run_cmd(["git", "-C", str(dotfiles), "rev-parse", "--short", "HEAD"])
                print(f"{C_GREEN}✔{C_RESET} Dotfiles successfully updated to {C_CYAN}{new_head}{C_RESET}!")
                updated_git = True
            else:
                print(f"{C_RED}✖ Git pull failed. Please check {dotfiles}{C_RESET}", file=sys.stderr)
                return 1

    if check_only:
        return 0

    if update_all:
        update_brew()
        update_mise()
        run_tests()
    elif not auto_apply:
        ans = prompt_user("\nWould you also like to update Homebrew packages and Mise runtimes? [y/N]: ", default="n")
        if ans.lower().startswith("y"):
            update_brew()
            update_mise()
            run_tests()
    elif test_after:
        run_tests()

    if updated_git:
        print(f"\n{C_CYAN}💡 Run 'sz' to reload your active shell session.{C_RESET}")

    return 0
