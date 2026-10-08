import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from cli.manifest import get_dotfiles_dir, get_symlink_manifest
from cli.ui import (
    C_BOLD,
    C_DIM,
    C_GREEN,
    C_RED,
    C_RESET,
    C_YELLOW,
    print_header,
)


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

def run_cmd(cmd: list[str]) -> tuple[int, str]:
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=5, check=False)
        return res.returncode, res.stdout.strip()
    except (OSError, subprocess.SubprocessError) as e:
        return 1, str(e)

def check_repository(report: DoctorReport, dotfiles: Path):
    print(f"\n{C_BOLD}1. Dotfiles Repository{C_RESET}")
    if not (dotfiles / ".git").is_dir():
        report.fail("Dotfiles repository not found", str(dotfiles))
        return

    if not shutil.which("git"):
        report.warn(f"Repository: {dotfiles.name}", "git binary not installed")
        return

    _, branch = run_cmd(["git", "-C", str(dotfiles), "branch", "--show-current"])
    branch = branch or "detached"
    _, commit = run_cmd(["git", "-C", str(dotfiles), "rev-parse", "--short", "HEAD"])
    report.ok(f"Repository: {dotfiles.name}", f"{branch} ({commit})")

    _, status = run_cmd(["git", "-C", str(dotfiles), "status", "--porcelain"])
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
            except (OSError, RuntimeError):
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

def check_cli_tools(report: DoctorReport, fix: bool = False):
    print(f"\n{C_BOLD}3. Core CLI & Runtime Tools{C_RESET}")
    tools = [
        ("git", "Git version control", ["git", "--version"]),
        ("delta", "git-delta syntax diff pager", ["delta", "--version"]),
        ("zsh", "Zsh shell", ["zsh", "--version"]),
        ("rg", "ripgrep search", ["rg", "--version"]),
        ("fd", "fd file finder", ["fd", "--version"]),
        ("fzf", "fzf fuzzy finder", ["fzf", "--version"]),
        ("zoxide", "zoxide smart cd", ["zoxide", "--version"]),
        ("eza", "eza modern ls", ["eza", "--version"]),
        ("atuin", "Atuin shell history", ["atuin", "--version"]),
        ("bat", "bat syntax viewer", ["bat", "--version"]),
        ("mise", "Mise polyglot runtime", ["mise", "--version"]),
        ("nvim", "Neovim editor", ["nvim", "--version"]),
        ("yazi", "Yazi file manager", ["yazi", "--version"]),
        ("dust", "dust disk analyzer", ["dust", "--version"]),
        ("btop", "btop system monitor", ["btop", "--version"]),
        ("tldr", "tlrc cheat sheets (tldr)", ["tldr", "--version"]),
        ("tokei", "tokei codebase statistics", ["tokei", "--version"]),
        ("hyperfine", "hyperfine CLI benchmark", ["hyperfine", "--version"]),
        ("lazygit", "lazygit git terminal UI", ["lazygit", "--version"]),
        ("glow", "glow Markdown renderer", ["glow", "--version"]),
        ("trash", "trash (del alias)", ["sh", "-c", "command -v trash"]),
        ("uv", "uv Astral Python manager", ["uv", "--version"]),
    ]

    for bin_name, label, cmd in tools:
        if shutil.which(bin_name):
            code, ver = run_cmd(cmd)
            first_line = ver.splitlines()[0] if ver else "installed"
            report.ok(label, first_line[:38])
        else:
            report.warn(label, f"{bin_name} binary not found")

    # Check Spaceship Zsh prompt installation
    home = Path.home()
    spaceship_candidates = [
        Path("/opt/homebrew/opt/spaceship/spaceship.zsh"),
        Path("/home/linuxbrew/.linuxbrew/opt/spaceship/spaceship.zsh"),
        Path("/usr/local/opt/spaceship/spaceship.zsh"),
        home / ".oh-my-zsh" / "custom" / "themes" / "spaceship-prompt" / "spaceship.zsh",
        home / ".spaceship-prompt" / "spaceship.zsh",
    ]
    sp_found = next((p for p in spaceship_candidates if p.is_file()), None)
    if sp_found:
        zwc_status = " (.zwc compiled)" if sp_found.with_name("spaceship.zsh.zwc").is_file() else ""
        report.ok("Spaceship Zsh prompt", f"{sp_found.parent.name}{zwc_status}")
    else:
        report.warn("Spaceship Zsh prompt", "spaceship.zsh not found (using vcs_info fallback)")

    # Check Zsh plugins (fzf-tab, zsh-autosuggestions, zsh-syntax-highlighting)
    zsh_plugins = [
        ("fzf-tab completion menu", "fzf-tab.zsh", [
            Path("/opt/homebrew/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh"),
            Path("/usr/share/fzf-tab/fzf-tab.zsh"),
            Path("/home/linuxbrew/.linuxbrew/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh"),
            home / ".local" / "share" / "fzf-tab" / "fzf-tab.zsh",
        ]),
        ("zsh-autosuggestions", "zsh-autosuggestions.zsh", [
            Path("/opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh"),
            Path("/home/linuxbrew/.linuxbrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh"),
            Path("/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh"),
            Path("/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"),
            home / ".local" / "share" / "zsh-autosuggestions" / "zsh-autosuggestions.zsh",
        ]),
        ("zsh-syntax-highlighting", "zsh-syntax-highlighting.zsh", [
            Path("/opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"),
            Path("/home/linuxbrew/.linuxbrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"),
            Path("/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"),
            Path("/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"),
            home / ".local" / "share" / "zsh-syntax-highlighting" / "zsh-syntax-highlighting.zsh",
        ]),
    ]
    for plugin_label, plugin_file, candidates in zsh_plugins:
        found = next((p for p in candidates if p.is_file()), None)
        if found:
            report.ok(plugin_label, str(found).replace(str(home), "~")[:38])
        else:
            report.warn(plugin_label, f"{plugin_file} not found")

    # Check Mise managed runtimes (declared in config/mise/config.toml)
    if shutil.which("mise"):
        import json as _json
        code, raw_json = run_cmd(["mise", "ls", "--current", "--json"])
        if code == 0 and raw_json:
            try:
                mise_data = _json.loads(raw_json)
                active_tools = []
                missing_tools = []
                for tool_name, entries in mise_data.items():
                    for item in entries:
                        ver = item.get("version") or item.get("requested_version") or "unknown"
                        if item.get("installed", False):
                            active_tools.append(f"{tool_name}@{ver}")
                        else:
                            missing_tools.append(f"{tool_name}@{ver}")
                if missing_tools:
                    if fix:
                        ic, _ = run_cmd(["mise", "install"])
                        if ic == 0:
                            report.fixed("Mise managed runtimes", f"Installed {', '.join(missing_tools)}")
                        else:
                            report.warn("Mise managed runtimes", f"Missing: {', '.join(missing_tools)} (run 'mise install')")
                    else:
                        report.warn("Mise managed runtimes", f"Missing: {', '.join(missing_tools)} (run 'mise install')")
                elif active_tools:
                    report.ok("Mise managed runtimes", ", ".join(active_tools)[:38])
            except (ValueError, AttributeError, TypeError):
                report.warn("Mise managed runtimes", "Unexpected 'mise ls --json' output")

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
        code, _out = run_cmd(["zsh", "-c", '[ "${#${:-🐧}}" -eq 1 ]'])
        if code == 0:
            report.ok("Zsh multibyte parsing", "Single-char UTF-8 glyphs confirmed")
        else:
            report.warn("Zsh multibyte parsing", "Single-byte mode active; check ~/.zshenv")

