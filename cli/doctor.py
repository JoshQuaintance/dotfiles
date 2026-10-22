"""`dot doctor`: audit and auto-heal symlinks, CLI tools, Zsh bytecode, SSH, and Git signing."""

import contextlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Optional

from cli.manifest import SymlinkEntry, ToolEntry, get_cli_tool_manifest, get_dotfiles_dir, get_symlink_manifest
from cli.prompt import get_active_prompt
from cli.ui import (
    C_BOLD,
    C_DIM,
    C_GREEN,
    C_RED,
    C_RESET,
    C_YELLOW,
    print_header,
    run_cmd,
)

# Check label & path constants (avoids duplicated literals across status branches)
LBL_ZSH_BYTECODE = "Zsh bytecode (.zwc)"
LBL_SPACESHIP_PROMPT = "Active Zsh prompt (Spaceship)"
MSG_SPACESHIP_FALLBACK = "spaceship.zsh not found (using vcs_info fallback)"
FILE_FZF_TAB = "fzf-tab.zsh"
FILE_AUTOSUGGESTIONS = "zsh-autosuggestions.zsh"
FILE_SYNTAX_HIGHLIGHTING = "zsh-syntax-highlighting.zsh"
DIR_LOCAL = ".local"
LBL_MISE_RUNTIMES = "Mise managed runtimes"
LBL_NVIM_HEALTH = "Neovim healthcheck (:checkhealth)"
LBL_SSH_CONFIG = "~/.ssh/config"
LBL_SSH_SOCKETS = "~/.ssh/sockets"
LBL_SSH_AGENT = "SSH agent"
LBL_GPG_CACHE = "GPG passphrase cache"
FILE_SETTINGS_JSON = "settings.json"
LBL_WT_THEME = "Windows Terminal theme"


class DoctorReport:
    """Track and display pass, warning, failure, and auto-repair counts for `dot doctor`."""

    def __init__(self):
        """Initialize counters and check entry log for doctor audit checks."""
        self.passed = 0
        self.warnings = 0
        self.failed = 0
        self.repaired = 0
        self.entries: list[dict[str, str]] = []

    def ok(self, label: str, detail: str = ""):
        """Record and print a passing health check."""
        self.passed += 1
        self.entries.append({"status": "ok", "label": label, "detail": detail})
        print(f"  {C_GREEN}✔{C_RESET} {label:<44} {C_DIM}{detail}{C_RESET}")

    def warn(self, label: str, detail: str = ""):
        """Record and print a non-fatal health warning."""
        self.warnings += 1
        self.entries.append({"status": "warn", "label": label, "detail": detail})
        print(f"  {C_YELLOW}⚠{C_RESET} {label:<44} {C_YELLOW}{detail}{C_RESET}")

    def fail(self, label: str, detail: str = ""):
        """Record and print a failing health check."""
        self.failed += 1
        self.entries.append({"status": "fail", "label": label, "detail": detail})
        print(f"  {C_RED}✖{C_RESET} {C_BOLD}{label:<44}{C_RESET} {C_RED}{detail}{C_RESET}")

    def fixed(self, label: str, detail: str = ""):
        """Record and print an automatically repaired check."""
        self.repaired += 1
        self.passed += 1
        self.entries.append({"status": "fixed", "label": label, "detail": detail})
        print(f"  {C_GREEN}✔ [FIXED]{C_RESET} {label:<36} {C_GREEN}{detail}{C_RESET}")


def check_repository(report: DoctorReport, dotfiles: Path):
    """Audit the dotfiles Git checkout, current branch, and working tree status."""
    print(f"\n{C_BOLD}1. Dotfiles Repository{C_RESET}")
    if not (dotfiles / ".git").is_dir():
        report.fail("Dotfiles repository not found", str(dotfiles))
        return

    if not shutil.which("git"):
        report.warn(f"Repository: {dotfiles.name}", "git binary not installed")
        return

    _, branch, _ = run_cmd(["git", "-C", str(dotfiles), "branch", "--show-current"])
    branch = branch or "detached"
    _, commit, _ = run_cmd(["git", "-C", str(dotfiles), "rev-parse", "--short", "HEAD"])
    report.ok(f"Repository: {dotfiles.name}", f"{branch} ({commit})")

    _, status, _ = run_cmd(["git", "-C", str(dotfiles), "status", "--porcelain"])
    if not status:
        report.ok("Working tree clean", "No uncommitted changes")
    else:
        changed_count = len(status.splitlines())
        report.warn("Working tree has uncommitted changes", f"{changed_count} files modified")


