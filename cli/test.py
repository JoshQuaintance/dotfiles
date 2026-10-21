"""`dot test`: deep runtime, configuration schema, and CLI integration test runner."""

import contextlib
import io
import json
import os
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path
from unittest.mock import patch

try:
    import tomllib  # Python 3.11+
except ImportError:
    tomllib = None

from cli.manifest import get_cli_tool_manifest, get_dotfiles_dir, get_symlink_manifest
from cli.prompt import get_active_prompt, is_mobile_or_proot
from cli.prune import COMPLETION_DIRS, COMPLETIONS_DIR, find_stale_caches
from cli.ui import (
    C_BOLD,
    C_DIM,
    C_GREEN,
    C_RED,
    C_RESET,
    C_YELLOW,
    ICON_OK,
    ICON_WARN,
    box,
    format_row,
    print_header,
    run_cmd,
)

JSONC_TOKEN_RE = re.compile(
    r'"(?:\\.|[^"\\])*"'  # Double-quoted string literal
    r"|//[^\n]*"          # Single-line // comment
    r"|/\*[\s\S]*?\*/",   # Block /* ... */ comment
)


class TestReport:
    """Track and display pass, warning, and failure counts for `dot test`."""

    def __init__(self):
        """Initialize counters for test suite checks."""
        self.passed = 0
        self.warnings = 0
        self.failed = 0

    def ok(self, label: str, detail: str = ""):
        """Record and print a passing integration check."""
        self.passed += 1
        print(f"  {C_GREEN}✔{C_RESET} {label:<44} {C_DIM}{detail}{C_RESET}")

    def warn(self, label: str, detail: str = ""):
        """Record and print a non-fatal test warning."""
        self.warnings += 1
        print(f"  {C_YELLOW}⚠{C_RESET} {label:<44} {C_YELLOW}{detail}{C_RESET}")

    def fail(self, label: str, detail: str = ""):
        """Record and print a failing integration check."""
        self.failed += 1
        print(f"  {C_RED}✖{C_RESET} {C_BOLD}{label:<44}{C_RESET} {C_RED}{detail}{C_RESET}")


def _strip_jsonc_comments(text: str) -> str:
    """Strip // and /* */ comments outside JSON string literals and remove trailing commas."""
    cleaned = JSONC_TOKEN_RE.sub(lambda m: m.group(0) if m.group(0).startswith('"') else "", text)
    return re.sub(r",(\s*[}\]])", r"\1", cleaned)


def parse_jsonc(filepath: Path) -> dict:
    """Parse JSON with comments and trailing commas (standard VS Code JSONC format)."""
    text = filepath.read_text(encoding="utf-8")
    return json.loads(_strip_jsonc_comments(text))


def _check_json_schemas(report: TestReport, dotfiles: Path) -> None:
    """Validate VS Code JSONC and Windows Terminal JSON settings."""
    vscode_settings = dotfiles / "config" / "vscode" / "settings.json"
    if vscode_settings.exists():
        try:
            data = parse_jsonc(vscode_settings)
            theme = data.get("workbench.colorTheme", "default")
            report.ok("VS Code settings (JSONC)", f"Valid schema (theme: {theme})")
        except (OSError, ValueError, AttributeError) as e:
            report.fail("VS Code settings (JSONC)", f"Parse error: {e}")
    else:
        report.warn("VS Code settings (JSONC)", "File missing in repo")

    wt_settings = dotfiles / "config" / "windows-terminal" / "settings.json"
    if wt_settings.exists():
        try:
            json.loads(wt_settings.read_text(encoding="utf-8"))
            report.ok("Windows Terminal configuration", "settings.json valid JSON")
        except (OSError, ValueError) as e:
            report.fail("Windows Terminal configuration", f"Invalid JSON: {e}")


