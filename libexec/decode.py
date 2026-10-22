#!/usr/bin/env python3
"""Universal JWT, UUIDv7, Epoch timestamp, URL, HTML entity, Hex, and Base64 decoder (`decode`)."""

from __future__ import annotations

import base64
import datetime
import html
import json
import re
import sys
import urllib.parse

C_MAUVE = "\033[1;38;2;203;166;247m"
C_BLUE = "\033[1;38;2;137;180;250m"
C_GREEN = "\033[1;38;2;166;227;161m"
C_YELLOW = "\033[1;38;2;249;226;175m"
C_RED = "\033[1;38;2;243;139;168m"
C_RST = "\033[0m"

UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-([0-9a-fA-F])[0-9a-fA-F]{3}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)


def b64url_decode(segment: str) -> bytes:
    """Decode standard or URL-safe Base64 with automatic padding."""
    padded = segment + "=" * ((4 - len(segment) % 4) % 4)
    return base64.urlsafe_b64decode(padded.encode("ascii"))


def _rel_delta(secs: int) -> str:
    """Format a signed second delta into a human-readable duration."""
    abs_s = abs(secs)
    if abs_s >= 86400:
        return f"{abs_s // 86400}d {(abs_s % 86400) // 3600}h"
    if abs_s >= 3600:
        return f"{abs_s // 3600}h {(abs_s % 3600) // 60}m"
    return f"{abs_s // 60}m {abs_s % 60}s"


def fmt_epoch(ts: float) -> str:
    """Format a Unix epoch timestamp into UTC, local time, and relative delta."""
    utc_dt = datetime.datetime.fromtimestamp(ts, tz=datetime.timezone.utc)
    local_dt = utc_dt.astimezone()
    now = datetime.datetime.now(tz=datetime.timezone.utc)
    secs = int((utc_dt - now).total_seconds())
    rel = _rel_delta(secs)
    rel_str = f"in {rel}" if secs >= 0 else f"{rel} ago"
    return f"{utc_dt.strftime('%Y-%m-%d %H:%M:%S UTC')} | {local_dt.strftime('%Y-%m-%d %H:%M:%S %Z')} ({rel_str})"


def _try_decode_jwt(raw: str) -> bool:
    """Attempt to decode a JWT token and print its header, payload, and timestamp claims."""
    parts = raw.split(".")
    if len(parts) not in (2, 3) or not raw.startswith("eyJ"):
        return False
    try:
        hdr = json.loads(b64url_decode(parts[0]).decode("utf-8"))
        pay = json.loads(b64url_decode(parts[1]).decode("utf-8"))
    except (ValueError, UnicodeError, TypeError):
        return False

    print(f"{C_MAUVE}🔑 JWT Header:{C_RST}")
    print(json.dumps(hdr, indent=2))
    print(f"\n{C_BLUE}📦 JWT Payload:{C_RST}")
    print(json.dumps(pay, indent=2))
    now_ts = datetime.datetime.now(tz=datetime.timezone.utc).timestamp()
    for claim in ("iat", "nbf", "exp"):
        if isinstance(pay.get(claim), (int, float)):
            val = float(pay[claim])
            status = ""
            if claim == "exp":
                delta = _rel_delta(int(val - now_ts))
                status = (
                    f"{C_GREEN}✔ VALID (for {delta}){C_RST} "
                    if val > now_ts
                    else f"{C_RED}✖ EXPIRED ({delta} ago){C_RST} "
                )
            print(f"\n{C_BLUE}{claim}:{C_RST} {status}{fmt_epoch(val)}")
    return True


def _try_decode_uuid(raw: str) -> bool:
    """Inspect a UUID string and extract embedded timestamp if UUIDv7."""
    m = UUID_RE.match(raw)
    if not m:
        return False
    version = int(m.group(1), 16)
    print(f"{C_MAUVE}🆔 UUID (v{version}):{C_RST} {raw.lower()}")
    if version == 7:
        hex_clean = raw.replace("-", "")
        ms = int(hex_clean[:12], 16)
        print(f"{C_BLUE}➜ Created:{C_RST} {fmt_epoch(ms / 1000.0)}")
    return True


