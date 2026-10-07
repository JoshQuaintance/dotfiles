import os
import re
import shutil
import statistics
import subprocess
import time
from typing import Dict, List

from cli.manifest import get_dotfiles_dir

C_GREEN = "\033[38;2;166;227;161m"
C_YELLOW = "\033[38;2;249;226;175m"
C_RED = "\033[38;2;243;139;168m"
C_CYAN = "\033[38;2;137;220;235m"
C_MAUVE = "\033[38;2;203;166;247m"
C_BLUE = "\033[38;2;137;180;250m"
C_DIM = "\033[38;2;108;112;134m"
C_BOLD = "\033[1m"
C_RESET = "\033[0m"

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
STEP_RE = re.compile(r"\u2714\s+(.+?)\s+([0-9]+)\s*ms\s*$")


def run_bench(iterations: int = 5) -> int:
    dotfiles = get_dotfiles_dir()

    if not shutil.which("zsh"):
        print(f"{C_RED}\u2716 zsh binary not found in PATH.{C_RESET}")
        return 1

    iterations = max(1, min(iterations, 25))

    print(f"\n{C_CYAN}\u256d\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256e{C_RESET}")
    print(f"{C_CYAN}\u2502{C_RESET}  {C_BOLD}Dotfiles Startup Benchmark \u2014 Zsh Interactive Profiler {C_RESET}{C_CYAN}\u2502{C_RESET}")
    print(f"{C_CYAN}\u2570\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256f{C_RESET}")

    env = os.environ.copy()
    env["DOTFILES_DIR"] = str(dotfiles)
    env["ZSH_STARTUP_VERBOSE"] = "true"
    env["ZSH_BENCH_STEPS"] = "true"

    print(f"\n{C_BOLD}1. Interactive Boot Runs ({iterations} iterations){C_RESET}")

    run_totals: List[float] = []
    step_order: List[str] = []
    step_samples: Dict[str, List[float]] = {}

    for i in range(1, iterations + 1):
        t0 = time.perf_counter()
        proc = subprocess.run(
            ["zsh", "-i", "-c", "exit"],
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
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

    if step_order:
        print(f"\n{C_BOLD}3. Per-Phase Breakdown (Average across {iterations} runs){C_RESET}")
        step_avgs = {name: statistics.mean(step_samples[name]) for name in step_order}
        total_step_ms = sum(step_avgs.values()) or 1.0
        bar_width = 20

        for name in step_order:
            avg_ms = step_avgs[name]
            pct = (avg_ms / total_step_ms) * 100.0
            filled = int(round((avg_ms / total_step_ms) * bar_width))
            filled = max(0, min(bar_width, filled))
            bar = (f"{C_MAUVE}" + ("\u2588" * filled) + f"{C_DIM}" + ("\u2591" * (bar_width - filled)) + f"{C_RESET}")
            print(f"  {name:<42} {bar} {C_BLUE}{avg_ms:5.1f}ms{C_RESET} {C_DIM}({pct:4.1f}%){C_RESET}")

    print()
    return 0
