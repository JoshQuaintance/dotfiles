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


class TestReport:
    def __init__(self):
        self.passed = 0
        self.warnings = 0
        self.failed = 0

    def ok(self, label: str, detail: str = ""):
        self.passed += 1
        print(f"  {C_GREEN}✔{C_RESET} {label:<44} {C_DIM}{detail}{C_RESET}")

    def warn(self, label: str, detail: str = ""):
        self.warnings += 1
        print(f"  {C_YELLOW}⚠{C_RESET} {label:<44} {C_YELLOW}{detail}{C_RESET}")

    def fail(self, label: str, detail: str = ""):
        self.failed += 1
        print(f"  {C_RED}✖{C_RESET} {C_BOLD}{label:<44}{C_RESET} {C_RED}{detail}{C_RESET}")


def parse_jsonc(filepath: Path) -> dict:
    """Parse JSON with comments and trailing commas (standard VS Code JSONC format)."""
    text = filepath.read_text(encoding="utf-8")
    result = []
    in_string = False
    escape = False
    i = 0
    n = len(text)

    while i < n:
        c = text[i]
        if in_string:
            result.append(c)
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == '"':
                in_string = False
            i += 1
            continue

        if c == '"':
            in_string = True
            result.append(c)
            i += 1
            continue

        # Single-line comment //
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            i += 2
            while i < n and text[i] != "\n":
                i += 1
            continue

        # Block comment /* ... */
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue

        result.append(c)
        i += 1

    cleaned = "".join(result)
    # Strip trailing commas
    while True:
        subbed = re.sub(r",(\s*[}\]])", r"\1", cleaned)
        if subbed == cleaned:
            break
        cleaned = subbed

    return json.loads(cleaned)