def stale_zsh_bytecode(dotfiles: Path) -> list[Path]:
    """Repo zsh scripts sourced by ~/.zshrc whose .zwc is missing or older than the source."""
    zsh_dir = dotfiles / "zsh"
    sources = [zsh_dir / ".aliases", *zsh_dir.glob("*.zsh"), *(zsh_dir / "functions").glob("*.zsh")]
    stale = []
    for src in sources:
        zwc = src.with_name(f"{src.name}.zwc")
        if src.is_file() and (not zwc.is_file() or zwc.stat().st_mtime < src.stat().st_mtime):
            stale.append(src)
    return stale


def orphaned_zsh_bytecode(dotfiles: Path) -> list[Path]:
    """Return `.zwc` files under `zsh/` whose underlying `.zsh` or `.aliases` source is missing."""
    zsh_dir = dotfiles / "zsh"
    zwc_files = [*zsh_dir.glob("*.zwc"), *zsh_dir.glob(".*.zwc"), *(zsh_dir / "functions").glob("*.zwc")]
    orphans: list[Path] = []
    for zwc in zwc_files:
        src = zwc.with_name(zwc.name[:-4])
        if zwc.is_file() and not src.is_file():
            orphans.append(zwc)
    return orphans


def compile_zsh_sources(dotfiles: Path) -> int:
    """Compile stale repo Zsh scripts via `zcompile` and return how many were compiled."""
    if not shutil.which("zsh"):
        return 0
    compiled = 0
    for src in stale_zsh_bytecode(dotfiles):
        code, _, _ = run_cmd(["zsh", "-c", 'zcompile -R -- "$1.zwc" "$1"', "zcompile", str(src)])
        if code == 0:
            compiled += 1
    return compiled


def check_zsh_bytecode(report: DoctorReport, dotfiles: Path, fix: bool = False):
    """Verify `.zwc` bytecode freshness and orphan absence, healing when `fix` is True."""
    stale = stale_zsh_bytecode(dotfiles)
    orphans = orphaned_zsh_bytecode(dotfiles)
    if not stale and not orphans:
        report.ok(LBL_ZSH_BYTECODE, "All sourced scripts compiled")
        return

    if fix:
        compiled = compile_zsh_sources(dotfiles)
        removed = 0
        for zwc in orphans:
            with contextlib.suppress(OSError):
                zwc.unlink()
                removed += 1
        parts: list[str] = []
        if compiled:
            parts.append(f"Compiled {compiled} script(s)")
        if removed:
            parts.append(f"removed {removed} orphan .zwc")
        report.fixed(LBL_ZSH_BYTECODE, ", ".join(parts) or "Healed .zwc bytecode")
    else:
        issues: list[str] = []
        if stale:
            issues.append(f"{len(stale)} stale")
        if orphans:
            issues.append(f"{len(orphans)} orphaned")
        report.warn(LBL_ZSH_BYTECODE, f"{', '.join(issues)}. Run with --fix")


def _audit_existing_symlink(
    report: DoctorReport,
    link: Path,
    target_expected: Path,
    display_path: str,
    rel_target: str,
    fix: bool,
) -> None:
    """Validate or repair an existing symlink entry."""
    try:
        actual_target = link.resolve()
    except (OSError, RuntimeError):
        actual_target = None

    if not link.exists() or actual_target is None or not actual_target.exists():
        raw_target = str(link.readlink())
        if fix:
            link.unlink()
            link.symlink_to(target_expected)
            report.fixed(display_path, f"Repaired broken link -> {rel_target}")
        else:
            report.fail(f"{display_path} (dangling)", f"Points to missing {raw_target}")
        return

    if actual_target != target_expected:
        if fix:
            link.unlink()
            link.symlink_to(target_expected)
            report.fixed(display_path, f"Re-pointed to {rel_target}")
        else:
            report.warn(display_path, f"Points to: {actual_target}")
        return

    report.ok(display_path, f"-> {rel_target}")