def _check_yazi_schemas(report: TestReport, dotfiles: Path) -> None:
    """Validate Yazi TOML files (yazi.toml, theme.toml, keymap.toml)."""
    yazi_toml = dotfiles / "config" / "yazi" / "yazi.toml"
    theme_toml = dotfiles / "config" / "yazi" / "theme.toml"
    keymap_toml = dotfiles / "config" / "yazi" / "keymap.toml"
    if yazi_toml.exists() and theme_toml.exists():
        if tomllib:
            try:
                for p in (yazi_toml, theme_toml, keymap_toml):
                    if p.exists():
                        tomllib.loads(p.read_text(encoding="utf-8"))
                report.ok("Yazi configuration", "yazi.toml, theme.toml & keymap.toml valid TOML")
            except (OSError, ValueError) as e:
                report.fail("Yazi configuration", f"TOML parse error: {e}")
        else:
            report.ok("Yazi configuration", "Files present (tomllib skipped)")
    else:
        report.warn("Yazi configuration", "Configs not found")


def _check_ghostty_and_nvim(report: TestReport) -> None:
    """Validate Ghostty terminal config and Neovim headless initialization."""
    ghostty_bin = shutil.which("ghostty")
    if not ghostty_bin and Path("/Applications/Ghostty.app/Contents/MacOS/ghostty").is_file():
        ghostty_bin = "/Applications/Ghostty.app/Contents/MacOS/ghostty"
    if ghostty_bin:
        code, _out, err = run_cmd([ghostty_bin, "+validate-config"])
        if code == 0:
            report.ok("Ghostty terminal configuration", "ghostty +validate-config valid")
        else:
            report.fail("Ghostty terminal configuration", err.splitlines()[0] if err else "Validation failed")
    else:
        report.warn("Ghostty terminal configuration", "ghostty not installed (skipped)")

    if shutil.which("nvim"):
        code, _out, err = run_cmd(["nvim", "--headless", "+qa"])
        if code == 0:
            detail = "Lua config & plugins clean" if not err.strip() else "Boots clean (minor warnings)"
            report.ok("Neovim headless initialization", detail)
        else:
            report.fail("Neovim headless initialization", err.splitlines()[0] if err else "Exit non-zero")
    else:
        report.warn("Neovim headless initialization", "nvim binary not found (skipped)")


def _check_cli_tool_configs(report: TestReport, dotfiles: Path) -> None:
    """Validate Spaceship, prompt.zsh, bat, eza, mise, and .gitconfig files."""
    for label, rel_path in (
        ("Spaceship prompt configuration", "config/spaceship/spaceship.zsh"),
        ("Unified prompt manager script", "zsh/prompt.zsh"),
    ):
        cfg = dotfiles / rel_path
        if cfg.exists() and shutil.which("zsh"):
            code, _out, err = run_cmd(["zsh", "-n", str(cfg)])
            if code == 0:
                report.ok(label, f"{rel_path} valid Zsh")
            else:
                report.fail(label, err.splitlines()[0] if err else "Syntax error")

    bat_config = dotfiles / "config" / "bat" / "config"
    if bat_config.exists():
        content = bat_config.read_text(encoding="utf-8")
        detail = "Catppuccin Mocha active" if "Catppuccin Mocha" in content else "Config present"
        report.ok("Bat syntax viewer theme", detail)

    if (dotfiles / "config" / "eza" / "theme.yml").exists():
        report.ok("Eza theme configuration", "config/eza/theme.yml present")

    mise_toml = dotfiles / "config" / "mise" / "config.toml"
    if mise_toml.exists() and tomllib:
        try:
            tomllib.loads(mise_toml.read_text(encoding="utf-8"))
            report.ok("Mise runtime configuration", "config/mise/config.toml valid TOML")
        except (OSError, ValueError) as e:
            report.fail("Mise runtime configuration", f"Invalid TOML: {e}")

    gitconfig = dotfiles / "config" / "git" / ".gitconfig"
    if gitconfig.exists():
        code, _out, _err = run_cmd(["git", "config", "-f", str(gitconfig), "--list"])
        if code == 0:
            report.ok("Git configuration", ".gitconfig syntax valid")
        else:
            report.fail("Git configuration", ".gitconfig syntax error")