def test_parsers_and_schemas(report: TestReport, dotfiles: Path):
    print(f"\n{C_BOLD}1. Configuration & Runtime Parsers{C_RESET}")

    # VS Code JSONC
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

    # Windows Terminal settings.json
    wt_settings = dotfiles / "config" / "windows-terminal" / "settings.json"
    if wt_settings.exists():
        try:
            json.loads(wt_settings.read_text(encoding="utf-8"))
            report.ok("Windows Terminal configuration", "settings.json valid JSON")
        except (OSError, ValueError) as e:
            report.fail("Windows Terminal configuration", f"Invalid JSON: {e}")

    # Yazi TOML validation
    yazi_toml = dotfiles / "config" / "yazi" / "yazi.toml"
    theme_toml = dotfiles / "config" / "yazi" / "theme.toml"
    keymap_toml = dotfiles / "config" / "yazi" / "keymap.toml"
    if yazi_toml.exists() and theme_toml.exists():
        if tomllib:
            try:
                tomllib.loads(yazi_toml.read_text(encoding="utf-8"))
                tomllib.loads(theme_toml.read_text(encoding="utf-8"))
                if keymap_toml.exists():
                    tomllib.loads(keymap_toml.read_text(encoding="utf-8"))
                report.ok("Yazi configuration", "yazi.toml, theme.toml & keymap.toml valid TOML")
            except (OSError, ValueError) as e:
                report.fail("Yazi configuration", f"TOML parse error: {e}")
        else:
            report.ok("Yazi configuration", "Files present (tomllib skipped)")
    else:
        report.warn("Yazi configuration", "Configs not found")

    # Ghostty config validation
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

    # Neovim headless init
    if shutil.which("nvim"):
        code, _out, err = run_cmd(["nvim", "--headless", "+qa"])
        if code == 0 and not err.strip():
            report.ok("Neovim headless initialization", "Lua config & plugins clean")
        elif code == 0:
            report.ok("Neovim headless initialization", "Boots clean (minor warnings)")
        else:
            report.fail("Neovim headless initialization", err.splitlines()[0] if err else "Exit non-zero")
    else:
        report.warn("Neovim headless initialization", "nvim binary not found (skipped)")

    # Spaceship prompt config validation
    spaceship_cfg = dotfiles / "config" / "spaceship" / "spaceship.zsh"
    if spaceship_cfg.exists() and shutil.which("zsh"):
        code, _out, err = run_cmd(["zsh", "-n", str(spaceship_cfg)])
        if code == 0:
            report.ok("Spaceship prompt configuration", "config/spaceship/spaceship.zsh valid Zsh")
        else:
            report.fail("Spaceship prompt configuration", err.splitlines()[0] if err else "Syntax error")

    # Unified prompt manager script validation
    prompt_zsh = dotfiles / "zsh" / "prompt.zsh"
    if prompt_zsh.exists() and shutil.which("zsh"):
        code, _out, err = run_cmd(["zsh", "-n", str(prompt_zsh)])
        if code == 0:
            report.ok("Unified prompt manager script", "zsh/prompt.zsh valid Zsh")
        else:
            report.fail("Unified prompt manager script", err.splitlines()[0] if err else "Syntax error")

    # Bat syntax viewer config
    bat_config = dotfiles / "config" / "bat" / "config"
    if bat_config.exists():
        content = bat_config.read_text(encoding="utf-8")
        if "Catppuccin Mocha" in content:
            report.ok("Bat syntax viewer theme", "Catppuccin Mocha active")
        else:
            report.ok("Bat syntax viewer theme", "Config present")

    # Eza theme configuration
    eza_theme = dotfiles / "config" / "eza" / "theme.yml"
    if eza_theme.exists():
        report.ok("Eza theme configuration", "config/eza/theme.yml present")

    # Mise config validation
    mise_toml = dotfiles / "config" / "mise" / "config.toml"
    if mise_toml.exists() and tomllib:
        try:
            tomllib.loads(mise_toml.read_text(encoding="utf-8"))
            report.ok("Mise runtime configuration", "config/mise/config.toml valid TOML")
        except (OSError, ValueError) as e:
            report.fail("Mise runtime configuration", f"Invalid TOML: {e}")

    # Git config syntax validation
    gitconfig = dotfiles / "config" / "git" / ".gitconfig"
    if gitconfig.exists():
        code, _out, err = run_cmd(["git", "config", "-f", str(gitconfig), "--list"])
        if code == 0:
            report.ok("Git configuration", ".gitconfig syntax valid")
        else:
            report.fail("Git configuration", ".gitconfig syntax error")