def check_ssh(report: DoctorReport, dotfiles: Path, fix: bool = False):
    print(f"\n{C_BOLD}6. SSH Agent & Defaults{C_RESET}")
    if not shutil.which("ssh"):
        report.warn("SSH", "ssh binary not installed")
        return

    ssh_config = Path.home() / ".ssh" / "config"
    include = f"Include {dotfiles / 'config' / 'ssh' / 'dotfiles.conf'}"
    try:
        current = ssh_config.read_text()
    except OSError:
        current = ""
    if include in current.splitlines():
        report.ok("~/.ssh/config", "Includes shared dotfiles defaults")
    elif fix:
        ssh_config.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        ssh_config.write_text(f"{include}\n\n{current}")
        ssh_config.chmod(0o600)
        report.fixed("~/.ssh/config", "Prepended Include for shared defaults")
    else:
        report.warn("~/.ssh/config", "Missing shared defaults Include. Run with --fix")

    # ssh-add exit codes: 0 = keys loaded, 1 = agent running without keys, 2 = no agent
    code, _ = run_cmd(["ssh-add", "-l"])
    if code == 0:
        report.ok("SSH agent", "Running with keys loaded")
    elif code == 1:
        report.ok("SSH agent", "Running (keys load on first use)")
    else:
        report.warn("SSH agent", "Not reachable; open a new shell to start the shared agent")