def test_parsers_and_schemas(report: TestReport, dotfiles: Path):
    """Run all configuration file parser and schema validation checks."""
    print(f"\n{C_BOLD}1. Configuration & Runtime Parsers{C_RESET}")
    _check_json_schemas(report, dotfiles)
    _check_yazi_schemas(report, dotfiles)
    _check_ghostty_and_nvim(report)
    _check_cli_tool_configs(report, dotfiles)


def _check_zsh_boot_and_latency(report: TestReport, zsh_env: dict[str, str]) -> None:
    """Measure interactive Zsh boot time and verify zero stderr startup errors."""
    t0 = time.perf_counter()
    _code, _out, err = run_cmd(["zsh", "-i", "+m", "-c", "exit"], timeout=10, env=zsh_env)
    elapsed_ms = int((time.perf_counter() - t0) * 1000)
    if elapsed_ms >= 350:
        t1 = time.perf_counter()
        _c2, _o2, err2 = run_cmd(["zsh", "-i", "+m", "-c", "exit"], timeout=10, env=zsh_env)
        elapsed_ms = min(elapsed_ms, int((time.perf_counter() - t1) * 1000))
        err = err or err2

    err_pattern = re.compile(
        r"command not found|parse error|syntax error|job table full|no such file|compinit: initialization aborted",
        re.IGNORECASE,
    )
    critical_errors = [line.strip() for line in err.splitlines() if err_pattern.search(line.strip())]

    if not critical_errors:
        report.ok("Interactive Zsh startup", f"0 errors on boot ({elapsed_ms}ms)")
    else:
        report.fail("Interactive Zsh startup", critical_errors[0])

    if elapsed_ms < 350:
        report.ok("Startup latency budget (<350ms)", f"Fast boot: {elapsed_ms}ms")
    else:
        report.warn("Startup latency budget (<350ms)", f"Exceeded target: {elapsed_ms}ms")


def _check_zsh_registries_and_reload(report: TestReport, zsh_env: dict[str, str]) -> None:
    """Verify registered functions, completions, clean reload, and namespace separation."""
    func_check_code = """
if (( ! ${#DOTFILES_FUNCTIONS[@]} )); then
    echo "Missing function: DOTFILES_FUNCTIONS registry is empty"
fi
for fn in "${DOTFILES_FUNCTIONS[@]}"; do
    if ! (( $+functions[$fn] )); then
        echo "Missing function: $fn"
    fi
done
echo "COUNT:${#DOTFILES_FUNCTIONS[@]}"
"""
    _code, out, _err = run_cmd(["zsh", "-i", "+m", "-c", func_check_code], timeout=5, env=zsh_env)
    missing_funcs = [line.strip() for line in out.splitlines() if line.startswith("Missing function:")]
    count_lines = [line.split(":", 1)[1] for line in out.splitlines() if line.startswith("COUNT:")]
    fn_count = count_lines[0] if count_lines else "all"
    if not missing_funcs:
        report.ok("Custom shell functions", f"All {fn_count} functions registered in zsh")
    else:
        report.fail("Custom shell functions", missing_funcs[0])

    comp_check_code = """
for comp in _git _uv _fzf_complete _dot _conf _up _proj _dotenv _comma _wt _gwtnew _gwtdel _pkg_scripts _fjq _extract _dotbranch; do
    if ! (( $+functions[$comp] )); then
        echo "Missing completion: $comp"
    fi
done
"""
    _code, out, _err = run_cmd(["zsh", "-i", "+m", "-c", comp_check_code], timeout=5, env=zsh_env)
    missing_comps = [line.strip() for line in out.splitlines() if line.startswith("Missing completion:")]
    if not missing_comps:
        report.ok(
            "Completions engine",
            "All completions active (_git, _uv, _fzf, _dot, _conf, _up, _proj, _dotenv, _comma, _wt, _gwtn, _gwtdel, _pkg_scripts, _fjq, _extract, _dotbranch)",
        )
    else:
        report.fail("Completions engine", missing_comps[0])

    _code, _out, err = run_cmd(["zsh", "-i", "+m", "-c", "source ~/.zshrc"], timeout=10, env=zsh_env)
    reload_re = re.compile(r"command not found|parse error|syntax error|defining function based on alias", re.IGNORECASE)
    reload_errors = [line.strip() for line in err.splitlines() if reload_re.search(line.strip())]
    if not reload_errors:
        report.ok("Shell reload / re-source", "0 errors on reload (source ~/.zshrc)")
    else:
        report.fail("Shell reload / re-source", reload_errors[0])

    collision_check_code = """
local -a collisions
for a in ${(k)aliases}; do
    if (( $+functions[$a] )); then
        collisions+=("$a")
    fi
done
print -l "${collisions[@]}"
"""
    _code, out, _err = run_cmd(["zsh", "-i", "+m", "-c", collision_check_code], timeout=5, env=zsh_env)
    collisions = [line.strip() for line in out.splitlines() if line.strip()]
    if not collisions:
        report.ok("Alias & function namespaces", "Clean separation (0 colliding names)")
    else:
        report.fail("Alias & function namespaces", f"Colliding alias/function: {', '.join(collisions)}")