def _try_decode_url_or_html(raw: str) -> bool:
    """Attempt to decode a percent-encoded URL/query string or HTML entities."""
    if "&" in raw and ";" in raw and re.search(r"&(#\d+|#x[0-9a-fA-F]+|[a-zA-Z]+);", raw):
        unescaped = html.unescape(raw)
        if unescaped != raw:
            print(f"{C_MAUVE}🏷  Decoded HTML Entities:{C_RST}\n{unescaped}")
            return True

    if "%" not in raw and "://" not in raw and not ("?" in raw and "=" in raw):
        return False
    unquoted = urllib.parse.unquote_plus(raw)
    if unquoted == raw and "://" not in raw:
        return False
    print(f"{C_MAUVE}🌐 Decoded URL:{C_RST}\n{unquoted}")
    parsed = urllib.parse.urlsplit(raw if "://" in raw else "http://x/?" + raw.lstrip("?"))
    qs = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
    if qs:
        print(f"\n{C_BLUE}Query Parameters:{C_RST}")
        for k, v in qs:
            print(f"  {C_GREEN}{k}{C_RST} = {v}")
    return True


def _try_decode_hex(raw: str) -> bool:
    r"""Attempt to decode a 0x-prefixed, \x-escaped, or pure hex UTF-8 string."""
    cleaned = raw
    if cleaned.lower().startswith("0x"):
        cleaned = cleaned[2:]
    elif "\\x" in cleaned.lower():
        cleaned = re.sub(r"\\x", "", cleaned, flags=re.IGNORECASE)
    elif not (len(cleaned) >= 8 and len(cleaned) % 2 == 0 and re.fullmatch(r"[0-9a-fA-F]+", cleaned)):
        return False

    if len(cleaned) % 2 != 0 or not re.fullmatch(r"[0-9a-fA-F]+", cleaned):
        return False
    try:
        decoded = bytes.fromhex(cleaned).decode("utf-8")
    except (ValueError, UnicodeError):
        return False
    if not all(ch.isprintable() or ch in "\n\r\t" for ch in decoded):
        return False
    print(f"{C_MAUVE}🔢 Decoded Hex:{C_RST}\n{decoded}")
    return True


def _try_decode_epoch(raw: str) -> bool:
    """Attempt to decode a 10-digit (s), 13-digit (ms), or 16-digit (us) epoch timestamp."""
    if not re.fullmatch(r"\d{10}(\.\d+)?|\d{13}|\d{16}", raw):
        return False
    ts = float(raw)
    digits = len(raw.split(".")[0])
    if digits == 13:
        ts /= 1000.0
    elif digits == 16:
        ts /= 1_000_000.0
    print(f"{C_MAUVE}⏱  Epoch Timestamp:{C_RST} {raw}")
    print(f"{C_BLUE}➜{C_RST}  {fmt_epoch(ts)}")
    return True


def main() -> int:
    """Entry point for decode Python executable."""
    raw = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
    if raw.lower().startswith("bearer "):
        raw = raw[7:].strip()

    for handler in (
        _try_decode_jwt,
        _try_decode_uuid,
        _try_decode_epoch,
        _try_decode_url_or_html,
        _try_decode_hex,
    ):
        if handler(raw):
            return 0

    try:
        b_out = b64url_decode(raw).decode("utf-8")
        try:
            j_obj = json.loads(b_out)
            print(json.dumps(j_obj, indent=2))
        except ValueError:
            print(b_out)
    except (ValueError, UnicodeError):
        print(
            f"{C_RED}✖ Could not decode input as JWT, UUID, Epoch, URL, HTML, Hex, or UTF-8 Base64.{C_RST}",
            file=sys.stderr,
        )
        return 1
    else:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