def _audit_single_symlink(report: DoctorReport, entry: SymlinkEntry, dotfiles: Path, fix: bool) -> None:
    """Validate or repair a single declarative symlink entry."""
    link = entry.link_path
    if not entry.required and not link.parent.exists():
        return

    target_expected = (dotfiles / entry.rel_target).resolve()
    if not target_expected.exists():
        report.fail(entry.description, f"Repo target missing: {entry.rel_target}")
        return

    display_path = str(link).replace(str(Path.home()), "~")
    if link.is_symlink():
        _audit_existing_symlink(report, link, target_expected, display_path, entry.rel_target, fix)
    elif link.exists():
        if fix:
            backup = link.with_name(f"{link.name}.bak.{datetime.now().strftime('%Y%m%d%H%M%S')}")
            shutil.move(link, backup)
            link.symlink_to(target_expected)
            report.fixed(display_path, f"Backed up collision & linked -> {entry.rel_target}")
        else:
            report.warn(f"{display_path} is regular file", "Not a symlink. Run with --fix to link")
    elif fix:
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(target_expected)
        report.fixed(display_path, f"Created link -> {entry.rel_target}")
    else:
        report.fail(f"{display_path} missing", "Run with --fix or ./install.sh to link")


def check_and_heal_symlinks(report: DoctorReport, dotfiles: Path, fix: bool = False):
    """Audit all declarative symlinks and create or re-point them when `fix` is True."""
    print(f"\n{C_BOLD}2. Configuration Symlinks & Health{C_RESET}")
    for entry in get_symlink_manifest():
        _audit_single_symlink(report, entry, dotfiles, fix)


def _should_brew_install(item_name: str, package: str, fix: bool) -> bool:
    """Return True if a missing Homebrew package should be installed now."""
    if fix:
        return True
    if not sys.stdin.isatty():
        return False
    try:
        ans = input(f"  {C_YELLOW}?{C_RESET} {item_name} is missing. Install '{package}' via brew? [y/N]: ")
        return ans.strip().lower().startswith("y")
    except (EOFError, KeyboardInterrupt):
        return False


def _resolve_tool_binary(tool: ToolEntry) -> Optional[str]:
    """Return the resolved path for a CLI tool or any of its fallback binary names."""
    resolved = shutil.which(tool.bin_name)
    if resolved:
        return resolved
    for alt in getattr(tool, "alt_bin_names", ()):
        alt_resolved = shutil.which(alt)
        if alt_resolved:
            return alt_resolved
    return None


def _check_single_cli_tool(report: DoctorReport, tool: ToolEntry, fix: bool) -> None:
    """Audit or install a single CLI tool from the manifest."""
    resolved_bin = _resolve_tool_binary(tool)
    if resolved_bin:
        vcmd = [resolved_bin, *tool.version_cmd[1:]] if tool.version_cmd else [resolved_bin, "--version"]
        _, ver, _ = run_cmd(vcmd)
        first_line = ver.splitlines()[0] if ver else "installed"
        report.ok(tool.label, first_line[:38])
        return

    formula = tool.brew_formula
    if shutil.which("brew") and formula and _should_brew_install(tool.label, formula, fix):
        print(f"  \033[1;34m==>\033[0m Installing {formula} via brew...")
        code, _, _ = run_cmd(["brew", "install", formula], timeout=600)
        if code == 0 and not _resolve_tool_binary(tool):
            run_cmd(["brew", "link", "--overwrite", formula], timeout=60)
        if code == 0 and _resolve_tool_binary(tool):
            report.fixed(tool.label, f"Installed {formula} via brew")
        else:
            report.warn(tool.label, f"brew install {formula} failed")
        return

    report.warn(tool.label, f"{tool.bin_name} binary not found")


def _check_active_prompt_health(report: DoctorReport, home: Path, fix: bool) -> None:
    """Audit the active Zsh prompt engine installation."""
    active_prompt, _ = get_active_prompt()
    if active_prompt == "native":
        report.ok("Active Zsh prompt (Native)", "Fast Native (0-fork pure Zsh vcs_info)")
        return

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
        report.ok(LBL_SPACESHIP_PROMPT, f"{sp_found.parent.name}{zwc_status}")
        return

    if shutil.which("brew") and _should_brew_install("Spaceship Zsh prompt", "spaceship", fix):
        print("  \033[1;34m==>\033[0m Installing spaceship via brew...")
        code, _, _ = run_cmd(["brew", "install", "spaceship"], timeout=600)
        if code == 0:
            report.fixed(LBL_SPACESHIP_PROMPT, "Installed spaceship via brew")
            return

    report.warn(LBL_SPACESHIP_PROMPT, MSG_SPACESHIP_FALLBACK)