# gpg-agent forgets passphrases after 10 minutes by default, so signing from editors and TUIs
# (which can't show a terminal pinentry) breaks soon after an unlock. Remember them for a working day.
GPG_CACHE_TTL = {"default-cache-ttl": 28800, "max-cache-ttl": 86400}


def check_gpg_cache(report: DoctorReport, fix: bool = False):
    home = Path(os.environ.get("GNUPGHOME", Path.home() / ".gnupg"))
    conf = home / "gpg-agent.conf"
    try:
        lines = conf.read_text().splitlines()
    except OSError:
        lines = []
    current = {}
    for line in lines:
        parts = line.split()
        if len(parts) == 2 and parts[0] in GPG_CACHE_TTL and parts[1].isdigit():
            current[parts[0]] = int(parts[1])
    ttl = current.get("default-cache-ttl", 600)
    if ttl >= GPG_CACHE_TTL["default-cache-ttl"]:
        report.ok("GPG passphrase cache", f"{ttl // 3600}h after unlock")
    elif fix:
        kept = [line for line in lines if not line.split() or line.split()[0] not in GPG_CACHE_TTL]
        kept += [f"{key} {value}" for key, value in GPG_CACHE_TTL.items()]
        home.mkdir(mode=0o700, parents=True, exist_ok=True)
        conf.write_text("\n".join(kept) + "\n")
        run_cmd(["gpg-connect-agent", "reloadagent", "/bye"])
        report.fixed("GPG passphrase cache", "Raised to 8h (max 24h); unlock once to start it")
    else:
        report.warn("GPG passphrase cache", f"Only {ttl // 60} min; signing outside a terminal fails. Run with --fix")

def check_git_signing(report: DoctorReport, fix: bool = False):
    print(f"\n{C_BOLD}5. Git Identity & Commit Signing{C_RESET}")
    if not shutil.which("git"):
        report.warn("Git config", "git binary not installed")
        return

    _, name = run_cmd(["git", "config", "--get", "user.name"])
    _, email = run_cmd(["git", "config", "--get", "user.email"])
    if name:
        report.ok("Git user.name", name)
    else:
        report.warn("Git user.name", "Not set in git config")

    if email:
        report.ok("Git user.email", email)
    else:
        report.warn("Git user.email", "Not set in git config")

    _, sign = run_cmd(["git", "config", "--get", "commit.gpgsign"])
    _, format_type = run_cmd(["git", "config", "--get", "gpg.format"])
    _, signing_key = run_cmd(["git", "config", "--get", "user.signingkey"])

    if sign == "true":
        key_desc = f"{format_type or 'gpg'} ({signing_key})" if signing_key else "Enabled"
        report.ok("Commit signing", key_desc)
        if format_type in ("", "openpgp") and shutil.which("gpg"):
            check_gpg_cache(report, fix=fix)
    else:
        report.ok("Commit signing", "Disabled (optional)")

def is_wsl() -> bool:
    if os.environ.get("WSL_DISTRO_NAME"):
        return True
    try:
        return "microsoft" in Path("/proc/version").read_text().lower()
    except OSError:
        return False

def check_wsl(report: DoctorReport, dotfiles: Path):
    print(f"\n{C_BOLD}7. WSL Integration{C_RESET}")
    if str(dotfiles.resolve()).startswith("/mnt/"):
        report.warn("Dotfiles location", "On the Windows drive; move to ~ (9P file access is slow)")
    else:
        report.ok("Dotfiles location", "Linux filesystem")

    if shutil.which("win32yank.exe"):
        report.ok("Clipboard (win32yank)", "UTF-8 safe copy / clippaste")
    else:
        report.warn("Clipboard (win32yank)", "Missing; falls back to clip.exe. Run install-cli.sh wsl")

    if shutil.which("wslview"):
        report.ok("Browser opener (wslview)", "open & $BROWSER use the Windows browser")
    else:
        report.warn("Browser opener (wslview)", "Missing; 'open' falls back to explorer.exe. Install wslu")

def run_doctor(fix: bool = False) -> int:
    dotfiles = get_dotfiles_dir()
    report = DoctorReport()

    header_text = "Dotfiles Doctor \u2014 System & Environment Health Check"
    if fix:
        header_text += " [FIX]"

    print_header(header_text)

    check_repository(report, dotfiles)
    check_and_heal_symlinks(report, dotfiles, fix=fix)
    check_cli_tools(report, fix=fix)
    check_locale(report)
    check_git_signing(report, fix=fix)
    check_ssh(report, dotfiles, fix=fix)
    if is_wsl():
        check_wsl(report, dotfiles)

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
