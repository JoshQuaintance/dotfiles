"""`dot profile`: profile Zsh startup functions using `zsh/zprof`."""

import json
import os
import re
import shutil
import subprocess
from typing import Any

from cli.manifest import get_dotfiles_dir
from cli.ui import (
    C_BOLD,
    C_CYAN,
    C_DIM,
    C_GREEN,
    C_RED,
    C_RESET,
    C_YELLOW,
    ICON_FAIL,
    format_row,
    print_header,
)

ZPROF_ROW_RE = re.compile(
    r"^\s*(\d+)\)\s+(\d+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)%\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)%\s+(\S+)\s*$"
)


def parse_zprof_output(raw: str, top_n: int = 15) -> list[dict[str, Any]]:
    """Parse `zprof` summary table rows into structured dictionaries."""
    rows: list[dict[str, Any]] = []
    in_summary = False
    for line in raw.splitlines():
        if line.strip().startswith("---"):
            if in_summary and rows:
                break
            in_summary = True
            continue
        m = ZPROF_ROW_RE.match(line)
        if m:
            in_summary = True
            rows.append(
                {
                    "rank": int(m.group(1)),
                    "calls": int(m.group(2)),
                    "total_ms": float(m.group(3)),
                    "avg_ms": float(m.group(4)),
                    "total_pct": float(m.group(5)),
                    "self_ms": float(m.group(6)),
                    "self_avg_ms": float(m.group(7)),
                    "self_pct": float(m.group(8)),
                    "name": m.group(9),
                }
            )
            if len(rows) >= top_n:
                break
        elif in_summary and rows and not line.strip():
            break
    return rows


def run_profile(top_n: int = 15, json_output: bool = False) -> int:
    """Run an interactive Zsh startup with `ZSH_PROFILE=1` and render the top functions."""
    if not shutil.which("zsh"):
        if json_output:
            print(json.dumps({"error": "zsh binary not found"}))
        else:
            print(f"{C_RED}{ICON_FAIL} zsh binary not found in PATH.{C_RESET}")
        return 1

    dotfiles = get_dotfiles_dir()
    env = os.environ.copy()
    env["DOTFILES_DIR"] = str(dotfiles)
    env["ZSH_STARTUP_VERBOSE"] = "false"
    env["ZSH_PROFILE"] = "1"
    if not env.get("TERM") or env.get("TERM") == "dumb":
        env["TERM"] = "xterm-256color"

    proc = subprocess.run(
        ["zsh", "-i", "+m", "-c", "exit"],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=15,
        env=env,
        check=False,
    )
    entries = parse_zprof_output(proc.stdout + "\n" + proc.stderr, top_n=max(1, top_n))

    if json_output:
        print(json.dumps({"functions": entries}, indent=2))
        return 0

    print_header("Dotfiles Zsh Startup Function Profiler (zsh/zprof)")
    print(f"\n{C_BOLD}Top {len(entries)} Startup Functions by Total Time{C_RESET}")
    if not entries:
        print(f"  {C_DIM}No zprof entries captured.{C_RESET}\n")
        return 0

    for item in entries:
        ms = item["total_ms"]
        pct = item["total_pct"]
        calls = item["calls"]
        color = C_RED if pct >= 25.0 else (C_YELLOW if pct >= 10.0 else C_CYAN)
        detail = f"{color}{ms:6.2f}ms{C_RESET} ({pct:5.1f}%) │ {C_DIM}self: {item['self_ms']:.2f}ms │ {calls} call(s){C_RESET}"
        badge = f"{C_GREEN}#{item['rank']:<2}{C_RESET}"
        print(format_row(item["name"], detail, badge))

    print()
    return 0
