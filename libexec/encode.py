#!/usr/bin/env python3
"""Multi-format encoder executable (`encode`)."""

from __future__ import annotations

import argparse
import base64
import hashlib
import html
import sys
import urllib.parse

C_MAUVE = "\033[1;38;2;203;166;247m"
C_BLUE = "\033[1;38;2;137;180;250m"
C_GREEN = "\033[1;38;2;166;227;161m"
C_YELLOW = "\033[1;38;2;249;226;175m"
C_CYAN = "\033[1;38;2;137;220;235m"
C_PEACH = "\033[1;38;2;250;179;135m"
C_DIM = "\033[2m"
C_RST = "\033[0m"


def main() -> int:
    """Encode input string into Base64, URL, Hex, HTML, and SHA-256."""
    parser = argparse.ArgumentParser(description="Multi-format encoder")
    parser.add_argument("text", nargs="?", default="", help="Text to encode")
    parser.add_argument("-b", "--b64", action="store_true", help="Print Base64 only")
    parser.add_argument("-u", "--url", action="store_true", help="Print URL-encoded only")
    parser.add_argument("-x", "--hex", action="store_true", help="Print Hex only")
    parser.add_argument("--html", action="store_true", help="Print HTML-escaped only")
    parser.add_argument("-s", "--sha256", action="store_true", help="Print SHA-256 hash only")

    args = parser.parse_args()
    text = args.text
    if not text:
        if not sys.stdin.isatty():
            text = sys.stdin.read()
        else:
            print("Provide a string to encode.", file=sys.stderr)
            return 1

    b_text = text.encode("utf-8")
    b64_val = base64.b64encode(b_text).decode("ascii")
    b64u_val = base64.urlsafe_b64encode(b_text).decode("ascii").rstrip("=")
    url_val = urllib.parse.quote(text, safe="")
    hex_val = b_text.hex()
    html_val = html.escape(text)
    sha_val = hashlib.sha256(b_text).hexdigest()

    single_formats = (
        (args.b64, b64_val),
        (args.url, url_val),
        (args.hex, hex_val),
        (args.html, html_val),
        (args.sha256, sha_val),
    )
    for flag, val in single_formats:
        if flag:
            print(val, end="")
            return 0

    preview = repr(text) if len(text) <= 50 else repr(text[:47]) + "..."
    print(f"\n{C_MAUVE}⚡ Multi-Format Encoding{C_RST} {C_DIM}(input: {preview}){C_RST}")
    print(f"  {C_BLUE}Base64:{C_RST}      {b64_val}")
    print(f"  {C_CYAN}Base64URL:{C_RST}   {b64u_val}")
    print(f"  {C_YELLOW}URL Encoded:{C_RST} {url_val}")
    print(f"  {C_GREEN}Hex:{C_RST}         {hex_val}")
    print(f"  {C_PEACH}HTML:{C_RST}        {html_val}")
    print(f"  {C_DIM}SHA-256:{C_RST}     {sha_val}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
