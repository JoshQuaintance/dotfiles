#!/usr/bin/env python3
"""Multi-digest file & directory checksum calculator and comparator (`checksum` / `hashc`)."""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
from collections import defaultdict
from pathlib import Path

C_MAUVE = "\033[1;38;2;203;166;247m"
C_BLUE = "\033[1;38;2;137;180;250m"
C_GREEN = "\033[1;38;2;166;227;161m"
C_YELLOW = "\033[1;38;2;249;226;175m"
C_RED = "\033[1;38;2;243;139;168m"
C_DIM = "\033[2m"
C_RST = "\033[0m"


def _hash_file(filepath: str) -> tuple[list[tuple[str, str]], int, int]:
    """Compute MD5, SHA-1, SHA-256, and SHA-512 for a single file."""
    path = Path(filepath)
    h_md5 = hashlib.md5()
    h_sha1 = hashlib.sha1()
    h_sha256 = hashlib.sha256()
    h_sha512 = hashlib.sha512()

    with path.open("rb") as f:
        while chunk := f.read(1024 * 1024):
            h_md5.update(chunk)
            h_sha1.update(chunk)
            h_sha256.update(chunk)
            h_sha512.update(chunk)

    digests = [
        ("MD5", h_md5.hexdigest()),
        ("SHA-1", h_sha1.hexdigest()),
        ("SHA-256", h_sha256.hexdigest()),
        ("SHA-512", h_sha512.hexdigest()),
    ]
    return digests, path.stat().st_size, 1


def _hash_directory(dirpath: str) -> tuple[list[tuple[str, str]], int, int]:
    """Compute deterministic MD5, SHA-1, SHA-256, and SHA-512 over a directory tree."""
    h_md5 = hashlib.md5()
    h_sha1 = hashlib.sha1()
    h_sha256 = hashlib.sha256()
    h_sha512 = hashlib.sha512()

    rel_files: list[tuple[str, Path]] = []
    for root, dirs, files in os.walk(dirpath):
        dirs[:] = sorted(d for d in dirs if d != ".git")
        root_path = Path(root)
        for fname in sorted(files):
            full = root_path / fname
            if full.is_file() and not full.is_symlink():
                rel = os.path.relpath(str(full), dirpath).replace(os.sep, "/")
                rel_files.append((rel, full))

    rel_files.sort(key=lambda item: item[0])
    total_bytes = 0
    for rel, full in rel_files:
        header = f"{rel}\0".encode()
        for h in (h_md5, h_sha1, h_sha256, h_sha512):
            h.update(header)
        total_bytes += full.stat().st_size
        with full.open("rb") as f:
            while chunk := f.read(1024 * 1024):
                h_md5.update(chunk)
                h_sha1.update(chunk)
                h_sha256.update(chunk)
                h_sha512.update(chunk)

    digests = [
        ("MD5", h_md5.hexdigest()),
        ("SHA-1", h_sha1.hexdigest()),
        ("SHA-256", h_sha256.hexdigest()),
        ("SHA-512", h_sha512.hexdigest()),
    ]
    return digests, total_bytes, len(rel_files)


def _render_target(
    target: str,
    digests: list[tuple[str, str]],
    total_bytes: int,
    file_count: int,
    expected: str,
) -> str | None:
    """Print formatted digests for a file or folder and return matched algorithm name if any."""
    target_path = Path(target)
    is_dir = target_path.is_dir()
    label = target_path.name or target
    if is_dir:
        meta = f"({file_count:,} files, {total_bytes:,} bytes)"
        print(f"{C_MAUVE}📁 {label}/{C_RST} {C_DIM}{meta}{C_RST}")
    else:
        print(f"{C_MAUVE}📄 {label}{C_RST} {C_DIM}({total_bytes:,} bytes){C_RST}")

    matched_algo: str | None = None
    for name, digest in digests:
        mark = ""
        if expected and digest == expected:
            matched_algo = name
            mark = f" {C_GREEN}✔ MATCH{C_RST}"
        print(f"  {C_BLUE}{name:<8}{C_RST} {digest}{mark}")
    return matched_algo