def _check_zsh_smoke_and_unit_tests(report: TestReport, dotfiles: Path, zsh_env: dict[str, str]) -> None:
    """Run interactive CLI function smoke tests and the Zsh unit test harness."""
    smoke_test_code = f"""
set -e
# Universal functions
d -h >/dev/null
up -h >/dev/null
tree -h >/dev/null
tree 1 "{dotfiles}/zsh" >/dev/null
lt 1 "{dotfiles}/zsh" >/dev/null
conf -h >/dev/null
clone -h >/dev/null
fa -p >/dev/null
fenv -h >/dev/null
cheath -h >/dev/null
port -h >/dev/null
fkill -h >/dev/null
fcon -h >/dev/null
fssh -h >/dev/null
scratch -h >/dev/null
toggle-autonotify -h >/dev/null
take /tmp/test-smoke-take >/dev/null && cd - >/dev/null && rm -rf /tmp/test-smoke-take
notify "test" "dottest" >/dev/null
extract >/dev/null 2>&1 || true
pack -h >/dev/null
genignore -h >/dev/null
strdiff -h >/dev/null
strdiff "feat/SALES-1234/my-branch" "feat/SALES-1235/my_branch " >/dev/null
dotbranch -h >/dev/null
dotbranch -s >/dev/null
lastout -h >/dev/null
clip -h >/dev/null
, -h >/dev/null
, -l >/dev/null
netinfo -h >/dev/null
checksum -h >/dev/null
,net -h >/dev/null
,hash -h >/dev/null
decode -h >/dev/null
snip -h >/dev/null
fpkg -h >/dev/null
fsize -h >/dev/null
fknown -h >/dev/null
termtest -h >/dev/null
wpath -h >/dev/null
wcd -h >/dev/null

# Git-dependent functions (must run inside git repo)
(
    cd "{dotfiles}"
    groot >/dev/null
    gmain >/dev/null
    gwts >/dev/null
    gwtnew -h >/dev/null
    gwtenv -h >/dev/null
    gstash -h >/dev/null
    ga -h >/dev/null
    gfile -h >/dev/null
    gl -n 1 >/dev/null
)
"""
    code, _out, err = run_cmd(["zsh", "-i", "+m", "-c", smoke_test_code], timeout=10, env=zsh_env)
    if code == 0:
        report.ok("Function runtime execution", "Core custom functions run cleanly (smoke test)")
    else:
        report.fail("Function runtime execution", f"Smoke test failed (exit {code}): {err.strip()}")

    runner = dotfiles / "tests" / "zsh" / "run.zsh"
    if runner.is_file():
        code, out, err = run_cmd(["zsh", str(runner)], timeout=120)
        summary = next((line for line in reversed(out.splitlines()) if line.endswith("failed")), "no summary")
        if code == 0:
            report.ok("Zsh function unit tests", summary)
        else:
            failing = [line.strip().lstrip("✖ ") for line in out.splitlines() if "✖" in line]
            report.fail("Zsh function unit tests", f"{summary}: {', '.join(failing)[:60] or err.strip()[:60]}")


