"""`dot bench`: benchmark interactive Zsh startup latency and modern CLI tool speedups."""

import contextlib
import io
import json
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
SPARK_CHARS = "▁▂▃▄▅▆▇█"


def render_sparkline(values: list[float]) -> str:
    """Render a numeric series as an 8-level Unicode sparkline (▁▂▃▄▅▆▇█)."""
    if not values:
        return ""
    lo, hi = min(values), max(values)
    if hi <= lo:
        return SPARK_CHARS[3] * len(values)
    out: list[str] = []
    for val in values:
        idx = round((val - lo) / (hi - lo) * (len(SPARK_CHARS) - 1))
        out.append(SPARK_CHARS[max(0, min(idx, len(SPARK_CHARS) - 1))])
    return "".join(out)


def append_bench_history(history_path: Path, entry: dict, max_entries: int = 50) -> None:
    """Append a benchmark summary entry to `bench_history.jsonl`, keeping at most `max_entries`."""
    history_path.parent.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []
    if history_path.exists():
        lines = [ln for ln in history_path.read_text(encoding="utf-8").splitlines() if ln.strip()]
    lines.append(json.dumps(entry))
    lines = lines[-max_entries:]
    history_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def load_bench_history(history_path: Path) -> list[dict]:
    """Load saved benchmark entries from `bench_history.jsonl`."""
    if not history_path.exists():
        return []
    entries: list[dict] = []
    for ln in history_path.read_text(encoding="utf-8").splitlines():
        if not ln.strip():
            continue
        with contextlib.suppress(ValueError):
            entries.append(json.loads(ln))
    return entries


def evaluate_bench_trend(history: list[dict]) -> tuple[str, bool, float]:
    """Compute sparkline, >15% regression flag, and delta percentage across saved history."""
    medians = [float(h["median_ms"]) for h in history if "median_ms" in h]
    spark = render_sparkline(medians)
    if len(medians) < 2:
        return spark, False, 0.0
    latest = medians[-1]
    prev_window = medians[max(0, len(medians) - 6) : -1]
    ref_med = statistics.median(prev_window)
    diff_pct = round(((latest - ref_med) / ref_med * 100.0), 1) if ref_med > 0 else 0.0
    return spark, diff_pct > 15.0, diff_pct


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


def _handle_json_output(
    dotfiles: Path,
    iterations: int,
    cache_dir: Path,
    baseline_path: Path,
    save_baseline: bool,
    compare_baseline: bool,
) -> int:
    with contextlib.redirect_stdout(io.StringIO()):
        run_totals, step_order, step_samples = _measure_boot_runs(dotfiles, iterations)
    median_ms = round(statistics.median(run_totals), 2)
    payload: dict = {
        "iterations": iterations,
        "median_ms": median_ms,
        "min_ms": round(min(run_totals), 2),
        "mean_ms": round(statistics.mean(run_totals), 2),
        "max_ms": round(max(run_totals), 2),
        "runs_ms": [round(r, 2) for r in run_totals],
        "phases_ms": {name: round(statistics.mean(step_samples[name]), 2) for name in step_order},
    }

    if save_baseline:
        cache_dir.mkdir(parents=True, exist_ok=True)
        baseline_path.write_text(json.dumps(payload, indent=2))
        append_bench_history(
            cache_dir / "bench_history.jsonl",
            {
                "ts": time.time(),
                "median_ms": median_ms,
                "mean_ms": payload["mean_ms"],
                "min_ms": payload["min_ms"],
                "max_ms": payload["max_ms"],
            },
        )

    regression = False
    if compare_baseline and baseline_path.exists():
        try:
            base_data = json.loads(baseline_path.read_text())
            base_median = float(base_data.get("median_ms", 0.0))
            diff_ms = round(median_ms - base_median, 2)
            diff_pct = round(((median_ms - base_median) / base_median * 100.0), 1) if base_median > 0 else 0.0
            regression = diff_pct > 15.0
            payload["comparison"] = {
                "baseline_ms": base_median,
                "diff_ms": diff_ms,
                "diff_pct": diff_pct,
                "regression": regression,
            }
        except (ValueError, KeyError):
            pass

    print(json.dumps(payload, indent=2))
    return 1 if regression else 0