def _check_zsh_plugins(report: DoctorReport, home: Path, fix: bool) -> None:
    """Audit or install Zsh interactive plugins (fzf-tab, autosuggestions, syntax-highlighting)."""
    local_share = home / DIR_LOCAL / "share"
    zsh_plugins = [
        (
            "fzf-tab completion menu",
            FILE_FZF_TAB,
            [
                Path("/opt/homebrew/opt/fzf-tab/share/fzf-tab") / FILE_FZF_TAB,
                Path("/usr/share/fzf-tab") / FILE_FZF_TAB,
                Path("/home/linuxbrew/.linuxbrew/opt/fzf-tab/share/fzf-tab") / FILE_FZF_TAB,
                local_share / "fzf-tab" / FILE_FZF_TAB,
            ],
        ),
        (
            "zsh-autosuggestions",
            FILE_AUTOSUGGESTIONS,
            [
                Path("/opt/homebrew/share/zsh-autosuggestions") / FILE_AUTOSUGGESTIONS,
                Path("/home/linuxbrew/.linuxbrew/share/zsh-autosuggestions") / FILE_AUTOSUGGESTIONS,
                Path("/usr/share/zsh-autosuggestions") / FILE_AUTOSUGGESTIONS,
                Path("/usr/share/zsh/plugins/zsh-autosuggestions") / FILE_AUTOSUGGESTIONS,
                local_share / "zsh-autosuggestions" / FILE_AUTOSUGGESTIONS,
            ],
        ),
        (
            "zsh-syntax-highlighting",
            FILE_SYNTAX_HIGHLIGHTING,
            [
                Path("/opt/homebrew/share/zsh-syntax-highlighting") / FILE_SYNTAX_HIGHLIGHTING,
                Path("/home/linuxbrew/.linuxbrew/share/zsh-syntax-highlighting") / FILE_SYNTAX_HIGHLIGHTING,
                Path("/usr/share/zsh-syntax-highlighting") / FILE_SYNTAX_HIGHLIGHTING,
                Path("/usr/share/zsh/plugins/zsh-syntax-highlighting") / FILE_SYNTAX_HIGHLIGHTING,
                local_share / "zsh-syntax-highlighting" / FILE_SYNTAX_HIGHLIGHTING,
            ],
        ),
    ]
    brew_plugins = {FILE_FZF_TAB, FILE_AUTOSUGGESTIONS, FILE_SYNTAX_HIGHLIGHTING}
    for plugin_label, plugin_file, candidates in zsh_plugins:
        found = next((p for p in candidates if p.is_file()), None)
        if found:
            report.ok(plugin_label, str(found).replace(str(home), "~")[:38])
            continue
        pkg = plugin_file.replace(".zsh", "")
        if shutil.which("brew") and plugin_file in brew_plugins and _should_brew_install(plugin_label, pkg, fix):
            print(f"  \033[1;34m==>\033[0m Installing {pkg} via brew...")
            code, _, _ = run_cmd(["brew", "install", pkg], timeout=600)
            if code == 0:
                report.fixed(plugin_label, f"Installed {pkg} via brew")
                continue
        report.warn(plugin_label, f"{plugin_file} not found")


def _classify_mise_runtimes(mise_data: dict) -> tuple[list[str], list[str]]:
    """Classify Mise runtimes into active and missing lists."""
    active_tools: list[str] = []
    missing_tools: list[str] = []
    for tool_name, entries in mise_data.items():
        for item in entries:
            ver = item.get("version") or item.get("requested_version") or "unknown"
            target = active_tools if item.get("installed", False) else missing_tools
            target.append(f"{tool_name}@{ver}")
    return active_tools, missing_tools


