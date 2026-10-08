import json
import os
import re
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from cli.clean import remove_target
from cli.manifest import get_dotfiles_dir
from cli.ui import (
    C_BLUE,
    C_BOLD,
    C_CYAN,
    C_DIM,
    C_GREEN,
    C_RED,
    C_RESET,
    C_YELLOW,
    ICON_OK,
    print_header,
)

BREWFILE_ENTRY = re.compile(r'^\s*(brew|cask)\s+"([^"]+)"')
TOML_TABLE = re.compile(r"^\s*\[([^\]]+)\]")
TOML_KEY = re.compile(r'^\s*"?([^"=\s]+)"?\s*=')
MISE_CONFIG = "config/mise/config.toml"
COMPLETIONS_DIR = "zsh/custom/completions/"


@dataclass
class PrunePlan:
    """Everything on this machine that came from files deleted between two commits."""

    old: str
    links: list[tuple[Path, str]] = field(default_factory=list)  # (symlink, repo path it pointed to)
    caches: list[Path] = field(default_factory=list)
    brew: dict[str, list[str]] = field(default_factory=dict)  # "brew"/"cask" -> names
    mise: list[str] = field(default_factory=list)

    @property
    def empty(self) -> bool:
        return not (self.links or self.caches or self.brew or self.mise)


@dataclass
class Orphans:
    """Installed packages that nothing in these dotfiles asks for (`dot prune --orphans`)."""

    brew: dict[str, list[str]] = field(default_factory=dict)  # "brew"/"cask" -> names
    mise: list[str] = field(default_factory=list)  # tool@version no tracked config uses

    @property
    def empty(self) -> bool:
        return not (self.brew or self.mise)


def _git(dotfiles: Path, *args: str) -> str:
    res = subprocess.run(["git", "-C", str(dotfiles), *args], capture_output=True, text=True, check=False)
    return res.stdout if res.returncode == 0 else ""


def _confirm(prompt: str, default: bool = True) -> bool:
    try:
        answer = input(prompt).strip().lower()
    except (EOFError, KeyboardInterrupt):
        return False
    return answer.startswith("y") if answer else default


def deleted_paths(dotfiles: Path, old: str, new: str) -> set[str]:
    """Repo paths that existed at `old` but are gone at `new` (deletions and the old side of renames)."""
    gone: set[str] = set()
    for line in _git(dotfiles, "diff", "--name-status", "-M", old, new).splitlines():
        status, *paths = line.split("\t")
        if status == "D" or status.startswith("R"):
            gone.add(paths[0])
    return gone


def _fully_deleted(dotfiles: Path, old: str, rel: str, gone: set[str]) -> bool:
    """True when every file tracked under `rel` at `old` (a file or a directory) was removed."""
    tracked = _git(dotfiles, "ls-tree", "-r", "--name-only", old, "--", rel).splitlines()
    return bool(tracked) and all(path in gone for path in tracked)


def _scan_roots() -> list[tuple[Path, int]]:
    home = Path.home()
    roots = [
        (home, 1),
        (home / ".config", 3),
        (home / ".local" / "bin", 1),
        (home / "Library" / "Application Support" / "Code" / "User", 2),
    ]
    return [(path, depth) for path, depth in roots if path.is_dir()]


def find_stale_links(dotfiles: Path, old: str, gone: set[str]) -> list[tuple[Path, str]]:
    """Symlinks into the repo whose target was deleted since `old` (or no longer exists at all)."""
    repo_roots = {os.path.normpath(str(dotfiles)), os.path.normpath(str(dotfiles.resolve()))}
    stale: list[tuple[Path, str]] = []
    seen: set[Path] = set()

    for root, max_depth in _scan_roots():
        for current, dirnames, filenames in os.walk(root, followlinks=False):
            for name in dirnames + filenames:
                link = Path(current) / name
                if link in seen or not link.is_symlink():
                    continue
                seen.add(link)
                raw = os.readlink(link)
                target = os.path.normpath(raw if os.path.isabs(raw) else os.path.join(current, raw))
                rel = next((target[len(repo) + 1:] for repo in repo_roots if target.startswith(repo + os.sep)), None)
                if rel and (not os.path.exists(target) or _fully_deleted(dotfiles, old, rel, gone)):
                    stale.append((link, rel))
            if len(Path(current).relative_to(root).parts) + 1 >= max_depth:
                dirnames[:] = []
    return stale