def test_shell_runtime(report: TestReport, dotfiles: Path):
    """Run interactive Zsh boot, completion, reload, smoke, and unit test suites."""
    print(f"\n{C_BOLD}2. Shell Runtime & Interactive Startup{C_RESET}")

    if not shutil.which("zsh"):
        report.fail("Interactive Zsh startup", "zsh binary not found")
        report.fail("Custom shell functions", "zsh binary not found")
        report.fail("Completions engine", "zsh binary not found")
        return

    zsh_env = {"DOTFILES_DIR": str(dotfiles), "ZSH_STARTUP_VERBOSE": "false", "TERM": "xterm-256color"}
    _check_zsh_boot_and_latency(report, zsh_env)
    _check_zsh_registries_and_reload(report, zsh_env)
    _check_zsh_smoke_and_unit_tests(report, dotfiles, zsh_env)


def _collect_bash_scripts(dotfiles: Path) -> list[Path]:
    """Return all executable/installer files with a bash or sh shebang."""
    candidates = [dotfiles / "install.sh", *(dotfiles / "install").glob("*.sh")]
    candidates.extend(p for p in (dotfiles / "bin").iterdir() if p.is_file())
    valid: list[Path] = []
    for script in candidates:
        if not script.is_file():
            continue
        try:
            with open(script, encoding="utf-8", errors="ignore") as f:
                if re.match(r"^#!.*(bash|sh)", f.readline()):
                    valid.append(script)
        except (OSError, ValueError):
            continue
    return valid


def _check_bash_scripts_syntax_and_lint(report: TestReport, dotfiles: Path) -> None:
    """Validate Bash syntax, ShellCheck, and shfmt formatting."""
    valid_bash_scripts = _collect_bash_scripts(dotfiles)
    bash_failed = False
    for script in valid_bash_scripts:
        if run_cmd(["bash", "-n", str(script)])[0] != 0:
            report.fail(f"Bash syntax: {script.name}", "Syntax error")
            bash_failed = True

    if not bash_failed:
        report.ok("Bash scripts syntax", "All bin/* and install/*.sh pass (bash -n)")

    if shutil.which("shellcheck") and valid_bash_scripts:
        sc_code, sc_out, sc_err = run_cmd(
            ["shellcheck", "--severity=warning", "-x", *[str(s) for s in valid_bash_scripts]],
            timeout=15,
        )
        if sc_code == 0:
            report.ok("ShellCheck static analysis", f"0 warnings/errors across {len(valid_bash_scripts)} scripts")
        else:
            first_issue = (sc_out or sc_err).splitlines()[0] if (sc_out or sc_err) else "Warnings found"
            report.fail("ShellCheck static analysis", first_issue[:48])

    if shutil.which("shfmt") and valid_bash_scripts:
        fmt_code, fmt_out, fmt_err = run_cmd(
            ["shfmt", "-l", "-i", "2", "-ci", *[str(s) for s in valid_bash_scripts]],
            timeout=10,
        )
        unformatted = [Path(line.strip()).name for line in fmt_out.splitlines() if line.strip()]
        if fmt_code == 0 and not unformatted:
            report.ok("shfmt script formatting", f"All {len(valid_bash_scripts)} bash scripts formatted (-i 2 -ci)")
        else:
            detail = (
                f"Run 'shfmt -w -i 2 -ci': {', '.join(unformatted[:4])}"
                if unformatted
                else (fmt_err[:40] or "Formatting mismatch")
            )
            report.fail("shfmt script formatting", detail)