def _check_mise_runtimes(report: DoctorReport, fix: bool) -> None:
    """Audit or install Mise managed runtimes declared in config/mise/config.toml."""
    if not shutil.which("mise"):
        return
    code, raw_json, _ = run_cmd(["mise", "ls", "--current", "--json"])
    if code != 0 or not raw_json:
        return
    try:
        mise_data = json.loads(raw_json)
        active_tools, missing_tools = _classify_mise_runtimes(mise_data)
    except (ValueError, AttributeError, TypeError):
        report.warn(LBL_MISE_RUNTIMES, "Unexpected 'mise ls --json' output")
        return

    if missing_tools:
        joined = ", ".join(missing_tools)
        if fix and run_cmd(["mise", "install"], timeout=600)[0] == 0:
            report.fixed(LBL_MISE_RUNTIMES, f"Installed {joined}")
        else:
            report.warn(LBL_MISE_RUNTIMES, f"Missing: {joined} (run 'mise install')")
    elif active_tools:
        report.ok(LBL_MISE_RUNTIMES, ", ".join(active_tools)[:38])


def _clean_empty_nvim_pack_core(home: Path) -> None:
    """Remove empty Neovim 0.12+ site/pack/core directories that trigger healthcheck warnings."""
    nvim_data = Path(os.environ.get("XDG_DATA_HOME", str(home / DIR_LOCAL / "share"))) / "nvim"
    pack_core = nvim_data / "site" / "pack" / "core"
    if not pack_core.is_dir():
        return
    with contextlib.suppress(OSError):
        for sub in (pack_core / "opt", pack_core / "start", pack_core, pack_core.parent):
            if sub.is_dir() and not any(sub.iterdir()):
                sub.rmdir()


def _parse_nvim_health_output(content: str) -> tuple[list[str], list[str]]:
    """Extract non-provider error and warning lines from Neovim :checkhealth output."""
    errors: list[str] = []
    warnings: list[str] = []
    for section in content.split("=============================================================================="):
        lines = section.strip().splitlines()
        if not lines or "vim.provider" in lines[0]:
            continue
        for raw_line in lines[1:]:
            item_line = raw_line.strip()
            if item_line.startswith(("- ❌", "- ERROR")) or "ERROR" in item_line:
                errors.append(item_line)
            elif item_line.startswith(("- ⚠️", "- WARNING")) or "WARNING" in item_line:
                warnings.append(item_line)
    return errors, warnings