def find_stale_caches(dotfiles: Path, gone: set[str]) -> list[Path]:
    """Compiled .zwc files left beside deleted zsh sources, plus compdumps if a completion was removed."""
    caches = [dotfiles / f"{rel}.zwc" for rel in sorted(gone) if (dotfiles / f"{rel}.zwc").exists()]
    if any(rel.startswith(COMPLETIONS_DIR) for rel in gone):
        caches += sorted(Path(os.environ.get("ZDOTDIR", Path.home())).glob(".zcompdump*"))
    return caches


def _brewfile_entries(text: str) -> dict[str, set[str]]:
    entries: dict[str, set[str]] = {"brew": set(), "cask": set()}
    for line in text.splitlines():
        match = BREWFILE_ENTRY.match(line)
        if match:
            entries[match.group(1)].add(match.group(2))
    return entries


def find_removed_brew(dotfiles: Path, old: str, new: str) -> dict[str, list[str]]:
    """Installed Homebrew formulae/casks that were dropped from the Brewfile between `old` and `new`."""
    if not shutil.which("brew"):
        return {}
    before = _brewfile_entries(_git(dotfiles, "show", f"{old}:Brewfile"))
    after = _brewfile_entries(_git(dotfiles, "show", f"{new}:Brewfile"))
    removed: dict[str, list[str]] = {}
    for kind in ("brew", "cask"):
        dropped = before[kind] - after[kind]
        if not dropped:
            continue
        flag = "--cask" if kind == "cask" else "--formula"
        res = subprocess.run(["brew", "list", flag, "-1"], capture_output=True, text=True, check=False)
        installed = set(res.stdout.split())
        hits = sorted(name for name in dropped if name.split("/")[-1] in installed)
        if hits:
            removed[kind] = hits
    return removed


def _mise_tools(text: str) -> set[str]:
    """Keys of the [tools] table (line-based, so it works on Python < 3.11 without tomllib)."""
    tools: set[str] = set()
    table = ""
    for line in text.splitlines():
        if match := TOML_TABLE.match(line):
            table = match.group(1).strip()
        elif table == "tools" and (match := TOML_KEY.match(line)):
            tools.add(match.group(1))
    return tools


def find_removed_mise(dotfiles: Path, old: str, new: str) -> list[str]:
    """Installed mise tools that were dropped from the global mise config between `old` and `new`."""
    if not shutil.which("mise"):
        return []
    dropped = _mise_tools(_git(dotfiles, "show", f"{old}:{MISE_CONFIG}")) - _mise_tools(_git(dotfiles, "show", f"{new}:{MISE_CONFIG}"))
    if not dropped:
        return []
    res = subprocess.run(["mise", "ls", "--installed", "--json"], capture_output=True, text=True, check=False)
    try:
        installed = set(json.loads(res.stdout or "{}"))
    except json.JSONDecodeError:
        return []
    return sorted(dropped & installed)


def find_orphans(dotfiles: Path) -> Orphans:
    """Brew packages installed on request but missing from the Brewfile, and mise versions no config uses."""
    orphans = Orphans()
    if shutil.which("brew"):
        brewfile = dotfiles / "Brewfile"
        wanted = _brewfile_entries(brewfile.read_text() if brewfile.is_file() else "")
        listings = {"brew": ["brew", "leaves", "--installed-on-request"], "cask": ["brew", "list", "--cask", "-1"]}
        for kind, cmd in listings.items():
            short_wanted = {name.split("/")[-1] for name in wanted[kind]}
            res = subprocess.run(cmd, capture_output=True, text=True, check=False)
            extra = sorted(name for name in res.stdout.split() if name.split("/")[-1] not in short_wanted)
            if extra:
                orphans.brew[kind] = extra
    if shutil.which("mise"):
        res = subprocess.run(["mise", "ls", "--prunable", "--json"], capture_output=True, text=True, check=False)
        try:
            prunable = json.loads(res.stdout or "{}")
        except json.JSONDecodeError:
            prunable = {}
        orphans.mise = sorted(
            f"{tool}@{entry['version']}" for tool, entries in prunable.items() for entry in entries if entry.get("installed", True)
        )
    return orphans


