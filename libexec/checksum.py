#!/usr/bin/env python3
"""Multi-digest file checksum and integrity verifier executable (`checksum`)."""

from __future__ import annotations

import hashlib
import os
import sys

C_MAUVE = "\033[1;38;2;203;166;247m"
C_BLUE = "\033[1;38;2;137;180;250m"
C_GREEN = "\033[1;38;2;166;227;161m"
C_RED = "\033[1;38;2;243;139;168m"
C_DIM = "\033[2m"
C_RST = "\033[0m"


def main() -> int:
    """Compute MD5, SHA-1, SHA-256, and SHA-512 in a single pass and verify expected digest."""
    filepath = sys.argv[1]
    expected = (sys.argv[2] if len(sys.argv) > 2 else "").strip().lower()
    source = sys.argv[3] if len(sys.argv) > 3 else "argument"

    if ":" in expected:
        expected = expected.split(":", 1)[1].strip()

    h_md5 = hashlib.md5()
    h_sha1 = hashlib.sha1()
    h_sha256 = hashlib.sha256()
    h_sha512 = hashlib.sha512()

    with open(filepath, "rb") as f:
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

    sz = os.path.getsize(filepath)
    print(f"{C_MAUVE}📄 {os.path.basename(filepath)}{C_RST} {C_DIM}({sz:,} bytes){C_RST}")
    matched_algo = None
    for name, digest in digests:
        mark = ""
        if expected and digest == expected:
            matched_algo = name
            mark = f" {C_GREEN}✔ MATCH{C_RST}"
        print(f"  {C_BLUE}{name:<8}{C_RST} {digest}{mark}")

    print(f"__SHA256__:{h_sha256.hexdigest()}")
    if expected:
        if matched_algo:
            print(f"\n{C_GREEN}✔ Checksum verified ({matched_algo} matched {source}){C_RST}")
            return 0
        print(f"\n{C_RED}✖ Checksum MISMATCH against {source}: {expected}{C_RST}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