def _check_zsh_scripts_syntax(report: TestReport, dotfiles: Path) -> None:
    """Validate Zsh script syntax across zsh/ and zsh/functions/."""
    if not shutil.which("zsh"):
        return
    zsh_scripts = [dotfiles / "zsh" / ".zshrc", dotfiles / "zsh" / ".zshenv", dotfiles / "zsh" / ".aliases"]
    zsh_scripts.extend((dotfiles / "zsh").glob("*.zsh"))
    zsh_scripts.extend((dotfiles / "zsh" / "functions").glob("*.zsh"))
    zsh_failed = False
    for zscript in zsh_scripts:
        if zscript.is_file() and run_cmd(["zsh", "-n", str(zscript)])[0] != 0:
            report.fail(f"Zsh syntax: {zscript.name}", "Syntax error")
            zsh_failed = True
    if not zsh_failed:
        report.ok("Zsh scripts syntax", "All zsh/* and functions pass (zsh -n)")


def _check_brewfile_and_symlinks(report: TestReport, dotfiles: Path) -> None:
    """Verify Brewfile formula parity with manifest and check for dangling symlinks."""
    brewfile = dotfiles / "Brewfile"
    if brewfile.is_file():
        brew_text = brewfile.read_text(encoding="utf-8")
        declared_brews = set(re.findall(r'^\s*brew\s+"([^"]+)"', brew_text, re.MULTILINE))
        missing_in_brewfile = [
            t.brew_formula
            for t in get_cli_tool_manifest()
            if t.brew_formula and t.brew_formula not in declared_brews
        ]
        if not missing_in_brewfile:
            report.ok("Tool manifest & Brewfile sync", "All Homebrew-managed CLI tools in Brewfile")
        else:
            report.fail("Tool manifest & Brewfile sync", f"Missing from Brewfile: {', '.join(missing_in_brewfile)}")

    dangling: list[str] = []
    for entry in get_symlink_manifest():
        link = entry.link_path
        if link.is_symlink():
            try:
                if not link.resolve().exists():
                    dangling.append(str(link).replace(str(Path.home()), "~"))
            except (OSError, RuntimeError):
                dangling.append(str(link).replace(str(Path.home()), "~"))

    if not dangling:
        report.ok("Symlink health", "All configuration symlinks point to valid targets")
    else:
        report.fail("Symlink health", f"Dangling symlinks: {', '.join(dangling)}")


def test_syntax_and_links(report: TestReport, dotfiles: Path):
    """Run Bash/Zsh syntax checks, ShellCheck, shfmt, Brewfile sync, and symlink checks."""
    print(f"\n{C_BOLD}3. Script Syntax & Link Integrity{C_RESET}")
    _check_bash_scripts_syntax_and_lint(report, dotfiles)
    _check_zsh_scripts_syntax(report, dotfiles)
    _check_brewfile_and_symlinks(report, dotfiles)


