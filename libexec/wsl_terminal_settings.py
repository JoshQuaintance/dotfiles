#!/usr/bin/env python3
"""Merge canonical Windows Terminal template settings into a user's settings.json."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


def parse_jsonc(raw: str) -> dict[str, Any]:
    """Strip JSONC line/block comments and trailing commas before parsing JSON."""
    token_re = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/')
    stripped = token_re.sub(lambda m: m.group(0) if m.group(0).startswith('"') else "", raw)
    cleaned = re.sub(r",(\s*[}\]])", r"\1", stripped)
    result: dict[str, Any] = json.loads(cleaned)
    return result


def _merge_schemes(data: dict[str, Any], template: dict[str, Any]) -> None:
    """Merge color schemes from template into data by scheme name."""
    if "schemes" not in data or not isinstance(data["schemes"], list):
        data["schemes"] = []
    for tpl_scheme in template.get("schemes", []):
        scheme_name = tpl_scheme.get("name")
        if not scheme_name:
            continue
        scheme_idx = next((i for i, s in enumerate(data["schemes"]) if s.get("name") == scheme_name), None)
        if scheme_idx is not None:
            data["schemes"][scheme_idx] = tpl_scheme
        else:
            data["schemes"].append(tpl_scheme)


def _merge_profile_defaults(data: dict[str, Any], template: dict[str, Any]) -> None:
    """Merge profiles.defaults from template into data, preserving profiles.list."""
    if "profiles" not in data or not isinstance(data["profiles"], dict):
        data["profiles"] = {}
    if "defaults" not in data["profiles"] or not isinstance(data["profiles"]["defaults"], dict):
        data["profiles"]["defaults"] = {}

    tpl_defaults = template.get("profiles", {}).get("defaults", {})
    for key, val in tpl_defaults.items():
        if key == "font" and isinstance(val, dict):
            if "font" not in data["profiles"]["defaults"] or not isinstance(data["profiles"]["defaults"]["font"], dict):
                data["profiles"]["defaults"]["font"] = {}
            data["profiles"]["defaults"]["font"].update(val)
        else:
            data["profiles"]["defaults"][key] = val


def _merge_actions(data: dict[str, Any], template: dict[str, Any]) -> None:
    """Merge keybindings/actions from template into data matched by 'keys'."""
    if "actions" not in template or not isinstance(template["actions"], list):
        return
    target_key = "actions" if "actions" in data or "keybindings" not in data else "keybindings"
    if target_key not in data or not isinstance(data[target_key], list):
        data[target_key] = []
    for tpl_action in template["actions"]:
        keys = tpl_action.get("keys")
        if not keys:
            continue
        act_idx = next((i for i, a in enumerate(data[target_key]) if a.get("keys") == keys), None)
        if act_idx is not None:
            data[target_key][act_idx] = tpl_action
        else:
            data[target_key].append(tpl_action)


def main() -> int:
    """Entry point for Windows Terminal settings merger."""
    settings_path, template_path = Path(sys.argv[1]), Path(sys.argv[2])
    try:
        data = parse_jsonc(settings_path.read_text(encoding="utf-8"))
        template = parse_jsonc(template_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print(f"\033[38;2;243;139;168m[ERROR]\033[0m Failed to parse JSON: {exc}", file=sys.stderr)
        return 1

    for top_key in ("copyOnSelect", "copyFormatting", "trimBlockSelection"):
        if top_key in template:
            data[top_key] = template[top_key]

    _merge_schemes(data, template)
    _merge_profile_defaults(data, template)
    _merge_actions(data, template)

    with settings_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=4)

    print(
        "\033[38;2;166;227;161m[✔]\033[0m Successfully synced Windows Terminal settings "
        "from config/windows-terminal/settings.json!"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