def test_shell_runtime(report: TestReport, dotfiles: Path):
    print(f"\n{C_BOLD}2. Shell Runtime & Interactive Startup{C_RESET}")

    if not shutil.which("zsh"):
        report.fail("Interactive Zsh startup", "zsh binary not found")
        report.fail("Custom shell functions", "zsh binary not found")
        report.fail("Completions engine", "zsh binary not found")
        return

    zsh_env = {"DOTFILES_DIR": str(dotfiles), "ZSH_STARTUP_VERBOSE": "false", "TERM": "xterm-256color"}

    # Interactive boot test & stderr inspection
    # If the first run exceeds 350ms (e.g. rebuilding .zcompdump.zwc or tool init caches),
    # perform one warm run so cold cache generation does not trigger a false-positive warning.
    t0 = time.perf_counter()
    code, out, err = run_cmd(["zsh", "-i", "+m", "-c", "exit"], timeout=10, env=zsh_env)
    elapsed_ms = int((time.perf_counter() - t0) * 1000)
    if elapsed_ms >= 350:
        t1 = time.perf_counter()
        _c2, _o2, err2 = run_cmd(["zsh", "-i", "+m", "-c", "exit"], timeout=10, env=zsh_env)
        warm_ms = int((time.perf_counter() - t1) * 1000)
        elapsed_ms = min(elapsed_ms, warm_ms)
        if not err and err2:
            err = err2

    # Filter benign terminal warnings in headless CI
    critical_errors = []
    for line in err.splitlines():
        line_clean = line.strip()
        if re.search(r"command not found|parse error|syntax error|job table full|no such file|compinit: initialization aborted", line_clean, re.IGNORECASE):
            critical_errors.append(line_clean)

    if not critical_errors:
        report.ok("Interactive Zsh startup", f"0 errors on boot ({elapsed_ms}ms)")
    else:
        report.fail("Interactive Zsh startup", critical_errors[0])

    # Startup performance budget (< 350ms)
    if elapsed_ms < 350:
        report.ok("Startup latency budget (<350ms)", f"Fast boot: {elapsed_ms}ms")
    else:
        report.warn("Startup latency budget (<350ms)", f"Exceeded target: {elapsed_ms}ms")

    # Custom functions check (reads canonical DOTFILES_FUNCTIONS from zsh/functions.zsh)
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
    code, out, err = run_cmd(["zsh", "-i", "+m", "-c", func_check_code], timeout=5, env=zsh_env)
    missing_funcs = [line.strip() for line in out.splitlines() if line.startswith("Missing function:")]
    count_lines = [line.split(":", 1)[1] for line in out.splitlines() if line.startswith("COUNT:")]
    fn_count = count_lines[0] if count_lines else "all"
    if not missing_funcs:
        report.ok("Custom shell functions", f"All {fn_count} functions registered in zsh")
    else:
        report.fail("Custom shell functions", missing_funcs[0])

    # Completions engine
    comp_check_code = """
for comp in _git _uv _fzf_complete _dot _conf _up _proj _dotenv _comma _wt _gwtnew _gwtdel _pkg_scripts _fjq _extract _dotbranch; do
    if ! (( $+functions[$comp] )); then
        echo "Missing completion: $comp"
    fi
done
"""
    code, out, err = run_cmd(["zsh", "-i", "+m", "-c", comp_check_code], timeout=5, env=zsh_env)
    missing_comps = [line.strip() for line in out.splitlines() if line.startswith("Missing completion:")]
    if not missing_comps:
        report.ok("Completions engine", "All completions active (_git, _uv, _fzf, _dot, _conf, _up, _proj, _dotenv, _comma, _wt, _gwtn, _gwtdel, _pkg_scripts, _fjq, _extract, _dotbranch)")
    else:
        report.fail("Completions engine", missing_comps[0])

    # Shell reload / re-source test (guards against alias-function collisions on reload)
    reload_code = """
source ~/.zshrc
"""
    code, out, err = run_cmd(["zsh", "-i", "+m", "-c", reload_code], timeout=10, env=zsh_env)
    reload_errors = []
    for line in err.splitlines():
        line_clean = line.strip()
        if re.search(r"command not found|parse error|syntax error|defining function based on alias", line_clean, re.IGNORECASE):
            reload_errors.append(line_clean)
    if not reload_errors:
        report.ok("Shell reload / re-source", "0 errors on reload (source ~/.zshrc)")
    else:
        report.fail("Shell reload / re-source", reload_errors[0])

    # Alias & function namespace collision check
    collision_check_code = """
local -a collisions
for a in ${(k)aliases}; do
    if (( $+functions[$a] )); then
        collisions+=("$a")
    fi
done
print -l "${collisions[@]}"
"""
    code, out, err = run_cmd(["zsh", "-i", "+m", "-c", collision_check_code], timeout=5, env=zsh_env)
    collisions = [line.strip() for line in out.splitlines() if line.strip()]
    if not collisions:
        report.ok("Alias & function namespaces", "Clean separation (0 colliding names)")
    else:
        report.fail("Alias & function namespaces", f"Colliding alias/function: {', '.join(collisions)}")

    # Function runtime execution smoke test
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
    code, out, err = run_cmd(["zsh", "-i", "+m", "-c", smoke_test_code], timeout=10, env=zsh_env)
    if code == 0:
        report.ok("Function runtime execution", "Core custom functions run cleanly (smoke test)")
    else:
        report.fail("Function runtime execution", f"Smoke test failed (exit {code}): {err.strip()}")

    # Unit tests for zsh/functions (tests/zsh/test_*.zsh)
    runner = dotfiles / "tests" / "zsh" / "run.zsh"
    if runner.is_file():
        code, out, err = run_cmd(["zsh", str(runner)], timeout=120)
        summary = next((line for line in reversed(out.splitlines()) if line.endswith("failed")), "no summary")
        if code == 0:
            report.ok("Zsh function unit tests", summary)
        else:
            failing = [line.strip().lstrip("✖ ") for line in out.splitlines() if "✖" in line]
            report.fail("Zsh function unit tests", f"{summary}: {', '.join(failing)[:60] or err.strip()[:60]}")


