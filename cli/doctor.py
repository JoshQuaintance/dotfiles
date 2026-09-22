import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Tuple

try:
    from rich.console import Console
    from rich.panel import Panel
    from rich.text import Text
    console = Console()
    HAS_RICH = True
except ImportError:
    console = None
    HAS_RICH = False

from cli.manifest import get_dotfiles_dir, get_symlink_manifest, SymlinkEntry

# Catppuccin-inspired status icons and ANSI colors
C_GREEN = "\033[38;2;166;227;161m"
C_YELLOW = "\033[38;2;249;226;175m"
C_RED = "\033[38;2;243;139;168m"
C_CYAN = "\033[38;2;137;220;235m"
C_DIM = "\033[38;2;108;112;134m"
C_BOLD = "\033[1m"
C_RESET = "\033[0m"

class DoctorReport:
    def __init__(self):
        self.passed = 0
        self.warnings = 0
        self.failed = 0
        self.repaired = 0

    def ok(self, label: str, detail: str = ""):
        self.passed += 1
        print(f"  {C_GREEN}✔{C_RESET} {label:<44} {C_DIM}{detail}{C_RESET}")

    def warn(self, label: str, detail: str = ""):
        self.warnings += 1
        print(f"  {C_YELLOW}⚠{C_RESET} {label:<44} {C_YELLOW}{detail}{C_RESET}")

    def fail(self, label: str, detail: str = ""):
        self.failed += 1
        print(f"  {C_RED}✖{C_RESET} {C_BOLD}{label:<44}{C_RESET} {C_RED}{detail}{C_RESET}")

    def fixed(self, label: str, detail: str = ""):
        self.repaired += 1
        self.passed += 1
        print(f"  {C_GREEN}✔ [FIXED]{C_RESET} {label:<36} {C_GREEN}{detail}{C_RESET}")

def run_cmd(cmd: list[str]) -> Tuple[int, str]:
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        return res.returncode, res.stdout.strip()
    except Exception as e:
        return 1, str(e)

def check_repository(report: DoctorReport, dotfiles: Path):
    print(f"\n{C_BOLD}1. Dotfiles Repository{C_RESET}")
    if not (dotfiles / ".git").is_dir():
        report.fail("Dotfiles repository not found", str(dotfiles))
        return

    if not shutil.which("git"):
        report.warn(f"Repository: {dotfiles.name}", "git binary not installed")
        return

    code, branch = run_cmd(["git", "-C", str(dotfiles), "branch", "--show-current"])
    branch = branch or "detached"
    code, commit = run_cmd(["git", "-C", str(dotfiles), "rev-parse", "--short", "HEAD"])
    report.ok(f"Repository: {dotfiles.name}", f"{branch} ({commit})")

    code, status = run_cmd(["git", "-C", str(dotfiles), "status", "--porcelain"])
    if not status:
        report.ok("Working tree clean", "No uncommitted changes")
    else:
        changed_count = len(status.splitlines())
        report.warn("Working tree has uncommitted changes", f"{changed_count} files modified")

def check_and_heal_symlinks(report: DoctorReport, dotfiles: Path, fix: bool = False):
    print(f"\n{C_BOLD}2. Configuration Symlinks & Health{C_RESET}")
    manifest = get_symlink_manifest()

    for entry in manifest:
        link = entry.link_path
        target_expected = (dotfiles / entry.rel_target).resolve()
        display_path = str(link).replace(str(Path.home()), "~")

        # Skip non-required parent directory paths if the parent app isn't installed
        if not entry.required and not link.parent.exists():
            continue

        # Target file in dotfiles repo must exist
        if not target_expected.exists():
            report.fail(f"{entry.description}", f"Repo target missing: {entry.rel_target}")
            continue

        if link.is_symlink():
            try:
                actual_target = link.resolve()
            except Exception:
                actual_target = None

            # 1. Broken / Dangling symlink
            if not link.exists() or actual_target is None or not actual_target.exists():
                raw_target = os.readlink(link)
                if fix:
                    link.unlink()
                    link.symlink_to(target_expected)
                    report.fixed(f"{display_path}", f"Repaired broken link -> {entry.rel_target}")
                else:
                    report.fail(f"{display_path} (dangling)", f"Points to missing {raw_target}")
                continue

            # 2. Symlink points to wrong/unexpected destination
            if actual_target != target_expected:
                if fix:
                    link.unlink()
                    link.symlink_to(target_expected)
                    report.fixed(f"{display_path}", f"Re-pointed to {entry.rel_target}")
                else:
                    report.warn(f"{display_path}", f"Points to: {actual_target}")
                continue

            # 3. Healthy symlink
            report.ok(f"{display_path}", f"-> {entry.rel_target}")

        elif link.exists():
            # Regular file or directory collision (not a symlink)
            if fix:
                backup = link.with_name(f"{link.name}.bak.{datetime.now().strftime('%Y%m%d%H%M%S')}")
                shutil.move(link, backup)
                link.symlink_to(target_expected)
                report.fixed(f"{display_path}", f"Backed up collision & linked -> {entry.rel_target}")
            else:
                report.warn(f"{display_path} is regular file", "Not a symlink. Run with --fix to link")

        else:
            # Link does not exist
            if fix:
                link.parent.mkdir(parents=True, exist_ok=True)
                link.symlink_to(target_expected)
                report.fixed(f"{display_path}", f"Created link -> {entry.rel_target}")
            else:
                report.fail(f"{display_path} missing", "Run with --fix or ./install.sh to link")