def print_orphans(orphans: Orphans) -> None:
    for kind, names in orphans.brew.items():
        label = "cask" if kind == "cask" else "formula"
        for name in names:
            print(f"  {C_YELLOW}?{C_RESET} brew {label} {name} {C_DIM}(not in Brewfile){C_RESET}")
    for tool in orphans.mise:
        print(f"  {C_YELLOW}?{C_RESET} mise {tool} {C_DIM}(unused by any tracked mise config){C_RESET}")


def apply_orphans(orphans: Orphans) -> int:
    """Uninstall orphans after an explicit yes (defaults to no: some may have been installed on purpose)."""
    total = sum(map(len, orphans.brew.values())) + len(orphans.mise)
    if not _confirm(f"Uninstall these {total} package(s)? [y/N]: ", default=False):
        print("Kept them. Add packages you want to keep to the Brewfile or config/mise/config.toml.")
        return 0
    removed = 0
    for kind, names in orphans.brew.items():
        cmd = ["brew", "uninstall", "--cask" if kind == "cask" else "--formula", *names]
        if subprocess.run(cmd, check=False).returncode == 0:
            removed += len(names)
        else:
            print(f"{C_YELLOW}⚠ Some brew {kind}s were not uninstalled (still required by another package?){C_RESET}")
    for tool in orphans.mise:
        if subprocess.run(["mise", "uninstall", tool], check=False).returncode == 0:
            removed += 1
    return removed


def plan_prune(dotfiles: Path, old: str, new: str) -> PrunePlan:
    """Work out what to remove for the commit range `old`..`new` without changing anything."""
    gone = deleted_paths(dotfiles, old, new)
    return PrunePlan(
        old=old,
        links=find_stale_links(dotfiles, old, gone),
        caches=find_stale_caches(dotfiles, gone),
        brew=find_removed_brew(dotfiles, old, new),
        mise=find_removed_mise(dotfiles, old, new),
    )


def _short(path: Path) -> str:
    return str(path).replace(str(Path.home()), "~")


def print_plan(plan: PrunePlan) -> None:
    for link, rel in plan.links:
        print(f"  {C_RED}-{C_RESET} {_short(link)} {C_DIM}(link to removed {rel}){C_RESET}")
    for cache in plan.caches:
        print(f"  {C_RED}-{C_RESET} {_short(cache)} {C_DIM}(stale zsh cache){C_RESET}")
    for kind, names in plan.brew.items():
        for name in names:
            label = "cask" if kind == "cask" else "formula"
            print(f"  {C_RED}-{C_RESET} brew {label} {name} {C_DIM}(dropped from Brewfile){C_RESET}")
    for tool in plan.mise:
        print(f"  {C_RED}-{C_RESET} mise {tool} {C_DIM}(dropped from {MISE_CONFIG}){C_RESET}")


def preview_prune(dotfiles: Path, old: str, new: str) -> None:
    """Show what `dot update` would remove for `old`..`new`."""
    plan = plan_prune(dotfiles, old, new)
    if not plan.empty:
        print(f"{C_YELLOW}🧹 Applying this update would also remove:{C_RESET}")
        print_plan(plan)
        print()


