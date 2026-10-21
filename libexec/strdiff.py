#!/usr/bin/env python3
"""Character-level and word-level inline string diff executable (`strdiff`)."""

from __future__ import annotations

import difflib
import re
import sys

C_RED_FG = "\033[1;38;2;243;139;168m"
C_GREEN_FG = "\033[1;38;2;166;227;161m"
C_BLUE_FG = "\033[1;38;2;137;180;250m"
C_DIM = "\033[2m"
C_DEL = "\033[1;38;2;243;139;168;48;2;69;39;50m"
C_ADD = "\033[1;38;2;166;227;161;48;2;35;57;46m"
C_RST = "\033[0m"


def fmt_ws(s: str, is_edge: bool = False) -> str:
    """Render leading/trailing or whitespace-only spans with visible glyphs."""
    if not s:
        return s
    if s.strip(" \t") == "":
        return s.replace(" ", "·").replace("\t", "→")
    if is_edge:
        lstripped = s.lstrip(" \t")
        rstripped = s.rstrip(" \t")
        lead_len = len(s) - len(lstripped)
        trail_len = len(s) - len(rstripped)
        lead = s[:lead_len].replace(" ", "·").replace("\t", "→")
        trail = s[len(rstripped) :].replace(" ", "·").replace("\t", "→") if trail_len > 0 else ""
        mid = s[lead_len : len(s) - trail_len]
        return lead + mid + trail
    return s


def tokenize(s: str, mode: str) -> list[str]:
    """Split a line into words or individual characters based on diff mode."""
    if mode == "word":
        return re.findall(r"\S+|\s+", s)
    return list(s)


def diff_line(la: str, lb: str, mode: str) -> tuple[str, str, str, float]:
    """Compute old, new, and inline diff strings and similarity ratio for a line pair."""
    ta, tb = tokenize(la, mode), tokenize(lb, mode)
    sm = difflib.SequenceMatcher(None, ta, tb)
    old_p: list[str] = []
    new_p: list[str] = []
    inl_p: list[str] = []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        sa = "".join(ta[i1:i2])
        sb = "".join(tb[j1:j2])
        edge_a = i1 == 0 or i2 == len(ta)
        edge_b = j1 == 0 or j2 == len(tb)
        if tag == "equal":
            old_p.append(sa)
            new_p.append(sb)
            inl_p.append(sa)
        elif tag == "delete":
            fa = fmt_ws(sa, edge_a)
            old_p.append(f"{C_DEL}{fa}{C_RST}")
            inl_p.append(f"{C_DEL}{fa}{C_RST}")
        elif tag == "insert":
            fb = fmt_ws(sb, edge_b)
            new_p.append(f"{C_ADD}{fb}{C_RST}")
            inl_p.append(f"{C_ADD}{fb}{C_RST}")
        elif tag == "replace":
            fa = fmt_ws(sa, edge_a)
            fb = fmt_ws(sb, edge_b)
            old_p.append(f"{C_DEL}{fa}{C_RST}")
            new_p.append(f"{C_ADD}{fb}{C_RST}")
            inl_p.append(f"{C_DEL}{fa}{C_RST}{C_ADD}{fb}{C_RST}")
    return "".join(old_p), "".join(new_p), "".join(inl_p), sm.ratio()


def _render_replace_chunk(ca: list[str], cb: list[str], mode: str, single_line: bool) -> None:
    """Render a replaced block of lines with inline diff when similarity is sufficient."""
    pairs = min(len(ca), len(cb))
    for k in range(pairs):
        o, n, inl, ratio = diff_line(ca[k], cb[k], mode)
        if single_line or ratio >= 0.45:
            print(f"  {C_RED_FG}-{C_RST} {o}")
            print(f"  {C_GREEN_FG}+{C_RST} {n}")
            print(f"  {C_BLUE_FG}Δ{C_RST} {inl}")
        else:
            print(f"  {C_RED_FG}-{C_RST} {C_DEL}{fmt_ws(ca[k], True)}{C_RST}")
            print(f"  {C_GREEN_FG}+{C_RST} {C_ADD}{fmt_ws(cb[k], True)}{C_RST}")
    for line in ca[pairs:]:
        print(f"  {C_RED_FG}-{C_RST} {C_DEL}{fmt_ws(line, True)}{C_RST}")
    for line in cb[pairs:]:
        print(f"  {C_GREEN_FG}+{C_RST} {C_ADD}{fmt_ws(line, True)}{C_RST}")


def main() -> int:
    """Entry point for strdiff Python executable."""
    a = sys.argv[1] if len(sys.argv) > 1 else ""
    b = sys.argv[2] if len(sys.argv) > 2 else ""
    mode = sys.argv[3] if len(sys.argv) > 3 else "char"

    if a == b:
        print(f"{C_GREEN_FG}✔ Strings are identical{C_RST} {C_DIM}({len(a)} chars){C_RST}")
        return 0

    lines_a = a.splitlines() or [""]
    lines_b = b.splitlines() or [""]
    single_line = len(lines_a) == 1 and len(lines_b) == 1

    sm_lines = difflib.SequenceMatcher(None, lines_a, lines_b)
    for tag, i1, i2, j1, j2 in sm_lines.get_opcodes():
        if tag == "equal":
            for line in lines_a[i1:i2]:
                print(f"    {C_DIM}{line}{C_RST}")
        elif tag == "delete":
            for line in lines_a[i1:i2]:
                print(f"  {C_RED_FG}-{C_RST} {C_DEL}{fmt_ws(line, True)}{C_RST}")
        elif tag == "insert":
            for line in lines_b[j1:j2]:
                print(f"  {C_GREEN_FG}+{C_RST} {C_ADD}{fmt_ws(line, True)}{C_RST}")
        elif tag == "replace":
            _render_replace_chunk(lines_a[i1:i2], lines_b[j1:j2], mode, single_line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
