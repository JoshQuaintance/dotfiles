#!/usr/bin/env python3
"""Clipboard text transformation pipeline executable (`clip`)."""

from __future__ import annotations

import base64
import json
import sys
import urllib.parse


def _transform_json(text: str) -> str:
    """Pretty-print JSON with 2-space indentation."""
    obj = json.loads(text)
    return json.dumps(obj, indent=2, ensure_ascii=False)


def _transform_min(text: str) -> str:
    """Minify JSON or collapse whitespace in plain text."""
    try:
        obj = json.loads(text)
        return json.dumps(obj, separators=(",", ":"), ensure_ascii=False)
    except ValueError:
        return " ".join(text.split())


def _transform_sort(text: str) -> str:
    """Sort and deduplicate lines preserving first-seen order after sorting."""
    seen: set[str] = set()
    lines: list[str] = []
    for line in sorted(text.splitlines()):
        if line not in seen:
            seen.add(line)
            lines.append(line)
    return "\n".join(lines)


def _transform_b64d(text: str) -> str:
    """Decode standard or URL-safe Base64 string into UTF-8 text."""
    raw = text.strip()
    padded = raw + "=" * ((4 - len(raw) % 4) % 4)
    return base64.urlsafe_b64decode(padded.encode("ascii")).decode("utf-8", errors="replace")


def main() -> int:
    """Entry point for clip_transform Python executable."""
    op = sys.argv[1] if len(sys.argv) > 1 else ""
    text = sys.argv[2] if len(sys.argv) > 2 else ""

    if op == "json":
        try:
            print(_transform_json(text), end="")
            return 0
        except ValueError as exc:
            print(f"Invalid JSON: {exc}", file=sys.stderr)
            return 1

    dispatch = {
        "trim": lambda s: "\n".join(line.rstrip() for line in s.strip().splitlines()),
        "min": _transform_min,
        "sort": _transform_sort,
        "lower": lambda s: s.lower(),
        "upper": lambda s: s.upper(),
        "urlencode": lambda s: urllib.parse.quote(s.strip(), safe=""),
        "urldecode": lambda s: urllib.parse.unquote_plus(s.strip()),
        "b64e": lambda s: base64.b64encode(s.encode("utf-8")).decode("ascii"),
        "b64d": _transform_b64d,
    }
    handler = dispatch.get(op)
    if handler is not None:
        print(handler(text), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
