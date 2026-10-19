import os
import shutil
import subprocess
from pathlib import Path
from typing import Any, Optional

# Catppuccin Mocha ANSI color constants
C_GREEN = "\033[38;2;166;227;161m"
C_YELLOW = "\033[38;2;249;226;175m"
C_RED = "\033[38;2;243;139;168m"
C_BLUE = "\033[1;34m"
C_MAUVE = "\033[38;2;203;166;247m"
C_CYAN = "\033[38;2;137;220;235m"
C_DIM = "\033[38;2;108;112;134m"
C_BOLD = "\033[1m"
C_RESET = "\033[0m"

ICON_OK = "\u2714"
ICON_WARN = "\u26a0"
ICON_FAIL = "\u2716"
ICON_BULLET = "\u2022"

BOX_TOP = "\u256d" + ("\u2500" * 56) + "\u256e"
BOX_BOT = "\u2570" + ("\u2500" * 56) + "\u256f"
BOX_SIDE = "\u2502"


def get_terminal_columns(default: int = 80) -> int:
    """Return active terminal width in columns with safe fallback to default."""
    try:
        env_cols = os.environ.get("COLUMNS")
        if env_cols and env_cols.isdigit() and int(env_cols) > 0:
            return int(env_cols)
        return shutil.get_terminal_size((default, 24)).columns
    except (OSError, ValueError):
        return default


def box(title: str, max_width: Optional[int] = None) -> list[str]:
    """Render rounded box lines dynamically adapted to the active terminal width."""
    cols = max_width or get_terminal_columns()
    if cols < 60:
        box_w = max(24, min(cols - 2, 58))
    else:
        needed = len(title) + 6
        box_w = max(58, min(needed, min(cols - 2, 80)))

    inner = max(20, box_w - 2)
    top = "╭" + ("─" * inner) + "╮"
    bot = "╰" + ("─" * inner) + "╯"

    max_text_w = inner - 4
    if len(title) > max_text_w:
        t_len = max(1, max_text_w - 3)
        disp_title = f"{title[:t_len]}..."
    else:
        disp_title = title

    pad_right = max_text_w - len(disp_title)
    content = f"{BOX_SIDE}  {disp_title}{' ' * pad_right}  {BOX_SIDE}"
    return [top, content, bot]


def print_header(title: str) -> None:
    """Render a responsive Catppuccin Mocha rounded header box."""
    top, content, bot = box(title)
    inner_text = content[3:-3]
    print(f"\n{C_CYAN}{top}{C_RESET}")
    print(f"{C_CYAN}{BOX_SIDE}{C_RESET}  {C_BOLD}{inner_text}{C_RESET}  {C_CYAN}{BOX_SIDE}{C_RESET}")
    print(f"{C_CYAN}{bot}{C_RESET}")


def format_row(label: str, detail: str = "", status_icon: str = "", cols: Optional[int] = None) -> str:
    """Format a responsive key-value / status row matching Zsh startup banner conventions."""
    term_cols = cols or get_terminal_columns()
    prefix = f"  {status_icon} " if status_icon else "  "
    if term_cols < 60:
        lbl_w = 24
        lbl = f"{label[:lbl_w]:<{lbl_w}}"
        max_det = max(0, term_cols - lbl_w - len(prefix) - 1)
        if len(detail) > max_det:
            det = f"{detail[:max_det - 3]}..." if max_det >= 3 else detail[:max_det]
        else:
            det = detail
        return f"{prefix}{lbl} {C_DIM}{det}{C_RESET}"
    else:
        lbl_w = 44
        lbl = f"{label:<{lbl_w}}"
        return f"{prefix}{lbl} {C_DIM}{detail}{C_RESET}"


def run_cmd(
    cmd: list[str],
    cwd: Optional[Path] = None,
    timeout: int = 10,
    env: Optional[dict[str, str]] = None,
    stdin: Optional[Any] = subprocess.DEVNULL,
) -> tuple[int, str, str]:
    """Execute a subprocess safely and return (returncode, stdout, stderr)."""
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    try:
        res = subprocess.run(
            cmd,
            cwd=cwd,
            stdin=stdin,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=merged_env,
            check=False,
        )
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", f"Timed out after {timeout}s"
    except (OSError, subprocess.SubprocessError) as e:
        return 1, "", str(e)