def _check_manifest_and_ui_primitives(report: TestReport) -> None:
    """Verify CLI tool manifest entries and responsive UI box/row clamping."""
    manifest_tools = get_cli_tool_manifest()
    dura_entry = next((t for t in manifest_tools if t.bin_name == "dura"), None)
    sevenzip_entry = next((t for t in manifest_tools if t.brew_formula == "sevenzip"), None)

    if dura_entry and dura_entry.brew_formula == "dura" and dura_entry.version_cmd == ["dura", "--version"]:
        report.ok("CLI manifest tool: dura", "Declared with brew formula and version command")
    else:
        report.fail("CLI manifest tool: dura", "Missing or invalid in get_cli_tool_manifest()")

    if (
        sevenzip_entry
        and hasattr(sevenzip_entry, "alt_bin_names")
        and {"7z", "7zz", "/usr/bin/7z"}.issubset(set(sevenzip_entry.alt_bin_names))
    ):
        report.ok("CLI manifest tool: 7-Zip alt names", f"Multi-binary parity: {sevenzip_entry.alt_bin_names}")
    else:
        report.fail("CLI manifest tool: 7-Zip alt names", "Missing 7z/7zz/p7zip alt_bin_names")

    box_desktop = box("Desktop Title", max_width=80)
    box_narrow = box("Extremely Long Title Designed To Exceed Narrow Terminal Width Clamping", max_width=40)
    box_min = box("Title", max_width=20)
    row_desktop = format_row("Tool Name", "Installed successfully", status_icon=ICON_OK, cols=80)
    row_narrow = format_row("Tool Name With Long Label", "Very detailed status text here", status_icon=ICON_WARN, cols=50)

    ui_valid = (
        len(box_desktop) == 3
        and "Desktop Title" in box_desktop[1]
        and len(box_narrow) == 3
        and "..." in box_narrow[1]
        and len(box_min) == 3
        and "Tool Name" in row_desktop
        and "..." in row_narrow
    )
    if ui_valid:
        report.ok("CLI UI rendering & viewport clamping", "box() & format_row() adapt to narrow (<60) & desktop widths")
    else:
        report.fail("CLI UI rendering & viewport clamping", "Unexpected box or row formatting")


def _check_mobile_and_prune_policies(report: TestReport) -> None:
    """Verify mobile/PRoot prompt auto-detection and prune cache invalidation rules."""
    clean_env = {
        "SSH_MOBILE": "",
        "_IS_MOBILE": "",
        "LC_TERMINAL": "",
        "TERM_PROGRAM": "xterm-256color",
        "TERMUX_VERSION": "",
        "PROOT_TMP_DIR": "",
        "DOTFILES_PROMPT": "",
    }
    mobile_checks_passed = True
    try:
        for env_override in (
            {"SSH_MOBILE": "1"},
            {"LC_TERMINAL": "Blink"},
            {"LC_TERMINAL": "Termius"},
            {"TERM_PROGRAM": "blink"},
        ):
            with patch.dict(os.environ, {**clean_env, **env_override}):
                assert is_mobile_or_proot() is True

        with patch.dict(os.environ, {**clean_env, "DOTFILES_PROMPT": "spaceship", "SSH_MOBILE": "1"}):
            engine, src = get_active_prompt()
            assert engine == "spaceship" and "DOTFILES_PROMPT" in src
        with patch.dict(os.environ, {**clean_env, "SSH_MOBILE": "1"}):
            engine, src = get_active_prompt()
            assert engine == "native" and "mobile/PRoot" in src
    except AssertionError:
        mobile_checks_passed = False

    if mobile_checks_passed:
        report.ok("Mobile prompt detection & precedence", "SSH_MOBILE, Blink, Termius detected; env override preserved")
    else:
        report.fail("Mobile prompt detection & precedence", "Assertion failed during mobile detection")

    prune_checks_passed = True
    try:
        assert COMPLETIONS_DIR == COMPLETION_DIRS
        assert {"zsh/functions/", "zsh/completions/", "zsh/custom/completions/"}.issubset(set(COMPLETION_DIRS))

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            zcomp = tmp_path / ".zcompdump-test"
            zcomp.touch()
            with patch.dict(os.environ, {"ZDOTDIR": str(tmp_path)}):
                for rel_file in ("zsh/functions/git.zsh", "zsh/completions/_foo", "zsh/custom/completions/_bar"):
                    assert zcomp in find_stale_caches(tmp_path, {rel_file})
                assert zcomp not in find_stale_caches(tmp_path, {"config/git/.gitconfig"})

                zwc_file = tmp_path / "zsh" / "old.zsh.zwc"
                zwc_file.parent.mkdir(parents=True, exist_ok=True)
                zwc_file.touch()
                assert zwc_file in find_stale_caches(tmp_path, {"zsh/old.zsh"})
    except AssertionError:
        prune_checks_passed = False

    if prune_checks_passed:
        report.ok("Prune cache invalidation logic", "COMPLETION_DIRS triggers compdump invalidation on source deletion")
    else:
        report.fail("Prune cache invalidation logic", "Assertion failed during prune cache test")


