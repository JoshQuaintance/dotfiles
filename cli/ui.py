import os
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple

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


def print_header(title: str) -> None:
    """Render a standard 58-column Catppuccin Mocha rounded header box."""
    print(f"\n{C_CYAN}{BOX_TOP}{C_RESET}")
    print(f"{C_CYAN}{BOX_SIDE}{C_RESET}  {C_BOLD}{title:<54}{C_RESET}{C_CYAN}{BOX_SIDE}{C_RESET}")
    print(f"{C_CYAN}{BOX_BOT}{C_RESET}")


def run_cmd(
    cmd: List[str],
    cwd: Optional[Path] = None,
    timeout: int = 10,
    env: Optional[Dict[str, str]] = None,
) -> Tuple[int, str, str]:
    """Execute a subprocess safely and return (returncode, stdout, stderr)."""
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    try:
        res = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=merged_env,
        )
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", f"Timed out after {timeout}s"
    except Exception as e:
        return 1, "", str(e)