def _check_neovim_health(report: DoctorReport, home: Path, fix: bool) -> None:
    """Run headless Neovim :checkhealth and report errors or warnings."""
    if not shutil.which("nvim"):
        return
    if fix:
        _clean_empty_nvim_pack_core(home)

    with tempfile.NamedTemporaryFile(mode="w+", prefix="nvim_health_", suffix=".txt", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    try:
        nvim_env = os.environ.copy()
        if not nvim_env.get("TERM") or nvim_env.get("TERM") == "dumb":
            nvim_env["TERM"] = "xterm-256color"
        res = subprocess.run(
            ["nvim", "--headless", "+checkhealth", f"+w! {tmp_path}", "+qa"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=15,
            env=nvim_env,
            check=False,
        )
        content = tmp_path.read_text(encoding="utf-8", errors="replace") if tmp_path.exists() else ""
        errors, warnings = _parse_nvim_health_output(content)
        if res.returncode != 0 and not content:
            report.warn(LBL_NVIM_HEALTH, "Non-zero exit running headless checkhealth")
        elif errors:
            first_err = errors[0].replace("- ❌ ERROR ", "").replace("- ❌ ", "").replace("- ERROR ", "")[:38]
            report.fail(LBL_NVIM_HEALTH, f"{len(errors)} error(s): {first_err}")
        elif warnings:
            first_warn = warnings[0].replace("- ⚠️ WARNING ", "").replace("- ⚠️ ", "").replace("- WARNING ", "")[:38]
            report.warn(LBL_NVIM_HEALTH, f"{len(warnings)} warning(s): {first_warn}")
        else:
            report.ok(LBL_NVIM_HEALTH, "0 errors, 0 warnings")
    except subprocess.TimeoutExpired:
        report.warn(LBL_NVIM_HEALTH, "Timed out after 15s")
    except (OSError, subprocess.SubprocessError) as e:
        report.warn(LBL_NVIM_HEALTH, f"Check error: {e}")
    finally:
        with contextlib.suppress(OSError):
            tmp_path.unlink(missing_ok=True)


def check_cli_tools(report: DoctorReport, fix: bool = False):
    """Audit installed CLI binaries, Zsh prompt/plugins, Mise runtimes, and Neovim health."""
    print(f"\n{C_BOLD}3. Core CLI & Runtime Tools{C_RESET}")
    for tool in get_cli_tool_manifest():
        _check_single_cli_tool(report, tool, fix)

    home = Path.home()
    _check_active_prompt_health(report, home, fix)
    _check_zsh_plugins(report, home, fix)
    _check_mise_runtimes(report, fix)
    _check_neovim_health(report, home, fix)


def check_locale(report: DoctorReport):
    """Check active terminal locale and Zsh UTF-8 multibyte character evaluation."""
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
        code, _out, _ = run_cmd(["zsh", "-c", '[ "${#${:-🐧}}" -eq 1 ]'])
        if code == 0:
            report.ok("Zsh multibyte parsing", "Single-char UTF-8 glyphs confirmed")
        else:
            report.warn("Zsh multibyte parsing", "Single-byte mode active; check ~/.zshenv")


def _check_ssh_agent_and_keys(report: DoctorReport) -> None:
    """Audit SSH agent reachability and local `~/.ssh` key pair presence."""
    # ssh-add exit codes: 0 = keys loaded, 1 = agent running without keys, 2 = no agent
    code, _, _ = run_cmd(["ssh-add", "-l"])
    if code == 0:
        report.ok(LBL_SSH_AGENT, "Running with keys loaded")
    elif code == 1:
        report.ok(LBL_SSH_AGENT, "Running (keys load on first use)")
    else:
        report.warn(LBL_SSH_AGENT, "Not reachable; open a new shell to start the shared agent")

    ssh_dir = Path.home() / ".ssh"
    key_candidates = ("id_ed25519", "id_rsa", "id_ecdsa", "id_ed25519_sk")
    found_key = next((k for k in key_candidates if (ssh_dir / k).is_file() or (ssh_dir / f"{k}.pub").is_file()), None)
    if found_key:
        report.ok("SSH key pair", f"~/.ssh/{found_key}")
    elif code == 0:
        report.ok("SSH key pair", "Managed by external/hardware SSH agent")
    else:
        report.warn("SSH key pair", "No key in ~/.ssh (run 'ssh-keygen -t ed25519')")


def _check_sensitive_permissions(report: DoctorReport, path: Path, expected_mode: int, label: str, fix: bool) -> None:
    """Audit permissions on sensitive credential/config paths and chmod on fix."""
    if not path.exists():
        return
    try:
        curr_mode = path.stat().st_mode & 0o777
    except OSError:
        return
    if curr_mode == expected_mode:
        report.ok(label, f"Permissions {oct(curr_mode)} (secure)")
    elif fix:
        try:
            path.chmod(expected_mode)
            report.fixed(label, f"Chmod {oct(curr_mode)} -> {oct(expected_mode)}")
        except OSError as exc:
            report.warn(label, f"Could not chmod to {oct(expected_mode)}: {exc}")
    else:
        report.warn(label, f"Permissive {oct(curr_mode)} (expected {oct(expected_mode)}). Run with --fix")


def check_ssh(report: DoctorReport, dotfiles: Path, fix: bool = False):
    """Audit `~/.ssh/config` shared defaults include, multiplexing sockets, and agent status."""
    print(f"\n{C_BOLD}6. SSH Agent & Defaults{C_RESET}")
    if not shutil.which("ssh"):
        report.warn("SSH", "ssh binary not installed")
        return

    ssh_dir = Path.home() / ".ssh"
    ssh_config = ssh_dir / "config"
    ssh_sockets = ssh_dir / "sockets"
    _check_sensitive_permissions(report, ssh_dir, 0o700, "~/.ssh directory permissions", fix)
    _check_sensitive_permissions(report, ssh_config, 0o600, "~/.ssh/config permissions", fix)
    if ssh_dir.is_dir():
        for k in sorted(ssh_dir.glob("id_*")):
            if not k.name.endswith(".pub") and k.is_file():
                _check_sensitive_permissions(report, k, 0o600, f"~/.ssh/{k.name} private key", fix)

    include = f"Include {dotfiles / 'config' / 'ssh' / 'dotfiles.conf'}"
    try:
        current = ssh_config.read_text()
    except OSError:
        current = ""
    if include in current.splitlines():
        report.ok(LBL_SSH_CONFIG, "Includes shared dotfiles defaults")
    elif fix:
        ssh_config.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        ssh_config.write_text(f"{include}\n\n{current}")
        ssh_config.chmod(0o600)
        report.fixed(LBL_SSH_CONFIG, "Prepended Include for shared defaults")
    else:
        report.warn(LBL_SSH_CONFIG, "Missing shared defaults Include. Run with --fix")

    if ssh_sockets.is_dir():
        report.ok(LBL_SSH_SOCKETS, "SSH ControlMaster multiplexing ready")
    elif fix:
        ssh_sockets.mkdir(mode=0o700, parents=True, exist_ok=True)
        report.fixed(LBL_SSH_SOCKETS, "Created directory for SSH multiplexing")
    else:
        report.warn(LBL_SSH_SOCKETS, "Missing ControlPath socket directory. Run with --fix")

    _check_ssh_agent_and_keys(report)


# gpg-agent forgets passphrases after 10 minutes by default, so signing from editors and TUIs
# (which can't show a terminal pinentry) breaks soon after an unlock. Remember them for a working day.
GPG_CACHE_TTL = {"default-cache-ttl": 28800, "max-cache-ttl": 86400}


def check_gpg_cache(report: DoctorReport, fix: bool = False):
    """Audit or extend `gpg-agent.conf` passphrase cache TTLs for non-TTY commit signing."""
    home = Path(os.environ.get("GNUPGHOME", Path.home() / ".gnupg"))
    _check_sensitive_permissions(report, home, 0o700, "~/.gnupg directory permissions", fix)
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
        report.ok(LBL_GPG_CACHE, f"{ttl // 3600}h after unlock")
    elif fix:
        kept = [line for line in lines if not line.split() or line.split()[0] not in GPG_CACHE_TTL]
        kept += [f"{key} {value}" for key, value in GPG_CACHE_TTL.items()]
        home.mkdir(mode=0o700, parents=True, exist_ok=True)
        conf.write_text("\n".join(kept) + "\n")
        run_cmd(["gpg-connect-agent", "reloadagent", "/bye"])
        report.fixed(LBL_GPG_CACHE, "Raised to 8h (max 24h); unlock once to start it")
    else:
        report.warn(LBL_GPG_CACHE, f"Only {ttl // 60} min; signing outside a terminal fails. Run with --fix")


def _check_git_identity_config(report: DoctorReport, fix: bool = False) -> None:
    """Audit `~/.gitconfig.local`, `user.name`, and `user.email`."""
    local_gitconfig = Path.home() / ".gitconfig.local"
    _, name, _ = run_cmd(["git", "config", "--get", "user.name"])
    _, email, _ = run_cmd(["git", "config", "--get", "user.email"])
    if local_gitconfig.is_file():
        report.ok("~/.gitconfig.local", "Local Git credentials override active")
        _check_sensitive_permissions(report, local_gitconfig, 0o600, "~/.gitconfig.local permissions", fix)
    elif name and email:
        report.ok("~/.gitconfig.local", "Optional (identity set in global config)")
    else:
        report.warn("~/.gitconfig.local", "Missing; create to store user.name & user.email")

    if name:
        report.ok("Git user.name", name)
    else:
        report.warn("Git user.name", "Not set (configure in ~/.gitconfig.local)")

    if email:
        report.ok("Git user.email", email)
    else:
        report.warn("Git user.email", "Not set (configure in ~/.gitconfig.local)")


def check_git_signing(report: DoctorReport, fix: bool = False):
    """Audit Git user identity (`user.name`, `user.email`), `~/.gitconfig.local`, and commit signing."""
    print(f"\n{C_BOLD}5. Git Identity & Commit Signing{C_RESET}")
    if not shutil.which("git"):
        report.warn("Git config", "git binary not installed")
        return

    _check_git_identity_config(report, fix=fix)

    _, sign, _ = run_cmd(["git", "config", "--get", "commit.gpgsign"])
    _, format_type, _ = run_cmd(["git", "config", "--get", "gpg.format"])
    _, signing_key, _ = run_cmd(["git", "config", "--get", "user.signingkey"])

    if sign == "true":
        key_desc = f"{format_type or 'gpg'} ({signing_key})" if signing_key else "Enabled"
        if format_type == "ssh" and signing_key and not signing_key.startswith("ssh-"):
            key_path = Path(signing_key).expanduser()
            if not key_path.is_file():
                report.warn("Commit signing", f"SSH signing key missing: {signing_key}")
                return
        report.ok("Commit signing", key_desc)
        if format_type in ("", "openpgp") and shutil.which("gpg"):
            check_gpg_cache(report, fix=fix)
    else:
        report.ok("Commit signing", "Disabled (optional)")


def is_wsl() -> bool:
    """Return True when running inside Windows Subsystem for Linux (WSL)."""
    if os.environ.get("WSL_DISTRO_NAME"):
        return True
    try:
        return "microsoft" in Path("/proc/version").read_text().lower()
    except OSError:
        return False


def _find_windows_terminal_settings() -> Optional[Path]:
    """Locate Windows Terminal settings.json on the Windows host from inside WSL."""
    if not shutil.which("powershell.exe") or not shutil.which("wslpath"):
        return None
    code, win_appdata, _ = run_cmd(["powershell.exe", "-NoProfile", "-Command", "$env:LOCALAPPDATA"])
    win_appdata = win_appdata.strip().replace("\r", "")
    if code != 0 or not win_appdata:
        return None
    code, mounted, _ = run_cmd(["wslpath", win_appdata])
    mounted = mounted.strip()
    if code != 0 or not mounted:
        return None
    base = Path(mounted)
    candidates = [
        base / "Packages" / "Microsoft.WindowsTerminal_8wekyb3d8bbwe" / "LocalState" / FILE_SETTINGS_JSON,
        base / "Packages" / "Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe" / "LocalState" / FILE_SETTINGS_JSON,
        base / "Microsoft" / "Windows Terminal" / FILE_SETTINGS_JSON,
    ]
    return next((p for p in candidates if p.is_file()), None)


def _check_windows_terminal_theme(report: DoctorReport, dotfiles: Path, fix: bool) -> None:
    """Audit or sync the Windows Terminal Catppuccin Mocha theme from WSL."""
    wt_settings = _find_windows_terminal_settings()
    if not wt_settings:
        return
    try:
        wt_text = wt_settings.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        wt_text = ""

    if '"Catppuccin Mocha"' in wt_text:
        report.ok(LBL_WT_THEME, "Catppuccin Mocha & Nerd Fonts active")
        return

    setup_script = dotfiles / "bin" / "wsl-setup-terminal"
    if fix and setup_script.is_file():
        code, _, _ = run_cmd([str(setup_script)])
        if code == 0:
            report.fixed(LBL_WT_THEME, "Synced Catppuccin Mocha via wsl-setup-terminal")
        else:
            report.warn(LBL_WT_THEME, "wsl-setup-terminal failed")
        return

    report.warn(LBL_WT_THEME, "Not synced. Run 'wsl-setup-terminal' or 'dot doctor --fix'")


def check_wsl(report: DoctorReport, dotfiles: Path, fix: bool = False):
    """Audit WSL filesystem placement, `win32yank.exe`, `wslview`, and Windows Terminal theme."""
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

    _check_windows_terminal_theme(report, dotfiles, fix)


def _run_all_doctor_checks(report: DoctorReport, dotfiles: Path, fix: bool) -> None:
    """Execute all doctor check suites in order."""
    check_repository(report, dotfiles)
    check_zsh_bytecode(report, dotfiles, fix=fix)
    check_and_heal_symlinks(report, dotfiles, fix=fix)
    check_cli_tools(report, fix=fix)
    check_locale(report)
    check_git_signing(report, fix=fix)
    check_ssh(report, dotfiles, fix=fix)
    if is_wsl():
        check_wsl(report, dotfiles, fix=fix)


def run_doctor(fix: bool = False, json_output: bool = False) -> int:
    """Run all workstation health checks and optionally auto-repair issues when `fix` is True."""
    dotfiles = get_dotfiles_dir()
    report = DoctorReport()

    if json_output:
        import io
        with contextlib.redirect_stdout(io.StringIO()):
            _run_all_doctor_checks(report, dotfiles, fix)
        payload = {
            "passed": report.passed,
            "warnings": report.warnings,
            "failed": report.failed,
            "repaired": report.repaired,
            "checks": report.entries,
        }
        print(json.dumps(payload, indent=2))
        return 1 if report.failed > 0 else 0

    header_text = "Dotfiles Doctor \u2014 System & Environment Health Check"
    if fix:
        header_text += " [FIX]"

    print_header(header_text)
    _run_all_doctor_checks(report, dotfiles, fix)

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
    do_json = "--json" in sys.argv or "-j" in sys.argv
    sys.exit(run_doctor(fix=do_fix, json_output=do_json))