def _handle_cli_baseline(
    cache_dir: Path,
    baseline_path: Path,
    run_totals: list[float],
    step_info: tuple[list[str], dict[str, list[float]]],
    iterations: int,
    save_baseline: bool,
    compare_baseline: bool,
) -> bool:
    """Save baseline or compare current run against saved baseline. Returns True if regression."""
    step_order, step_samples = step_info
    median_ms = statistics.median(run_totals)
    if save_baseline:
        cache_dir.mkdir(parents=True, exist_ok=True)
        baseline_payload = {
            "timestamp": time.time(),
            "iterations": iterations,
            "median_ms": round(median_ms, 2),
            "mean_ms": round(statistics.mean(run_totals), 2),
            "min_ms": round(min(run_totals), 2),
            "max_ms": round(max(run_totals), 2),
            "phases_ms": {name: round(statistics.mean(step_samples[name]), 2) for name in step_order},
        }
        baseline_path.write_text(json.dumps(baseline_payload, indent=2))
        append_bench_history(
            cache_dir / "bench_history.jsonl",
            {
                "ts": baseline_payload["timestamp"],
                "median_ms": baseline_payload["median_ms"],
                "mean_ms": baseline_payload["mean_ms"],
                "min_ms": baseline_payload["min_ms"],
                "max_ms": baseline_payload["max_ms"],
            },
        )
        print(f"\n{C_GREEN}✔ Saved benchmark baseline ({median_ms:.1f}ms) to {baseline_path}{C_RESET}")

    if not compare_baseline:
        return False

    print(f"\n{C_BOLD}5. Baseline Comparison{C_RESET}")
    if not baseline_path.exists():
        cache_dir.mkdir(parents=True, exist_ok=True)
        init_payload = {
            "timestamp": time.time(),
            "iterations": iterations,
            "median_ms": round(median_ms, 2),
            "mean_ms": round(statistics.mean(run_totals), 2),
            "phases_ms": {name: round(statistics.mean(step_samples[name]), 2) for name in step_order},
        }
        baseline_path.write_text(json.dumps(init_payload, indent=2))
        print(f"  {C_YELLOW}⚠ No baseline found. Saved current run as baseline at {baseline_path}.{C_RESET}")
        return False

    try:
        base_data = json.loads(baseline_path.read_text())
        base_median = float(base_data.get("median_ms", 0.0))
        diff_ms = round(median_ms - base_median, 2)
        diff_pct = round(((median_ms - base_median) / base_median * 100.0), 1) if base_median > 0 else 0.0
        regression = diff_pct > 15.0

        if regression:
            status_lbl = f"{C_RED}✖ REGRESSION (+{diff_pct:.1f}% > 15% threshold){C_RESET}"
        elif diff_pct < -5.0:
            status_lbl = f"{C_GREEN}✔ FASTER ({diff_pct:+.1f}%){C_RESET}"
        else:
            status_lbl = f"{C_GREEN}✔ COMPARABLE ({diff_pct:+.1f}%){C_RESET}"

        print(f"  Baseline: {C_CYAN}{base_median:.1f}ms{C_RESET} │ Current: {C_CYAN}{median_ms:.1f}ms{C_RESET} │ Diff: {diff_ms:+.1f}ms │ {status_lbl}")
        return regression
    except (ValueError, KeyError) as exc:
        print(f"  {C_RED}✖ Could not read baseline file: {exc}{C_RESET}")
        return False


def _render_trend_section(cache_dir: Path) -> bool:
    """Render saved benchmark history as a sparkline and flag regressions >15%."""
    history_path = cache_dir / "bench_history.jsonl"
    history = load_bench_history(history_path)
    print(f"\n{C_BOLD}6. Historical Latency Trend{C_RESET}")
    if not history:
        print(f"  {C_DIM}No saved history yet. Run 'dot bench --save' to record entries.{C_RESET}")
        return False

    medians = [float(h["median_ms"]) for h in history if "median_ms" in h]
    spark, reg, diff_pct = evaluate_bench_trend(history)
    recent_vals = ", ".join(f"{m:.0f}ms" for m in medians[-8:])
    status = (
        f"{C_RED}✖ REGRESSION ({diff_pct:+.1f}% > 15%){C_RESET}"
        if reg
        else f"{C_GREEN}✔ STABLE ({diff_pct:+.1f}%){C_RESET}"
    )
    print(f"  {C_MAUVE}{spark}{C_RESET}  ({len(medians)} runs; recent: {C_CYAN}{recent_vals}{C_RESET}) │ {status}")
    return reg


def run_bench(
    iterations: int = 5,
    test_prompt: bool = False,
    test_tools: bool = False,
    test_all: bool = False,
    json_output: bool = False,
    **kwargs: bool,
) -> int:
    """Run the interactive Zsh startup benchmark and optional tool/prompt suites."""
    save_baseline = bool(kwargs.get("save_baseline", False))
    compare_baseline = bool(kwargs.get("compare_baseline", False))
    show_trend = bool(kwargs.get("show_trend", False))
    dotfiles = get_dotfiles_dir()

    if not shutil.which("zsh"):
        if json_output:
            print(json.dumps({"error": "zsh binary not found in PATH"}))
        else:
            print(f"{C_RED}{ICON_FAIL} zsh binary not found in PATH.{C_RESET}")
        return 1

    iterations = max(1, min(iterations, 25))
    cache_dir = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")) / "dotfiles"
    baseline_path = cache_dir / "bench_baseline.json"

    if json_output:
        return _handle_json_output(
            dotfiles, iterations, cache_dir, baseline_path, save_baseline, compare_baseline
        )

    print_header("Dotfiles Unified Benchmark Suite — Profiler & Diagnostics")

    run_totals, step_order, step_samples = _measure_boot_runs(dotfiles, iterations)
    _render_boot_results(iterations, run_totals, step_order, step_samples)

    if test_tools or test_all:
        benchmark_tools(dotfiles)

    if test_prompt or test_all:
        from cli.prompt import print_prompt_summary
        print_prompt_summary(interactive=False)

    regression = _handle_cli_baseline(
        cache_dir, baseline_path, run_totals, (step_order, step_samples), iterations, save_baseline, compare_baseline
    )

    if show_trend or test_all:
        trend_reg = _render_trend_section(cache_dir)
        regression = regression or trend_reg

    print()
    return 1 if regression else 0