def test_syntax_and_links(report: TestReport, dotfiles: Path):
    print(f"\n{C_BOLD}3. Script Syntax & Link Integrity{C_RESET}")

    # Bash scripts syntax (bash -n) & static analysis (shellcheck)
    bash_scripts = [dotfiles / "install.sh"]
    bash_scripts.extend((dotfiles / "install").glob("*.sh"))
    bash_scripts.extend([p for p in (dotfiles / "bin").iterdir() if p.is_file()])

    valid_bash_scripts: list[Path] = []
    bash_failed = False
    for script in bash_scripts:
        if not script.is_file():
            continue
        try:
            with open(script, encoding="utf-8", errors="ignore") as f:
                first_line = f.readline()
                if not re.match(r"^#!.*(bash|sh)", first_line):
                    continue
        except (OSError, ValueError):
            continue

        valid_bash_scripts.append(script)
        code, _out, _err = run_cmd(["bash", "-n", str(script)])
        if code != 0:
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
            detail = f"Run 'shfmt -w -i 2 -ci': {', '.join(unformatted[:4])}" if unformatted else (fmt_err[:40] or "Formatting mismatch")
            report.fail("shfmt script formatting", detail)

    # Zsh scripts syntax (zsh -n)
    if shutil.which("zsh"):
        zsh_scripts = [dotfiles / "zsh" / ".zshrc", dotfiles / "zsh" / ".zshenv", dotfiles / "zsh" / ".aliases"]
        zsh_scripts.extend((dotfiles / "zsh").glob("*.zsh"))
        zsh_scripts.extend((dotfiles / "zsh" / "functions").glob("*.zsh"))

        zsh_failed = False
        for zscript in zsh_scripts:
            if zscript.is_file():
                code, _out, _err = run_cmd(["zsh", "-n", str(zscript)])
                if code != 0:
                    report.fail(f"Zsh syntax: {zscript.name}", "Syntax error")
                    zsh_failed = True
        if not zsh_failed:
            report.ok("Zsh scripts syntax", "All zsh/* and functions pass (zsh -n)")

    # Tool manifest <-> Brewfile consistency check
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

    # Declarative symlink integrity & dangling checks (Includes VS Code)
    manifest = get_symlink_manifest()
    dangling: list[str] = []
    for entry in manifest:
        link = entry.link_path
        if link.is_symlink():
            try:
                dest = link.resolve()
                if not dest.exists():
                    dangling.append(str(link).replace(str(Path.home()), "~"))
            except (OSError, RuntimeError):
                dangling.append(str(link).replace(str(Path.home()), "~"))

    if not dangling:
        report.ok("Symlink health", "All configuration symlinks point to valid targets")
    else:
        report.fail("Symlink health", f"Dangling symlinks: {', '.join(dangling)}")


