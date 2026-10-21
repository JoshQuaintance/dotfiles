#!/usr/bin/env python3
"""Universal JWT, Epoch timestamp, URL, and Base64 decoder executable (`decode`)."""

from __future__ import annotations

import base64
import datetime
import json
import re
import sys
import urllib.parse

C_MAUVE = "\033[1;38;2;203;166;247m"
C_BLUE = "\033[1;38;2;137;180;250m"
C_GREEN = "\033[1;38;2;166;227;161m"
C_RED = "\033[1;38;2;243;139;168m"
C_RST = "\033[0m"


def b64url_decode(segment: str) -> bytes:
    """Decode standard or URL-safe Base64 with automatic padding."""
    padded = segment + "=" * ((4 - len(segment) % 4) % 4)
    return base64.urlsafe_b64decode(padded.encode("ascii"))


def fmt_epoch(ts: float) -> str:
    """Format a Unix epoch timestamp into UTC, local time, and relative delta."""
    utc_dt = datetime.datetime.fromtimestamp(ts, tz=datetime.timezone.utc)
    local_dt = utc_dt.astimezone()
    now = datetime.datetime.now(tz=datetime.timezone.utc)
    secs = int((utc_dt - now).total_seconds())
    abs_s = abs(secs)
    if abs_s >= 86400:
        rel = f"{abs_s // 86400}d {(abs_s % 86400) // 3600}h"
    elif abs_s >= 3600:
        rel = f"{abs_s // 3600}h {(abs_s % 3600) // 60}m"
    else:
        rel = f"{abs_s // 60}m {abs_s % 60}s"
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
    for claim in ("iat", "nbf", "exp"):
        if isinstance(pay.get(claim), (int, float)):
            val = float(pay[claim])
            status = ""
            if claim == "exp":
                now_ts = datetime.datetime.now(tz=datetime.timezone.utc).timestamp()
                status = f"{C_GREEN}✔ VALID{C_RST} " if val > now_ts else f"{C_RED}✖ EXPIRED{C_RST} "
            print(f"\n{C_BLUE}{claim}:{C_RST} {status}{fmt_epoch(val)}")
    return True


def _try_decode_url(raw: str) -> bool:
    """Attempt to decode a percent-encoded URL or query string."""
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


def main() -> int:
    """Entry point for decode Python executable."""
    raw = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
    if raw.lower().startswith("bearer "):
        raw = raw[7:].strip()

    if _try_decode_jwt(raw):
        return 0

    if re.fullmatch(r"\d{10}(\.\d+)?|\d{13}", raw):
        ts = float(raw)
        if len(raw.split(".")[0]) == 13:
            ts /= 1000.0
        print(f"{C_MAUVE}⏱  Epoch Timestamp:{C_RST} {raw}")
        print(f"{C_BLUE}➜{C_RST}  {fmt_epoch(ts)}")
        return 0

    if _try_decode_url(raw):
        return 0

    try:
        b_out = b64url_decode(raw).decode("utf-8")
        try:
            j_obj = json.loads(b_out)
            print(json.dumps(j_obj, indent=2))
        except ValueError:
            print(b_out)
        return 0
    except (ValueError, UnicodeError):
        print(
            f"{C_RED}✖ Could not decode input as JWT, Epoch timestamp, URL, or UTF-8 Base64.{C_RST}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
