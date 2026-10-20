import os
import shutil
import statistics
import subprocess
from pathlib import Path
from typing import Optional

from cli.manifest import get_dotfiles_dir
from cli.ui import (
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
)

PROMPT_ENGINES = {
    "native": {
        "name": "Fast Native",
        "description": "0-fork pure Zsh vcs_info (instant in PRoot / Termux / low-spec)",
        "badge": "⚡ Instant",
        "icon": "⚡",
    },
    "spaceship": {
        "name": "Spaceship",
        "description": "Feature-rich native Zsh async prompt with section streaming",
        "badge": "🎨 Feature-rich",
        "icon": "🐢",
    },
}


def get_prompt_config_path() -> Path:
    xdg = os.environ.get("XDG_CONFIG_HOME")
    base = Path(xdg) if xdg else Path.home() / ".config"
    return base / "dotfiles" / "prompt"


def is_mobile_or_proot() -> bool:
    """Detect mobile terminal, PRoot, Android, or mobile SSH session."""
    if os.environ.get("SSH_MOBILE") or os.environ.get("_IS_MOBILE", "").strip().lower() in ("true", "1"):
        return True

    lc_term = os.environ.get("LC_TERMINAL", "").strip().lower()
    term_prog = os.environ.get("TERM_PROGRAM", "").strip().lower()
    if lc_term in ("blink", "termius") or term_prog in ("blink", "termius"):
        return True

    if os.environ.get("TERMUX_VERSION") or Path("/data/data/com.termux").is_dir():
        return True
    if os.environ.get("PROOT_TMP_DIR"):
        return True
    try:
        proc_ver = Path("/proc/version")
        if proc_ver.is_file():
            content = proc_ver.read_text(encoding="utf-8", errors="ignore").lower()
            if any(k in content for k in ("android", "samsung", "qcom", "proot")):
                return True
    except OSError:
        pass
    try:
        uname_r = os.uname().release.lower()
        if "android" in uname_r:
            return True
    except AttributeError:
        pass
    return False


def get_active_prompt() -> tuple[str, str]:
    # 1. Environment variable override (takes absolute precedence)
    env_val = os.environ.get("DOTFILES_PROMPT", "").strip().lower()
    if env_val in PROMPT_ENGINES:
        return env_val, "environment ($DOTFILES_PROMPT)"

    # 2. Dynamic mobile auto-detection (runs before desktop config)
    if is_mobile_or_proot():
        return "native", "auto-detected (mobile/PRoot environment)"

    # 3. Explicit user preference file for desktop / standard sessions
    config_file = get_prompt_config_path()
    if config_file.is_file():
        try:
            val = config_file.read_text(encoding="utf-8").strip().lower()
            if val in PROMPT_ENGINES:
                return val, "configured (~/.config/dotfiles/prompt)"
        except OSError:
            pass

    # Default desktop search: spaceship -> native
    home = Path.home()
    spaceship_paths = [
        Path("/opt/homebrew/opt/spaceship/spaceship.zsh"),
        Path("/home/linuxbrew/.linuxbrew/opt/spaceship/spaceship.zsh"),
        Path("/usr/local/opt/spaceship/spaceship.zsh"),
        home / ".spaceship-prompt" / "spaceship.zsh",
    ]
    if any(p.is_file() for p in spaceship_paths):
        return "spaceship", "auto-detected (Spaceship installed)"
    return "native", "auto-detected (Native fallback)"


def set_active_prompt(engine: str) -> bool:
    engine = engine.strip().lower()
    if engine not in PROMPT_ENGINES:
        print(f"{C_RED}{ICON_FAIL} Unknown prompt engine: {engine}{C_RESET}")
        print(f"Available engines: {', '.join(PROMPT_ENGINES.keys())}")
        return False

    cfg_path = get_prompt_config_path()
    try:
        cfg_path.parent.mkdir(parents=True, exist_ok=True)
        cfg_path.write_text(f"{engine}\n", encoding="utf-8")
        print(f"{C_GREEN}{ICON_OK} Active prompt set to {C_BOLD}{PROMPT_ENGINES[engine]['name']}{C_RESET} ({engine}).")
        print(f"{C_DIM}Persisted to {cfg_path}{C_RESET}")
        return True
    except OSError as e:
        print(f"{C_RED}{ICON_FAIL} Failed to write config: {e}{C_RESET}")
        return False


def is_engine_installed(engine: str) -> bool:
    if engine == "native":
        return True
    if engine == "spaceship":
        home = Path.home()
        candidates = [
            Path("/opt/homebrew/opt/spaceship/spaceship.zsh"),
            Path("/home/linuxbrew/.linuxbrew/opt/spaceship/spaceship.zsh"),
            Path("/usr/local/opt/spaceship/spaceship.zsh"),
            home / ".spaceship-prompt" / "spaceship.zsh",
        ]
        return any(p.is_file() for p in candidates)
    return False


