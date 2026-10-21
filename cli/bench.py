"""`dot bench`: benchmark interactive Zsh startup latency and modern CLI tool speedups."""

import os
import re
import shutil
import statistics
import subprocess
import time
from pathlib import Path

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
    print_header,
)

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
STEP_RE = re.compile(r"\u2714\s+(.+?)\s+([0-9]+)\s*ms\s*$")


def benchmark_tools(dotfiles: Path) -> None:
    """Compare modern Rust/Go CLI replacements against legacy POSIX equivalents."""
    print(f"\n{C_BOLD}4. Modern CLI Productivity Speedup Benchmark{C_RESET}")
    benchmarks = [
        ("ripgrep vs grep", ["rg", "-q", "main", str(dotfiles)], ["grep", "-rq", "main", str(dotfiles)]),
        ("fd vs find", ["fd", "-q", "main", str(dotfiles)], ["find", str(dotfiles), "-name", "*main*"]),
        ("eza vs ls", ["eza", str(dotfiles)], ["ls", str(dotfiles)]),
    ]
    for label, modern_cmd, legacy_cmd in benchmarks:
        modern_bin = modern_cmd[0]
        legacy_bin = legacy_cmd[0]
        if not shutil.which(modern_bin) or not shutil.which(legacy_bin):
            continue

        subprocess.run(modern_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        subprocess.run(legacy_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)

        runs = 5
        t_mod = []
        for _ in range(runs):
            t0 = time.perf_counter()
            subprocess.run(modern_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            t_mod.append((time.perf_counter() - t0) * 1000.0)

        t_leg = []
        for _ in range(runs):
            t0 = time.perf_counter()
            subprocess.run(legacy_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            t_leg.append((time.perf_counter() - t0) * 1000.0)

        avg_mod = statistics.mean(t_mod)
        avg_leg = statistics.mean(t_leg)
        ratio = avg_leg / avg_mod if avg_mod > 0 else 1.0

        if ratio >= 1.2:
            speedup_str = f"{C_GREEN}{ratio:.1f}x faster{C_RESET}"
        elif ratio <= 0.8:
            speedup_str = f"{C_YELLOW}{1.0 / ratio:.1f}x slower{C_RESET}"
        else:
            speedup_str = f"{C_DIM}comparable{C_RESET}"

        print(f"  {label:<20} {modern_bin}: {C_CYAN}{avg_mod:5.1f}ms{C_RESET} │ {legacy_bin}: {C_DIM}{avg_leg:5.1f}ms{C_RESET} │ {speedup_str}")


def _measure_boot_runs(
    dotfiles: Path,
    iterations: int,
) -> tuple[list[float], list[str], dict[str, list[float]]]:
    """Run interactive Zsh boot `iterations` times and collect total + per-step timings."""
    env = os.environ.copy()
    env["DOTFILES_DIR"] = str(dotfiles)
    env["ZSH_STARTUP_VERBOSE"] = "true"
    env["ZSH_BENCH_STEPS"] = "true"
    if not env.get("TERM") or env.get("TERM") == "dumb":
        env["TERM"] = "xterm-256color"

    print(f"\n{C_BOLD}1. Interactive Boot Runs ({iterations} iterations){C_RESET}")

    run_totals: list[float] = []
    step_order: list[str] = []
    step_samples: dict[str, list[float]] = {}

    for i in range(1, iterations + 1):
        t0 = time.perf_counter()
        proc = subprocess.run(
            ["zsh", "-i", "+m", "-c", "exit"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
            check=False,
        )
        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        run_totals.append(elapsed_ms)

        for raw_line in proc.stdout.splitlines():
            clean = ANSI_RE.sub("", raw_line).strip()
            m = STEP_RE.search(clean)
            if m:
                step_name = m.group(1).strip()
                step_ms = float(m.group(2))
                if step_name not in step_samples:
                    step_order.append(step_name)
                    step_samples[step_name] = []
                step_samples[step_name].append(step_ms)

        color = C_GREEN if elapsed_ms < 250 else (C_YELLOW if elapsed_ms < 350 else C_RED)
        print(f"  {C_DIM}Run #{i:<2}{C_RESET}  {color}{elapsed_ms:6.1f}ms{C_RESET}")

    return run_totals, step_order, step_samples


def _render_boot_results(
    iterations: int,
    run_totals: list[float],
    step_order: list[str],
    step_samples: dict[str, list[float]],
) -> None:
    """Render latency summary statistics and per-phase ASCII bar breakdown."""
    min_ms = min(run_totals)
    max_ms = max(run_totals)
    median_ms = statistics.median(run_totals)
    mean_ms = statistics.mean(run_totals)

    print(f"\n{C_BOLD}2. Latency Summary (Target: <350ms){C_RESET}")
    status_icon = f"{C_GREEN}\u2714{C_RESET}" if median_ms < 350 else f"{C_YELLOW}\u26a0{C_RESET}"
    print(
        f"  {status_icon} {C_BOLD}Median:{C_RESET} {C_GREEN}{median_ms:.1f}ms{C_RESET}   "
        f"{C_DIM}\u2502{C_RESET}  {C_BOLD}Min:{C_RESET} {min_ms:.1f}ms   "
        f"{C_DIM}\u2502{C_RESET}  {C_BOLD}Mean:{C_RESET} {mean_ms:.1f}ms   "
        f"{C_DIM}\u2502{C_RESET}  {C_BOLD}Max:{C_RESET} {max_ms:.1f}ms"
    )

    if not step_order:
        return

    print(f"\n{C_BOLD}3. Per-Phase Breakdown (Average across {iterations} runs){C_RESET}")
    step_avgs = {name: statistics.mean(step_samples[name]) for name in step_order}
    total_step_ms = sum(step_avgs.values()) or 1.0
    bar_width = 20

    for name in step_order:
        avg_ms = step_avgs[name]
        pct = (avg_ms / total_step_ms) * 100.0
        filled = max(0, min(bar_width, round((avg_ms / total_step_ms) * bar_width)))
        bar = f"{C_MAUVE}" + ("\u2588" * filled) + f"{C_DIM}" + ("\u2591" * (bar_width - filled)) + f"{C_RESET}"
        print(f"  {name:<42} {bar} {C_BLUE}{avg_ms:5.1f}ms{C_RESET} {C_DIM}({pct:4.1f}%){C_RESET}")


def run_bench(
    iterations: int = 5,
    test_prompt: bool = False,
    test_tools: bool = False,
    test_all: bool = False,
) -> int:
    """Run the interactive Zsh startup benchmark and optional tool/prompt suites."""
    dotfiles = get_dotfiles_dir()

    if not shutil.which("zsh"):
        print(f"{C_RED}{ICON_FAIL} zsh binary not found in PATH.{C_RESET}")
        return 1

    iterations = max(1, min(iterations, 25))
    print_header("Dotfiles Unified Benchmark Suite — Profiler & Diagnostics")

    run_totals, step_order, step_samples = _measure_boot_runs(dotfiles, iterations)
    _render_boot_results(iterations, run_totals, step_order, step_samples)

    if test_tools or test_all:
        benchmark_tools(dotfiles)

    if test_prompt or test_all:
        from cli.prompt import print_prompt_summary
        print_prompt_summary(interactive=False)

    print()
    return 0
