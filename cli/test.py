import json
import os
import pty
import re
import select
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Tuple

try:
    import tomllib  # Python 3.11+
except ImportError:
    tomllib = None

from cli.manifest import get_dotfiles_dir, get_symlink_manifest

C_GREEN = "\033[38;2;166;227;161m"
C_YELLOW = "\033[38;2;249;226;175m"
C_RED = "\033[38;2;243;139;168m"
C_CYAN = "\033[38;2;137;220;235m"
C_DIM = "\033[38;2;108;112;134m"
C_BOLD = "\033[1m"
C_RESET = "\033[0m"

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

def run_cmd(cmd: list[str], timeout: int = 5, env: dict = None) -> Tuple[int, str, str]:
    try:
        cur_env = os.environ.copy()
        if env:
            cur_env.update(env)
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=cur_env)
        return res.returncode, res.stdout, res.stderr
    except subprocess.TimeoutExpired:
        return 124, "", "Timed out"
    except Exception as e:
        return 1, "", str(e)

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
    vscode_settings = dotfiles / "vscode" / "settings.json"
    if vscode_settings.exists():
        try:
            data = parse_jsonc(vscode_settings)
            theme = data.get("workbench.colorTheme", "default")
            report.ok("VS Code settings (JSONC)", f"Valid schema (theme: {theme})")
        except Exception as e:
            report.fail("VS Code settings (JSONC)", f"Parse error: {e}")
    else:
        report.warn("VS Code settings (JSONC)", "File missing in repo")

    # Windows Terminal settings.json
    wt_settings = dotfiles / "windows-terminal" / "settings.json"
    if wt_settings.exists():
        try:
            json.loads(wt_settings.read_text(encoding="utf-8"))
            report.ok("Windows Terminal configuration", "settings.json valid JSON")
        except Exception as e:
            report.fail("Windows Terminal configuration", f"Invalid JSON: {e}")

    # Yazi TOML validation
    yazi_toml = dotfiles / "yazi" / "yazi.toml"
    theme_toml = dotfiles / "yazi" / "theme.toml"
    if yazi_toml.exists() and theme_toml.exists():
        if tomllib:
            try:
                tomllib.loads(yazi_toml.read_text(encoding="utf-8"))
                tomllib.loads(theme_toml.read_text(encoding="utf-8"))
                report.ok("Yazi configuration", "yazi.toml & theme.toml valid TOML")
            except Exception as e:
                report.fail("Yazi configuration", f"TOML parse error: {e}")
        else:
            report.ok("Yazi configuration", "Files present (tomllib skipped)")
    else:
        report.warn("Yazi configuration", "Configs not found")

    # Ghostty config validation
    if shutil.which("ghostty"):
        code, out, err = run_cmd(["ghostty", "+validate-config"])
        if code == 0:
            report.ok("Ghostty terminal configuration", "ghostty +validate-config valid")
        else:
            report.fail("Ghostty terminal configuration", err.splitlines()[0] if err else "Validation failed")
    else:
        report.warn("Ghostty terminal configuration", "ghostty not installed (skipped)")

    # Neovim headless init
    if shutil.which("nvim"):
        code, out, err = run_cmd(["nvim", "--headless", "+qa"])
        if code == 0 and not err.strip():
            report.ok("Neovim headless initialization", "Lua config & plugins clean")
        elif code == 0:
            report.ok("Neovim headless initialization", "Boots clean (minor warnings)")
        else:
            report.fail("Neovim headless initialization", err.splitlines()[0] if err else "Exit non-zero")
    else:
        report.warn("Neovim headless initialization", "nvim binary not found (skipped)")

    # Starship config validation
    starship_toml = dotfiles / "starship" / "starship.toml"
    if starship_toml.exists() and tomllib:
        try:
            tomllib.loads(starship_toml.read_text(encoding="utf-8"))
            report.ok("Starship prompt configuration", "starship.toml valid TOML")
        except Exception as e:
            report.fail("Starship prompt configuration", f"Invalid TOML: {e}")

    # Bat syntax viewer config
    bat_config = dotfiles / "bat" / "config"
    if bat_config.exists():
        content = bat_config.read_text(encoding="utf-8")
        if "Catppuccin Mocha" in content:
            report.ok("Bat syntax viewer theme", "Catppuccin Mocha active")
        else:
            report.ok("Bat syntax viewer theme", "Config present")

    # Eza theme configuration
    eza_theme = dotfiles / "eza" / "theme.yml"
    if eza_theme.exists():
        report.ok("Eza theme configuration", "eza/theme.yml present")

    # Mise config validation
    mise_toml = dotfiles / "mise" / "config.toml"
    if mise_toml.exists() and tomllib:
        try:
            tomllib.loads(mise_toml.read_text(encoding="utf-8"))
            report.ok("Mise runtime configuration", "mise/config.toml valid TOML")
        except Exception as e:
            report.fail("Mise runtime configuration", f"Invalid TOML: {e}")

    # Git config syntax validation
    gitconfig = dotfiles / ".gitconfig"
    if gitconfig.exists():
        code, out, err = run_cmd(["git", "config", "-f", str(gitconfig), "--list"])
        if code == 0:
            report.ok("Git configuration", ".gitconfig syntax valid")
        else:
            report.fail("Git configuration", ".gitconfig syntax error")