def test_cli_architecture(report: TestReport, dotfiles: Path):
    print(f"\n{C_BOLD}4. Python CLI Subcommands & Architecture{C_RESET}")

    # 1. Tool Manifest & Multi-Binary Parity (dura & 7-Zip)
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
        and "7z" in sevenzip_entry.alt_bin_names
        and "7zz" in sevenzip_entry.alt_bin_names
        and "/usr/bin/7z" in sevenzip_entry.alt_bin_names
    ):
        report.ok("CLI manifest tool: 7-Zip alt names", f"Multi-binary parity: {sevenzip_entry.alt_bin_names}")
    else:
        report.fail("CLI manifest tool: 7-Zip alt names", "Missing 7z/7zz/p7zip alt_bin_names")

    # 2. Terminal UI Responsive Rendering & Viewport Clamping
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

    # 3. Mobile Prompt Detection & Precedence Hierarchy
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
        with patch.dict(os.environ, {**clean_env, "SSH_MOBILE": "1"}):
            assert is_mobile_or_proot() is True
        with patch.dict(os.environ, {**clean_env, "LC_TERMINAL": "Blink"}):
            assert is_mobile_or_proot() is True
        with patch.dict(os.environ, {**clean_env, "LC_TERMINAL": "Termius"}):
            assert is_mobile_or_proot() is True
        with patch.dict(os.environ, {**clean_env, "TERM_PROGRAM": "blink"}):
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

    # 4. Prune Cache Invalidation Logic
    prune_checks_passed = True
    try:
        assert COMPLETIONS_DIR == COMPLETION_DIRS
        assert "zsh/functions/" in COMPLETION_DIRS
        assert "zsh/completions/" in COMPLETION_DIRS
        assert "zsh/custom/completions/" in COMPLETION_DIRS

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            zcomp = tmp_path / ".zcompdump-test"
            zcomp.touch()
            with patch.dict(os.environ, {"ZDOTDIR": str(tmp_path)}):
                c_fn = find_stale_caches(tmp_path, {"zsh/functions/git.zsh"})
                assert zcomp in c_fn
                c_comp = find_stale_caches(tmp_path, {"zsh/completions/_foo"})
                assert zcomp in c_comp
                c_custom = find_stale_caches(tmp_path, {"zsh/custom/completions/_bar"})
                assert zcomp in c_custom
                c_none = find_stale_caches(tmp_path, {"config/git/.gitconfig"})
                assert zcomp not in c_none

                # Stale .zwc file detection
                zwc_file = tmp_path / "zsh" / "old.zsh.zwc"
                zwc_file.parent.mkdir(parents=True, exist_ok=True)
                zwc_file.touch()
                c_zwc = find_stale_caches(tmp_path, {"zsh/old.zsh"})
                assert zwc_file in c_zwc
    except AssertionError:
        prune_checks_passed = False

    if prune_checks_passed:
        report.ok("Prune cache invalidation logic", "COMPLETION_DIRS triggers compdump invalidation on source deletion")
    else:
        report.fail("Prune cache invalidation logic", "Assertion failed during prune cache test")

    # 5. CLI Subcommands Smoke Test
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
                code = 0
                err_msg = ""
            except SystemExit as e:
                code = e.code if isinstance(e.code, int) else 0
                err_msg = ""
            except (RuntimeError, OSError, ValueError, TypeError) as ex:
                code = 1
                err_msg = str(ex)

        if code == 0:
            report.ok(label, detail)
        else:
            report.fail(label, err_msg or f"Exit non-zero ({code})")


def run_tests() -> int:
    dotfiles = get_dotfiles_dir()
    report = TestReport()

    print_header("Dotfiles Test Suite \u2014 Deep Runtime & Schema Checker")

    test_parsers_and_schemas(report, dotfiles)
    test_shell_runtime(report, dotfiles)
    test_syntax_and_links(report, dotfiles)
    test_cli_architecture(report, dotfiles)

    print(f"\n{C_BOLD}Summary:{C_RESET} {C_GREEN}{report.passed} passed{C_RESET}, {C_YELLOW}{report.warnings} warnings{C_RESET}, {C_RED}{report.failed} failed{C_RESET}\n")

    if report.failed > 0:
        print(f"{C_RED}✖ Test suite failed! Please review the errors above.{C_RESET}\n")
        return 1

    print(f"{C_GREEN}✔ All deep integration tests passed successfully!{C_RESET}\n")
    return 0

if __name__ == "__main__":
    sys.exit(run_tests())