def _check_cli_subcommand_smoke(report: TestReport) -> None:
    """Execute read-only/dry-run smoke tests across CLI subcommands."""
    import cli.main

    subcommand_specs = [
        ("CLI smoke: status", ["dot", "status"], "Quick workstation status overview (read-only)", None),
        ("CLI smoke: doctor", ["dot", "doctor"], "Health audit & symlinks check (read-only)", [patch("cli.doctor.check_cli_tools")]),
        (
            "CLI smoke: prompt",
            ["dot", "prompt", "benchmark"],
            "Prompt latency & engine manager",
            [patch("cli.prompt.run_prompt_benchmark", return_value={"native": (0.1, 0.2, 0.3), "spaceship": (10.0, 15.0, 20.0)})],
        ),
        ("CLI smoke: clean (-n)", ["dot", "clean", "-n"], "Cache & temp files cleaner preview", None),
        ("CLI smoke: prune (-n)", ["dot", "prune", "-n"], "Upstream removed files preview", [patch("cli.prune._scan_roots", return_value=[])]),
        ("CLI smoke: sync (-n)", ["dot", "sync", "-n"], "Two-way git sync preview", None),
        ("CLI smoke: backup (-n)", ["dot", "backup", "-n"], "Local overrides & state snapshot preview", None),
        ("CLI smoke: env", ["dot", "env"], "Environment & $PATH shadowing audit", None),
    ]

    for label, argv, detail, patches in subcommand_specs:
        buf = io.StringIO()
        ctxs = [patch.object(sys, "argv", argv), contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf)]
        if patches:
            ctxs.extend(patches)
        with contextlib.ExitStack() as stack:
            for ctx in ctxs:
                stack.enter_context(ctx)
            try:
                cli.main.main()
                code, err_msg = 0, ""
            except SystemExit as e:
                code = e.code if isinstance(e.code, int) else 0
                err_msg = ""
            except (RuntimeError, OSError, ValueError, TypeError) as ex:
                code, err_msg = 1, str(ex)

        if code == 0:
            report.ok(label, detail)
        else:
            report.fail(label, err_msg or f"Exit non-zero ({code})")


def test_cli_architecture(report: TestReport, _dotfiles: Path):
    """Run manifest, UI viewport clamping, mobile policy, prune, and subcommand smoke tests."""
    print(f"\n{C_BOLD}4. Python CLI Subcommands & Architecture{C_RESET}")
    _check_manifest_and_ui_primitives(report)
    _check_mobile_and_prune_policies(report)
    _check_cli_subcommand_smoke(report)


def run_tests() -> int:
    """Execute the full deep integration test suite and return the exit code."""
    dotfiles = get_dotfiles_dir()
    report = TestReport()

    print_header("Dotfiles Test Suite \u2014 Deep Runtime & Schema Checker")

    test_parsers_and_schemas(report, dotfiles)
    test_shell_runtime(report, dotfiles)
    test_syntax_and_links(report, dotfiles)
    test_cli_architecture(report, dotfiles)

    print(
        f"\n{C_BOLD}Summary:{C_RESET} {C_GREEN}{report.passed} passed{C_RESET}, "
        f"{C_YELLOW}{report.warnings} warnings{C_RESET}, {C_RED}{report.failed} failed{C_RESET}\n"
    )

    if report.failed > 0:
        print(f"{C_RED}✖ Test suite failed! Please review the errors above.{C_RESET}\n")
        return 1

    print(f"{C_GREEN}✔ All deep integration tests passed successfully!{C_RESET}\n")
    return 0


if __name__ == "__main__":
    sys.exit(run_tests())