def check_cli_tools(report: DoctorReport):
    print(f"\n{C_BOLD}3. Core CLI & Runtime Tools{C_RESET}")
    tools = [
        ("git", "Git version control", ["git", "--version"]),
        ("zsh", "Zsh shell", ["zsh", "--version"]),
        ("rg", "ripgrep search", ["rg", "--version"]),
        ("fd", "fd file finder", ["fd", "--version"]),
        ("fzf", "fzf fuzzy finder", ["fzf", "--version"]),
        ("zoxide", "zoxide smart cd", ["zoxide", "--version"]),
        ("starship", "Starship prompt", ["starship", "--version"]),
        ("eza", "eza modern ls", ["eza", "--version"]),
        ("atuin", "Atuin shell history", ["atuin", "--version"]),
        ("bat", "bat syntax viewer", ["bat", "--version"]),
        ("mise", "Mise polyglot runtime", ["mise", "--version"]),
        ("nvim", "Neovim editor", ["nvim", "--version"]),
        ("yazi", "Yazi file manager", ["yazi", "--version"]),
        ("dust", "dust disk analyzer", ["dust", "--version"]),
        ("btop", "btop system monitor", ["btop", "--version"]),
        ("uv", "uv Astral Python manager", ["uv", "--version"]),
    ]

    for bin_name, label, cmd in tools:
        if shutil.which(bin_name):
            code, ver = run_cmd(cmd)
            first_line = ver.splitlines()[0] if ver else "installed"
            report.ok(label, first_line[:38])
        else:
            report.warn(label, f"{bin_name} binary not found")

def check_locale(report: DoctorReport):
    print(f"\n{C_BOLD}4. Locale & Multibyte Support{C_RESET}")
    lang = os.environ.get("LANG", "")
    lc_all = os.environ.get("LC_ALL", "")
    active = lc_all or lang or "C"

    if "UTF-8" in active.upper() or "UTF8" in active.upper():
        report.ok(f"Active locale: {active}", "UTF-8 capable")
    else:
        report.warn(f"Terminal locale: {active}", "May cause border box or emoji misalignment")

    # Multibyte evaluation in Zsh
    if shutil.which("zsh"):
        code, out = run_cmd(["zsh", "-c", '[ "${#${:-🐧}}" -eq 1 ]'])
        if code == 0:
            report.ok("Zsh multibyte parsing", "Single-char UTF-8 glyphs confirmed")
        else:
            report.warn("Zsh multibyte parsing", "Single-byte mode active; check ~/.zshenv")

def check_git_signing(report: DoctorReport):
    print(f"\n{C_BOLD}5. Git Identity & Commit Signing{C_RESET}")
    if not shutil.which("git"):
        report.warn("Git config", "git binary not installed")
        return

    code, name = run_cmd(["git", "config", "--get", "user.name"])
    code, email = run_cmd(["git", "config", "--get", "user.email"])
    if name:
        report.ok("Git user.name", name)
    else:
        report.warn("Git user.name", "Not set in git config")

    if email:
        report.ok("Git user.email", email)
    else:
        report.warn("Git user.email", "Not set in git config")

    code, sign = run_cmd(["git", "config", "--get", "commit.gpgsign"])
    code, format_type = run_cmd(["git", "config", "--get", "gpg.format"])
    code, signing_key = run_cmd(["git", "config", "--get", "user.signingkey"])

    if sign == "true":
        key_desc = f"{format_type or 'gpg'} ({signing_key})" if signing_key else "Enabled"
        report.ok("Commit signing", key_desc)
    else:
        report.ok("Commit signing", "Disabled (optional)")

def run_doctor(fix: bool = False) -> int:
    dotfiles = get_dotfiles_dir()
    report = DoctorReport()

    header_text = "Dotfiles Doctor — System & Environment Health Check"
    if fix:
        header_text += " [AUTO-HEALING ACTIVE]"

    print(f"\n{C_CYAN}╭────────────────────────────────────────────────────────╮{C_RESET}")
    print(f"{C_CYAN}│{C_RESET}  {C_BOLD}{header_text:<53}{C_RESET}{C_CYAN}│{C_RESET}")
    print(f"{C_CYAN}╰────────────────────────────────────────────────────────╯{C_RESET}")

    check_repository(report, dotfiles)
    check_and_heal_symlinks(report, dotfiles, fix=fix)
    check_cli_tools(report)
    check_locale(report)
    check_git_signing(report)

    print(f"\n{C_BOLD}Summary:{C_RESET} {C_GREEN}{report.passed} passed{C_RESET}", end="")
    if report.repaired > 0:
        print(f", {C_GREEN}{report.repaired} auto-repaired{C_RESET}", end="")
    print(f", {C_YELLOW}{report.warnings} warnings{C_RESET}, {C_RED}{report.failed} failed{C_RESET}\n")

    if report.failed > 0:
        if not fix:
            print(f"{C_YELLOW}💡 Tip: Run 'dot doctor --fix' to automatically repair broken symlinks.{C_RESET}\n")
        return 1

    return 0

if __name__ == "__main__":
    do_fix = "--fix" in sys.argv or "-f" in sys.argv
    sys.exit(run_doctor(fix=do_fix))
