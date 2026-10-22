"""`dot status`: render a concise workstation, repository, symlink, and runtime dashboard."""

import json
import platform
import shutil
from pathlib import Path

from cli.manifest import get_dotfiles_dir, get_symlink_manifest
from cli.prompt import get_active_prompt
from cli.ui import (
    C_BOLD,
    C_CYAN,
    C_DIM,
    C_GREEN,
    C_MAUVE,
    C_RESET,
    C_YELLOW,
    ICON_BULLET,
    ICON_OK,
    ICON_WARN,
    print_header,
    run_cmd,
)

SUBCOMMANDS_TABLE: tuple[tuple[str, str, str], ...] = (
    ("dot status",          ".status / .s",     "Quick workstation & dotfiles overview"),
    ("dot doctor [--fix]",  ".doctor",          "Full system & symlink health check"),
    ("dot env [-a]",        ".env",             "Audit $PATH precedence & shadowed binaries"),
    ("dot test",            ".test",            "Run deep runtime & schema integration tests"),
    ("dot bench [-n N]",    ".bench",           "Profile Zsh startup latency by phase"),
    ("dot prompt",          ".prompt",          "Benchmark & select prompt (native, spaceship)"),
    ("dot clean [-n] [-a]", ".clean",           "Prune stale caches, dumps & temp files"),
    ("dot prune [-n] [-o]", ".prune",           "Remove links & packages deleted upstream"),
    ("dot update [-c] [-a]", ".update / .check", "Pull dotfiles & upgrade Brew / Mise"),
    ("dot sync [-m MSG]",   ".sync",            "Commit, rebase & push dotfiles changes"),
    ("dot backup [-l] [-n]", ".backup",         "Snapshot untracked local overrides & state"),
    ("dot restore [ARC]",   ".restore",         "Restore local overrides from snapshot"),
    ("dot link --fix",      "",                 "Reconcile all declarative symlinks"),
)


def _short_version(bin_name: str, args: list[str]) -> str:
    """Return the first line of a tool's version output, or 'not installed'."""
    if not shutil.which(bin_name):
        return "not installed"
    code, out, _ = run_cmd([bin_name, *args], timeout=3)
    if code != 0 or not out:
        return "installed"
    return out.splitlines()[0].strip()


def _count_symlinks(dotfiles: Path) -> tuple[int, int]:
    """Return (linked_ok, total_links) across the symlink manifest."""
    linked_ok = 0
    total_links = 0

    for entry in get_symlink_manifest():
        link = entry.link_path
        if not entry.required and not link.parent.exists():
            continue
        total_links += 1
        target_expected = (dotfiles / entry.rel_target).resolve()
        if link.is_symlink():
            try:
                if link.resolve() == target_expected and target_expected.exists():
                    linked_ok += 1
            except (OSError, RuntimeError):
                pass
    return linked_ok, total_links


def _summarize_symlinks(dotfiles: Path) -> str:
    """Return a formatted status string summarizing healthy vs. total symlinks."""
    linked_ok, total_links = _count_symlinks(dotfiles)
    if linked_ok == total_links:
        return f"{C_GREEN}{ICON_OK} {linked_ok}/{total_links} linked{C_RESET}"
    return (
        f"{C_YELLOW}{ICON_WARN} {linked_ok}/{total_links} linked{C_RESET} "
        f"{C_DIM}(run 'dot link --fix'){C_RESET}"
    )


def run_status(json_output: bool = False) -> int:
    """Render the `dot status` workstation overview (or JSON when `json_output` is True)."""
    dotfiles = get_dotfiles_dir()

    # 1. Repository & Branch State
    _, branch, _ = run_cmd(["git", "-C", str(dotfiles), "branch", "--show-current"])
    branch = branch or "detached"
    _, commit, _ = run_cmd(["git", "-C", str(dotfiles), "rev-parse", "--short", "HEAD"])
    _, porcelain, _ = run_cmd(["git", "-C", str(dotfiles), "status", "--porcelain"])
    dirty_count = len(porcelain.splitlines()) if porcelain else 0

    code, tracking_counts, _ = run_cmd(["git", "-C", str(dotfiles), "rev-list", "--left-right", "--count", "HEAD...@{u}"])
    ahead = 0
    behind = 0
    if code == 0 and tracking_counts:
        parts = tracking_counts.split()
        if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
            ahead = int(parts[0])
            behind = int(parts[1])

    sync_tags = []
    if ahead > 0:
        sync_tags.append(f"↑{ahead}")
    if behind > 0:
        sync_tags.append(f"↓{behind}")
    sync_str = f" {C_YELLOW}{''.join(sync_tags)}{C_RESET}" if sync_tags else ""

    # 2. Symlink & Runtime Versions
    linked_ok, total_links = _count_symlinks(dotfiles)
    zsh_ver = _short_version("zsh", ["--version"]).replace("zsh ", "").split(" ")[0]
    nvim_ver = _short_version("nvim", ["--version"]).replace("NVIM ", "")
    node_ver = _short_version("node", ["--version"])
    uv_ver = _short_version("uv", ["--version"]).replace("uv ", "").split(" ")[0]
    os_label = f"{platform.system()} ({platform.machine()})"
    active_prompt, _ = get_active_prompt()

    if json_output:
        payload = {
            "os": os_label,
            "branch": branch,
            "commit": commit,
            "dirty_count": dirty_count,
            "upstream": {"ahead": ahead, "behind": behind},
            "prompt": active_prompt,
            "symlinks": {"healthy": linked_ok, "total": total_links},
            "runtimes": {"zsh": zsh_ver, "nvim": nvim_ver, "node": node_ver, "uv": uv_ver},
        }
        print(json.dumps(payload, indent=2))
        return 0

    print_header("Dotfiles Workstation Status \u2014 Quick Overview")
    tree_str = (
        f"{C_GREEN}{ICON_OK} clean{C_RESET}"
        if dirty_count == 0
        else f"{C_YELLOW}{ICON_WARN} {dirty_count} modified{C_RESET}"
    )
    link_str = _summarize_symlinks(dotfiles)
    sep = f"{C_DIM}{ICON_BULLET}{C_RESET}"

    print(f"\n{C_BOLD}Environment{C_RESET}")
    print(f"  {C_MAUVE}OS & Shell:{C_RESET}   {os_label} {sep} zsh {zsh_ver} ({C_CYAN}{active_prompt}{C_RESET}) {sep} nvim {nvim_ver}")
    print(f"  {C_MAUVE}Repository:{C_RESET}   {C_BOLD}{branch}{C_RESET} ({C_CYAN}{commit}{C_RESET}{sync_str}) {sep} {tree_str}")
    print(f"  {C_MAUVE}Symlinks:{C_RESET}     {link_str}")
    print(f"  {C_MAUVE}Runtimes:{C_RESET}     node {C_GREEN}{node_ver}{C_RESET} {sep} uv {C_GREEN}{uv_ver}{C_RESET}")

    print(f"\n{C_BOLD}Commands{C_RESET}")
    for cmd_str, alias_str, desc in SUBCOMMANDS_TABLE:
        alias_col = f"{C_DIM}({alias_str}){C_RESET}" if alias_str else ""
        print(f"  {C_CYAN}{cmd_str:<21}{C_RESET} {alias_col:<28} {desc}")
    print()
    return 0