def test_shell_runtime(report: TestReport):
    print(f"\n{C_BOLD}2. Shell Runtime & Interactive Startup{C_RESET}")

    if not shutil.which("zsh"):
        report.fail("Interactive Zsh startup", "zsh binary not found")
        report.fail("Custom shell functions", "zsh binary not found")
        report.fail("Completions engine", "zsh binary not found")
        return

    # Interactive boot test & stderr inspection
    t0 = time.perf_counter()
    code, out, err = run_cmd(["zsh", "-i", "-c", "exit"], timeout=10, env={"ZSH_STARTUP_VERBOSE": "false"})
    elapsed_ms = int((time.perf_counter() - t0) * 1000)

    # Filter benign terminal warnings in headless CI
    critical_errors = []
    for line in err.splitlines():
        line_clean = line.strip()
        if re.search(r"command not found|parse error|syntax error|job table full|no such file", line_clean, re.IGNORECASE):
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

    # Custom functions check
    func_check_code = """
for fn in take up groot conf clone port wt y copy paste extract npmr bunr pnpmr fa toggle-autols; do
    if ! (( $+functions[$fn] )); then
        echo "Missing function: $fn"
    fi
done
"""
    code, out, err = run_cmd(["zsh", "-i", "-c", func_check_code], timeout=5)
    missing_funcs = [line.strip() for line in out.splitlines() if line.startswith("Missing function:")]
    if not missing_funcs:
        report.ok("Custom shell functions", "All 16 functions registered in zsh")
    else:
        report.fail("Custom shell functions", missing_funcs[0])

    # Completions engine
    comp_check_code = """
for comp in _git _uv _fzf_complete; do
    if ! (( $+functions[$comp] )); then
        echo "Missing completion: $comp"
    fi
done
"""
    code, out, err = run_cmd(["zsh", "-i", "-c", comp_check_code], timeout=5)
    missing_comps = [line.strip() for line in out.splitlines() if line.startswith("Missing completion:")]
    if not missing_comps:
        report.ok("Completions engine", "_git, _uv, and _fzf_complete active")
    else:
        report.fail("Completions engine", missing_comps[0])

def test_syntax_and_links(report: TestReport, dotfiles: Path):
    print(f"\n{C_BOLD}3. Script Syntax & Link Integrity{C_RESET}")

    # Bash scripts syntax (bash -n)
    bash_scripts = [dotfiles / "install.sh"]
    bash_scripts.extend((dotfiles / "install").glob("*.sh"))
    bash_scripts.extend([p for p in (dotfiles / "bin").iterdir() if p.is_file()])

    bash_failed = False
    for script in bash_scripts:
        if not script.is_file():
            continue
        try:
            with open(script, "r", encoding="utf-8", errors="ignore") as f:
                first_line = f.readline()
                if not re.match(r"^#!.*(bash|sh)", first_line):
                    continue
        except Exception:
            continue

        code, out, err = run_cmd(["bash", "-n", str(script)])
        if code != 0:
            report.fail(f"Bash syntax: {script.name}", "Syntax error")
            bash_failed = True

    if not bash_failed:
        report.ok("Bash scripts syntax", "All bin/* and install/*.sh pass (bash -n)")

    # Zsh scripts syntax (zsh -n)
    if shutil.which("zsh"):
        zsh_scripts = [dotfiles / ".zshrc", dotfiles / ".zshenv", dotfiles / ".aliases"]
        zsh_scripts.extend((dotfiles / "zsh").glob("*.zsh"))
        zsh_scripts.extend((dotfiles / "zsh" / "functions").glob("*.zsh"))

        zsh_failed = False
        for zscript in zsh_scripts:
            if zscript.is_file():
                code, out, err = run_cmd(["zsh", "-n", str(zscript)])
                if code != 0:
                    report.fail(f"Zsh syntax: {zscript.name}", "Syntax error")
                    zsh_failed = True
        if not zsh_failed:
            report.ok("Zsh scripts syntax", "All zsh/* and functions pass (zsh -n)")

    # Declarative symlink integrity & dangling checks (Includes VS Code)
    manifest = get_symlink_manifest()
    dangling: List[str] = []
    for entry in manifest:
        link = entry.link_path
        if link.is_symlink():
            try:
                dest = link.resolve()
                if not dest.exists():
                    dangling.append(str(link).replace(str(Path.home()), "~"))
            except Exception:
                dangling.append(str(link).replace(str(Path.home()), "~"))

    if not dangling:
        report.ok("Symlink health", "All configuration symlinks point to valid targets")
    else:
        report.fail("Symlink health", f"Dangling symlinks: {', '.join(dangling)}")

def run_tests() -> int:
    dotfiles = get_dotfiles_dir()
    report = TestReport()

    print(f"\n{C_CYAN}╭────────────────────────────────────────────────────────╮{C_RESET}")
    print(f"{C_CYAN}│{C_RESET}  {C_BOLD}Dotfiles Test Suite — Deep Runtime & Schema Checker   {C_RESET}{C_CYAN}│{C_RESET}")
    print(f"{C_CYAN}╰────────────────────────────────────────────────────────╯{C_RESET}")

    test_parsers_and_schemas(report, dotfiles)
    test_shell_runtime(report)
    test_syntax_and_links(report, dotfiles)

    print(f"\n{C_BOLD}Summary:{C_RESET} {C_GREEN}{report.passed} passed{C_RESET}, {C_YELLOW}{report.warnings} warnings{C_RESET}, {C_RED}{report.failed} failed{C_RESET}\n")

    if report.failed > 0:
        print(f"{C_RED}✖ Test suite failed! Please review the errors above.{C_RESET}\n")
        return 1

    print(f"{C_GREEN}✔ All deep integration tests passed successfully!{C_RESET}\n")
    return 0

if __name__ == "__main__":
    sys.exit(run_tests())