def _print_comparison(sha256_by_target: list[tuple[str, str]]) -> int:
    """Compare SHA-256 digests across 2+ targets and print comparison results."""
    by_hash: dict[str, list[str]] = defaultdict(list)
    for target, digest in sha256_by_target:
        by_hash[digest].append(target)

    if len(by_hash) == 1:
        print(f"\n{C_GREEN}✔ All {len(sha256_by_target)} targets are byte-for-byte identical{C_RST}")
        return 0

    print(
        f"\n{C_RED}✖ {len(by_hash)} distinct SHA-256 digests "
        f"across {len(sha256_by_target)} targets:{C_RST}"
    )
    for digest, group in by_hash.items():
        names = ", ".join(group)
        color = C_GREEN if len(group) > 1 else C_YELLOW
        marker = "=" if len(group) > 1 else "≠"
        print(f"  {color}{digest[:16]}…{C_RST}  {marker}  {names}")
    return 1


def _emit_summary(
    sha256_by_target: list[tuple[str, str]],
    expected: str,
    source: str,
    matched_algos: list[str],
    any_mismatch: bool,
    compare: bool,
) -> int:
    """Emit clipboard metadata and optional verification or comparison summary."""
    if len(sha256_by_target) == 1:
        print(f"__SHA256__:{sha256_by_target[0][1]}")
    else:
        for target, digest in sha256_by_target:
            print(f"__SHA256__:{digest}  {target}")

    if expected:
        if not any_mismatch and matched_algos:
            print(f"\n{C_GREEN}✔ Checksum verified ({matched_algos[0]} matched {source}){C_RST}")
            return 0
        print(f"\n{C_RED}✖ Checksum MISMATCH against {source}: {expected}{C_RST}")
        return 1

    if compare and len(sha256_by_target) > 1:
        return _print_comparison(sha256_by_target)

    return 0


def _parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse CLI arguments while staying resilient to legacy positional calls."""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("-e", "--expect", default="")
    parser.add_argument("-s", "--source", default="argument")
    parser.add_argument("--compare", action="store_true")
    parser.add_argument("paths", nargs="*")
    ns = parser.parse_args(argv)

    # Guard against legacy un-reloaded Zsh session passing: <file> <expected> "argument"
    if (
        len(ns.paths) == 3
        and ns.paths[2] in ("argument", "clipboard")
        and not Path(ns.paths[2]).exists()
        and Path(ns.paths[0]).exists()
    ):
        ns.expect = ns.paths[1]
        ns.source = ns.paths[2]
        ns.paths = [ns.paths[0]]

    return ns


def main() -> int:
    """Compute digests for files/folders and optionally verify or compare them."""
    ns = _parse_args(sys.argv[1:])
    expected = ns.expect.strip().lower()
    if ":" in expected:
        expected = expected.split(":", 1)[1].strip()

    sha256_by_target: list[tuple[str, str]] = []
    matched_algos: list[str] = []
    any_mismatch = False

    for idx, target in enumerate(ns.paths):
        if idx > 0:
            print()
        if Path(target).is_dir():
            digests, total_bytes, file_count = _hash_directory(target)
        else:
            digests, total_bytes, file_count = _hash_file(target)

        sha256_by_target.append((target, dict(digests)["SHA-256"]))
        matched = _render_target(target, digests, total_bytes, file_count, expected)
        if expected and matched:
            matched_algos.append(matched)
        elif expected:
            any_mismatch = True

    return _emit_summary(
        sha256_by_target,
        expected,
        ns.source,
        matched_algos,
        any_mismatch,
        ns.compare,
    )


if __name__ == "__main__":
    raise SystemExit(main())