def apply_prune(dotfiles: Path, plan: PrunePlan, title: Optional[str] = None) -> None:
    """Remove links and caches right away; ask before uninstalling any brew package or mise tool."""
    if plan.empty:
        return
    print(f"\n{C_BLUE}==>{C_RESET} {title or f'Removed upstream since {C_CYAN}{plan.old[:7]}{C_RESET}'}:")
    print_plan(plan)

    # Links and caches only point at files that no longer exist in the repo, so they are always safe to drop
    for link, _ in plan.links:
        link.unlink(missing_ok=True)
    for cache in plan.caches:
        remove_target(cache, dry_run=False)
        parent = cache.parent
        while parent != dotfiles and parent.is_relative_to(dotfiles) and not any(parent.iterdir()):
            parent.rmdir()
            parent = parent.parent

    # Packages may still be used outside these dotfiles, so they always need an explicit yes (even with -y)
    packages = sum(map(len, plan.brew.values())) + len(plan.mise)
    removed_packages = 0
    if packages and _confirm(f"Uninstall the {packages} package(s) listed above? [Y/n]: "):
        for kind, names in plan.brew.items():
            cmd = ["brew", "uninstall", "--cask" if kind == "cask" else "--formula", *names]
            if subprocess.run(cmd, check=False).returncode == 0:
                removed_packages += len(names)
            else:
                print(f"{C_YELLOW}⚠ Some brew {kind}s were not uninstalled (still required by another package?){C_RESET}")
        for tool in plan.mise:
            if subprocess.run(["mise", "uninstall", "--all", tool], check=False).returncode == 0:
                removed_packages += 1
    elif packages:
        print("Kept packages. Uninstall them later with 'brew uninstall' / 'mise uninstall --all'.")

    cleaned = len(plan.links) + len(plan.caches)
    print(f"{C_GREEN}✔{C_RESET} {C_BOLD}Pruned{C_RESET} {cleaned} file(s) and {removed_packages} package(s).")


def _default_base(dotfiles: Path) -> str:
    """The commit before the last pull/rebase (ORIG_HEAD) when it is an older ancestor of HEAD, else HEAD."""
    orig = _git(dotfiles, "rev-parse", "--verify", "-q", "ORIG_HEAD^{commit}").strip()
    head = _git(dotfiles, "rev-parse", "HEAD").strip()
    if orig and orig != head:
        res = subprocess.run(["git", "-C", str(dotfiles), "merge-base", "--is-ancestor", orig, head], check=False)
        if res.returncode == 0:
            return orig
    return head


def run_prune(ref: Optional[str] = None, dry_run: bool = False, orphans: bool = False) -> int:
    """`dot prune`: remove what was deleted from the dotfiles between `ref` (default ORIG_HEAD) and HEAD.

    With `orphans`, also offer to uninstall packages that nothing in the dotfiles asks for.
    """
    dotfiles = get_dotfiles_dir()
    print_header(f"Dotfiles Pruner \u2014 Removed Upstream Files{' [DRY RUN]' if dry_run else ''}")
    print()

    old = _git(dotfiles, "rev-parse", "--verify", "-q", f"{ref}^{{commit}}").strip() if ref else _default_base(dotfiles)
    if not old:
        print(f"{C_RED}\u2716 Unknown commit '{ref}'.{C_RESET}")
        return 1

    head = _git(dotfiles, "rev-parse", "HEAD").strip()
    if old == head:
        print(f"{C_DIM}No earlier commit to compare against; checking for dangling links into the repo only.{C_RESET}")
    else:
        count = _git(dotfiles, "rev-list", "--count", f"{old}..{head}").strip()
        print(f"Comparing {C_CYAN}{old[:7]}{C_RESET}..{C_CYAN}{head[:7]}{C_RESET} {C_DIM}({count} commit(s)){C_RESET}")

    plan = plan_prune(dotfiles, old, head)
    if plan.empty:
        print(f"  {C_GREEN}{ICON_OK}{C_RESET} Nothing to prune.")
    elif dry_run:
        print(f"\n{C_YELLOW}Would remove:{C_RESET}")
        print_plan(plan)
    else:
        apply_prune(dotfiles, plan, title="Pruning")

    if orphans:
        print(f"\n{C_BLUE}==>{C_RESET} Installed but not declared in the dotfiles:")
        found = find_orphans(dotfiles)
        if found.empty:
            print(f"  {C_GREEN}{ICON_OK}{C_RESET} Every brew package and mise version is accounted for.")
        else:
            print_orphans(found)
            if not dry_run:
                removed = apply_orphans(found)
                if removed:
                    print(f"{C_GREEN}✔{C_RESET} {C_BOLD}Uninstalled{C_RESET} {removed} orphaned package(s).")
    return 0