def benchmark_engine(engine: str, dotfiles_dir: Path, iterations: int = 3) -> Optional[tuple[float, float, float]]:
    if not is_engine_installed(engine):
        return None

    zsh_bin = shutil.which("zsh")
    if not zsh_bin:
        return None

    script = f"""
    zmodload zsh/datetime
    export DOTFILES_DIR="{dotfiles_dir}"
    export DOTFILES_PROMPT="{engine}"
    export TERM="xterm-256color"
    source "{dotfiles_dir}/zsh/prompt.zsh" >/dev/null 2>&1
    for i in $(seq 1 {iterations}); do
        t0=$EPOCHREALTIME
        for hook in $precmd_functions; do "$hook" >/dev/null 2>&1; done
        out="${{(e)PROMPT}}"
        t1=$EPOCHREALTIME
        print $(( (t1 - t0) * 1000 ))
    done
    """

    try:
        res = subprocess.run(
            [zsh_bin, "-c", script],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        if res.returncode != 0:
            return None
        samples = [float(line) for line in res.stdout.strip().splitlines() if line.strip()]
        if not samples:
            return None
        return min(samples), statistics.median(samples), max(samples)
    except (subprocess.SubprocessError, OSError, ValueError):
        return None


def run_prompt_benchmark(iterations: int = 3) -> dict[str, Optional[tuple[float, float, float]]]:
    dotfiles = get_dotfiles_dir()
    results: dict[str, Optional[tuple[float, float, float]]] = {}
    for engine in PROMPT_ENGINES:
        results[engine] = benchmark_engine(engine, dotfiles, iterations=iterations)
    return results


def _format_engine_timing(stats: Optional[tuple[float, float, float]], mobile: bool) -> str:
    """Format benchmark latency and speed badge for a prompt engine."""
    if stats is None:
        return f"{C_DIM}Not installed{C_RESET}"
    _min_ms, med_ms, _max_ms = stats
    if med_ms < 10:
        speed_color = C_GREEN
        speed_tag = "Instant"
    elif med_ms < 60:
        speed_color = C_CYAN
        speed_tag = "Fast"
    else:
        speed_color = C_YELLOW if med_ms < 200 else C_RED
        speed_tag = "High overhead" if mobile else "Feature-heavy"
    return f"{speed_color}{med_ms:5.1f}ms{C_RESET} [{speed_color}{speed_tag}{C_RESET}]"


def _resolve_selected_engine(choice: str, engine_keys: list[str]) -> Optional[str]:
    """Map user input ('1', '2', or engine key) to a valid prompt engine name."""
    if choice in ("1", "2"):
        return engine_keys[int(choice) - 1]
    if choice in PROMPT_ENGINES:
        return choice
    return None


def _prompt_interactive_selection(engine_keys: list[str], mobile: bool) -> None:
    """Prompt the user to interactively select and persist a shell prompt engine."""
    default_choice = "2" if (not mobile and is_engine_installed("spaceship")) else "1"
    print()
    try:
        choice = input(f"Select your active prompt [1-2] or press Enter for default [{default_choice}]: ").strip()
        selected_key = _resolve_selected_engine(choice or default_choice, engine_keys)
        if not selected_key:
            print(f"{C_DIM}Selection unchanged.{C_RESET}\n")
            return

        if not is_engine_installed(selected_key):
            print(f"{C_YELLOW}{ICON_WARN} {PROMPT_ENGINES[selected_key]['name']} is not yet installed.{C_RESET}")
            if selected_key == "spaceship":
                print("Run 'brew install spaceship' or clone into ~/.spaceship-prompt.")
            confirm = input("Set as default anyway? [y/N]: ").strip().lower()
            if confirm not in ("y", "yes"):
                return
        set_active_prompt(selected_key)
        print(f"\n{C_GREEN}{ICON_OK} Done! Open a new shell or run 'source ~/.zshrc' to apply.{C_RESET}\n")
    except (KeyboardInterrupt, EOFError):
        print(f"\n{C_DIM}Selection cancelled.{C_RESET}\n")


def print_prompt_summary(interactive: bool = False) -> None:
    print_header("Shell Prompt Manager & Benchmark")

    active_engine, source = get_active_prompt()
    mobile = is_mobile_or_proot()

    print(f"\n{C_BOLD}Current Configuration:{C_RESET}")
    print(f"  {C_MAUVE}{ICON_OK}{C_RESET} Active Prompt: {C_BOLD}{PROMPT_ENGINES[active_engine]['name']}{C_RESET} ({active_engine})")
    print(f"  {C_DIM}Source: {source}{C_RESET}")

    if mobile:
        print(f"\n  {C_YELLOW}{ICON_WARN} Environment detected as PRoot / Termux / Android.{C_RESET}")
        print(f"  {C_DIM}Subprocess forking incurs heavy ptrace overhead. Fast Native is strongly recommended.{C_RESET}")

    print(f"\n{C_BOLD}Measuring prompt render latency across available engines...{C_RESET}\n")

    results = run_prompt_benchmark(iterations=3)
    engine_keys = list(PROMPT_ENGINES.keys())
    for idx, key in enumerate(engine_keys, 1):
        meta = PROMPT_ENGINES[key]
        prefix = f"  [{idx}] {meta['icon']} {meta['name']:<12}"
        timing = _format_engine_timing(results.get(key), mobile)
        active_marker = f" {C_GREEN}\u2714 active{C_RESET}" if key == active_engine else ""
        print(f"{prefix} {timing:<28} {C_DIM}{meta['description']}{C_RESET}{active_marker}")

    if not interactive:
        print(f"\n{C_DIM}To switch active prompt: 'dot prompt set <native|spaceship>'{C_RESET}\n")
        return

    _prompt_interactive_selection(engine_keys, mobile)


def run_prompt_command(subcommand: Optional[str] = None, value: Optional[str] = None) -> int:
    if subcommand == "set":
        if not value:
            print(f"{C_RED}{ICON_FAIL} Missing engine argument.{C_RESET}")
            print(f"Usage: dot prompt set <{'|'.join(PROMPT_ENGINES.keys())}>")
            return 1
        return 0 if set_active_prompt(value) else 1
    elif subcommand == "benchmark":
        print_prompt_summary(interactive=False)
        return 0
    else:
        # Default: show benchmark and offer interactive selection if in TTY
        import sys
        is_tty = sys.stdin.isatty() and sys.stdout.isatty()
        print_prompt_summary(interactive=is_tty)
        return 0
