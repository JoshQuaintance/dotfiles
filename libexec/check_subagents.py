#!/usr/bin/env python3
"""Inspect Antigravity conversations, spawned subagents, swarm workers, models, and live status."""

from __future__ import annotations

import argparse
import collections
import datetime
import json
import os
import re
import sqlite3
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

C_MAUVE = "\033[1;38;2;203;166;247m"
C_BLUE = "\033[1;38;2;137;180;250m"
C_GREEN = "\033[1;38;2;166;227;161m"
C_YELLOW = "\033[1;38;2;249;226;175m"
C_RED = "\033[1;38;2;243;139;168m"
C_TEAL = "\033[1;38;2;148;226;213m"
C_BOLD = "\033[1m"
C_DIM = "\033[2m"
C_RST = "\033[0m"

MODEL_ID_RE = re.compile(
    rb"((?:gemini|claude|gpt|o1|o3|o4)-[a-zA-Z0-9._-]+)"
)
HUMAN_MODEL_RE = re.compile(
    rb"((?:Gemini|Claude|GPT)\s+[A-Za-z0-9 .()-]{2,40})"
)
UUID_RE = re.compile(
    r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})",
    re.IGNORECASE,
)


@dataclass
class RuntimeMetadata:
    """Metadata extracted from a conversation's `<cid>.db` (`gen_metadata` table)."""

    model_id: str = ""
    model_label: str = ""
    parent_id: str = ""
    root_id: str = ""
    subagent_type: str = ""
    stream_error: str = ""


@dataclass
class SpawnSpec:
    """Metadata recorded in a parent transcript when spawning a subagent or swarm worker."""

    conversation_id: str
    role: str = "Subagent"
    configured_model: str = "inherit"
    type_name: str = "self"
    order: int = 0


@dataclass
class SubagentRecord:
    """Consolidated record for a single child subagent or swarm worker."""

    conversation_id: str
    parent_id: str = ""
    nesting_depth: int = 1
    role: str = "Subagent"
    type_name: str = "self"
    configured_model: str = "inherit"
    runtime_model_id: str = ""
    runtime_model_label: str = ""
    status: str = "UNKNOWN"
    step_count: int = 0
    last_modified_time: str = ""
    latest_activity: str = ""
    killed: bool = False
    order: int = 0


@dataclass
class InspectionResult:
    """Structured result of inspecting a target conversation."""

    target_id: str
    title: str = ""
    is_subagent: bool = False
    parent_id: str = ""
    root_id: str = ""
    status: str = "UNKNOWN"
    step_count: int = 0
    last_modified_time: str = ""
    runtime_model_id: str = ""
    runtime_model_label: str = ""
    latest_activity: str = ""
    subagents: list[SubagentRecord] = field(default_factory=list)
    latest_with_subagents_hint: str = ""


def _connect_ro(db_path: Path) -> sqlite3.Connection:
    """Open a SQLite database in read-only URI mode so WAL writers are never blocked."""
    uri = f"file:{db_path.resolve()}?mode=ro"
    return sqlite3.connect(uri, uri=True, timeout=2.0)


def extract_runtime_metadata(conv_db_path: Path) -> RuntimeMetadata:
    """Extract runtime model, parent/root cascade IDs, and subagent type from `<cid>.db`."""
    meta = RuntimeMetadata()
    if not conv_db_path.is_file():
        return meta

    try:
        conn = _connect_ro(conv_db_path)
        cur = conn.cursor()
        cur.execute("SELECT data FROM gen_metadata ORDER BY idx DESC LIMIT 1;")
        row = cur.fetchone()
        conn.close()
    except sqlite3.Error:
        return meta

    if not row or not row[0]:
        return meta

    raw = row[0] if isinstance(row[0], bytes) else str(row[0]).encode("utf-8", errors="ignore")
    # Slice after the last b"sessionID" marker so embedded tool-schema examples
    # (which mention 'gemini-3.5-flash-lite' inside `invoke_subagent`) are never matched.
    tail_idx = raw.rfind(b"sessionID")
    tail = raw[tail_idx:] if tail_idx != -1 else raw[-2048:]

    model_matches = MODEL_ID_RE.findall(tail)
    if model_matches:
        meta.model_id = model_matches[0].decode("utf-8", errors="ignore")

    human_matches = HUMAN_MODEL_RE.findall(tail)
    if human_matches:
        meta.model_label = human_matches[-1].decode("utf-8", errors="ignore").strip()

    tail_text = tail.decode("utf-8", errors="ignore")
    parent_m = re.search(r"parent_cascade_id[^0-9a-fA-F]{1,8}([0-9a-fA-F-]{36})", tail_text)
    if parent_m:
        meta.parent_id = parent_m.group(1)

    root_m = re.search(r"root_cascade_id[^0-9a-fA-F]{1,8}([0-9a-fA-F-]{36})", tail_text)
    if root_m:
        meta.root_id = root_m.group(1)

    sub_m = re.search(r"subagent_type[^a-zA-Z0-9_-]{1,6}([a-zA-Z0-9_-]+)", tail_text)
    if sub_m:
        meta.subagent_type = sub_m.group(1)

    err_m = re.search(r"(stream reading error:[^\x00-\x1f\"\\]+)", tail_text)
    if err_m:
        meta.stream_error = err_m.group(1).strip()

    return meta


def parse_parent_transcript_spawns(transcript_path: Path) -> dict[str, SpawnSpec]:
    """Parse `transcript.jsonl` to match `invoke_subagent` (FIFO) and `swarm` add calls."""
    spawns: dict[str, SpawnSpec] = {}
    if not transcript_path.is_file():
        return spawns

    pending_invokes: collections.deque[dict[str, Any]] = collections.deque()

    try:
        lines = transcript_path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return spawns

    for line in lines:
        if not line.strip():
            continue
        try:
            step = json.loads(line)
        except json.JSONDecodeError:
            continue
        _process_transcript_spawn_step(step, pending_invokes, spawns)

    return spawns


def _clean_arg_str(val: Any, default: str = "") -> str:
    """Convert a tool-call argument to a clean string with outer JSON quotes stripped."""
    if val is None:
        return default
    s = str(val).strip()
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        s = s[1:-1].strip()
    return s or default


def _process_transcript_spawn_step(
    step: dict[str, Any],
    pending_invokes: collections.deque[dict[str, Any]],
    spawns: dict[str, SpawnSpec],
) -> None:
    """Process one transcript JSONL step for `invoke_subagent` or `swarm` spawn metadata."""
    step_type = step.get("type", "")
    if step_type == "PLANNER_RESPONSE":
        for tc in step.get("tool_calls") or []:
            if tc.get("name") == "invoke_subagent":
                pending_invokes.append(tc.get("args") or {})
        return

    if step_type != "GENERIC":
        return

    content = str(step.get("content") or "")
    if "Created the following subagent" in content:
        tc_args = pending_invokes.popleft() if pending_invokes else {}
        scid = _extract_subagent_cid_from_generic(content)
        if scid:
            spawns[scid] = SpawnSpec(
                conversation_id=scid,
                role=_clean_arg_str(tc_args.get("Role"), "Subagent"),
                configured_model=_clean_arg_str(tc_args.get("Model"), "inherit"),
                type_name=_clean_arg_str(tc_args.get("TypeName"), "self"),
                order=len(spawns) + 1,
            )
    elif '"status":"added"' in content.replace(" ", ""):
        _record_swarm_add_from_generic(content, spawns)


def _extract_subagent_cid_from_generic(content: str) -> str:
    """Extract `conversationId` from a `Created the following subagent` GENERIC step."""
    start = content.find("{")
    end = content.rfind("}") + 1
    if start != -1 and end > start:
        try:
            meta = json.loads(content[start:end])
            cid = str(meta.get("conversationId") or "")
            if cid:
                return cid
        except json.JSONDecodeError:
            pass
    m = UUID_RE.search(content)
    return m.group(1) if m else ""


def _record_swarm_add_from_generic(content: str, spawns: dict[str, SpawnSpec]) -> None:
    """Parse swarm `add` JSON responses (`{"status":"added","name":"...","model":"..."}`)."""
    start = content.find("{")
    end = content.rfind("}") + 1
    if start == -1 or end <= start:
        return
    try:
        payload = json.loads(content[start:end])
    except json.JSONDecodeError:
        return
    name = str(payload.get("name") or "")
    model = str(payload.get("model") or "inherit")
    if name:
        spawns[f"swarm:{name}"] = SpawnSpec(
            conversation_id=f"swarm:{name}",
            role=f"Swarm Worker (@{name})",
            configured_model=model,
            type_name="swarm",
            order=len(spawns) + 1,
        )


def inspect_transcript_tail(transcript_path: Path) -> tuple[str, bool, bool, int]:
    """Return `(latest_activity, has_send_message, last_step_error, line_count)` from a transcript."""
    if not transcript_path.is_file():
        return ("No transcript yet", False, False, 0)

    try:
        lines = [ln for ln in transcript_path.read_text(encoding="utf-8", errors="replace").splitlines() if ln.strip()]
    except OSError:
        return ("Unreadable transcript", False, False, 0)

    if not lines:
        return ("Starting...", False, False, 0)

    has_send_msg = False
    latest_desc = ""
    last_error = False

    try:
        last_obj = json.loads(lines[-1])
        last_error = last_obj.get("status") == "ERROR"
        step_idx = last_obj.get("step_index", len(lines) - 1)
        step_type = str(last_obj.get("type") or "STEP")
        latest_desc = f"Step {step_idx}: {step_type}"
    except json.JSONDecodeError:
        latest_desc = f"Step {len(lines)}"

    for raw_line in reversed(lines[-8:]):
        try:
            obj = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        tcs = obj.get("tool_calls") or []
        for tc in tcs:
            name = str(tc.get("name") or "")
            if name == "send_message":
                has_send_msg = True
            if name and (not latest_desc or latest_desc.endswith(("PLANNER_RESPONSE", "GENERIC"))):
                summary = _summarize_tool_call(name, tc.get("args") or {})
                step_idx = obj.get("step_index", len(lines) - 1)
                latest_desc = f"Step {step_idx} • {summary}"
                break

    return (latest_desc, has_send_msg, last_error, len(lines))


def _summarize_tool_call(name: str, args: dict[str, Any]) -> str:
    """Build a short human-readable summary of a tool call."""
    if name == "run_command":
        summary = _clean_arg_str(args.get("toolSummary") or args.get("CommandLine"))
        return f"run_command: {summary[:42]}" if summary else "run_command"
    if name in ("read_file", "write_file", "edit_file"):
        path = _clean_arg_str(args.get("Path"))
        short = Path(path).name if path else ""
        return f"{name}: {short}" if short else name
    if name == "send_message":
        return "send_message → reported back"
    if name == "invoke_subagent":
        role = _clean_arg_str(args.get("Role"), "subagent")
        return f"invoke_subagent: {role}"
    return name


def classify_status(
    db_status: str,
    not_fully_idle: bool,
    killed: bool,
    has_send_msg: bool,
    last_error: bool,
) -> str:
    """Classify a conversation or subagent into an authoritative status string."""
    if killed:
        return "KILLED"
    if db_status == "CASCADE_RUN_STATUS_RUNNING" or not_fully_idle:
        return "RUNNING"
    if last_error:
        return "ERROR"
    if has_send_msg:
        return "COMPLETED"
    if db_status == "CASCADE_RUN_STATUS_IDLE":
        return "IDLE"
    return "RUNNING" if not db_status else db_status.removeprefix("CASCADE_RUN_STATUS_")


def resolve_target_conversation(
    app_dir: Path,
    query: str | None,
    latest_with_subagents: bool = False,
) -> tuple[str | None, str]:
    """Resolve a conversation ID from an optional ID/prefix or pick the latest active one."""
    summaries_db = app_dir / "conversation_summaries.db"
    conv_dir = app_dir / "conversations"

    if query:
        q = query.strip()
        return _resolve_by_prefix(summaries_db, conv_dir, q)

    if summaries_db.is_file():
        cid, hint = _resolve_latest_from_db(summaries_db, latest_with_subagents)
        if cid:
            return cid, hint

    if conv_dir.is_dir():
        dbs = sorted(conv_dir.glob("*.db"), key=lambda p: p.stat().st_mtime, reverse=True)
        if dbs:
            return dbs[0].stem, ""

    return None, ""


def _resolve_by_prefix(summaries_db: Path, conv_dir: Path, prefix: str) -> tuple[str | None, str]:
    """Match an exact or prefix conversation UUID in `conversation_summaries.db` or `conversations/*.db`."""
    if summaries_db.is_file():
        try:
            conn = _connect_ro(summaries_db)
            cur = conn.cursor()
            cur.execute(
                "SELECT conversation_id FROM conversation_summaries WHERE conversation_id LIKE ? ORDER BY last_modified_time DESC LIMIT 5;",
                (f"{prefix}%",),
            )
            rows = [str(r[0]) for r in cur.fetchall() if r and r[0]]
            conn.close()
            if rows:
                for r in rows:
                    if r == prefix:
                        return r, ""
                return rows[0], ""
        except sqlite3.Error:
            pass

    if conv_dir.is_dir():
        matches = sorted(conv_dir.glob(f"{prefix}*.db"), key=lambda p: p.stat().st_mtime, reverse=True)
        if matches:
            return matches[0].stem, ""

    return (prefix, "") if UUID_RE.fullmatch(prefix) else (None, "")


def _resolve_latest_from_db(summaries_db: Path, latest_with_subagents: bool) -> tuple[str | None, str]:
    """Pick the most recent root conversation (or most recent root with subagents)."""
    try:
        conn = _connect_ro(summaries_db)
        cur = conn.cursor()
        cur.execute(
            """
            SELECT p.conversation_id
            FROM conversation_summaries p
            WHERE p.parent_conversation_id = ''
              AND EXISTS (
                  SELECT 1 FROM conversation_summaries c
                  WHERE c.parent_conversation_id = p.conversation_id
              )
            ORDER BY p.last_modified_time DESC
            LIMIT 1;
            """
        )
        sub_row = cur.fetchone()
        latest_with_sub_id = str(sub_row[0]) if sub_row and sub_row[0] else ""

        if latest_with_subagents and latest_with_sub_id:
            conn.close()
            return latest_with_sub_id, ""

        cur.execute(
            """
            SELECT conversation_id FROM conversation_summaries
            WHERE parent_conversation_id = ''
            ORDER BY last_modified_time DESC
            LIMIT 1;
            """
        )
        root_row = cur.fetchone()
        conn.close()
        latest_root = str(root_row[0]) if root_row and root_row[0] else ""
        hint = latest_with_sub_id if (latest_root and latest_with_sub_id and latest_root != latest_with_sub_id) else ""
        return (latest_root or None), hint
    except sqlite3.Error:
        return None, ""


def _fetch_summary_row(summaries_db: Path, cid: str) -> dict[str, Any] | None:
    """Fetch a single row from `conversation_summaries` by `conversation_id`."""
    if not summaries_db.is_file():
        return None
    try:
        conn = _connect_ro(summaries_db)
        cur = conn.cursor()
        cur.execute(
            """
            SELECT conversation_id, title, step_count, last_modified_time,
                   status, agent_name, parent_conversation_id, nesting_depth,
                   not_fully_idle, killed
            FROM conversation_summaries
            WHERE conversation_id = ?;
            """,
            (cid,),
        )
        row = cur.fetchone()
        conn.close()
        if not row:
            return None
        return {
            "conversation_id": str(row[0] or ""),
            "title": str(row[1] or ""),
            "step_count": int(row[2] or 0),
            "last_modified_time": str(row[3] or ""),
            "status": str(row[4] or ""),
            "agent_name": str(row[5] or ""),
            "parent_conversation_id": str(row[6] or ""),
            "nesting_depth": int(row[7] or 0),
            "not_fully_idle": bool(row[8]),
            "killed": bool(row[9]),
        }
    except sqlite3.Error:
        return None


def _fetch_descendant_rows(summaries_db: Path, root_cid: str) -> list[dict[str, Any]]:
    """Fetch all direct and nested child subagents for `root_cid` via a recursive CTE."""
    if not summaries_db.is_file():
        return []
    try:
        conn = _connect_ro(summaries_db)
        cur = conn.cursor()
        cur.execute(
            """
            WITH RECURSIVE descendants AS (
                SELECT conversation_id, title, step_count, last_modified_time,
                       status, agent_name, parent_conversation_id, nesting_depth,
                       not_fully_idle, killed
                FROM conversation_summaries
                WHERE parent_conversation_id = ?
                UNION ALL
                SELECT c.conversation_id, c.title, c.step_count, c.last_modified_time,
                       c.status, c.agent_name, c.parent_conversation_id, c.nesting_depth,
                       c.not_fully_idle, c.killed
                FROM conversation_summaries c
                JOIN descendants d ON c.parent_conversation_id = d.conversation_id
            )
            SELECT conversation_id, title, step_count, last_modified_time,
                   status, agent_name, parent_conversation_id, nesting_depth,
                   not_fully_idle, killed
            FROM descendants
            ORDER BY nesting_depth ASC, last_modified_time ASC;
            """,
            (root_cid,),
        )
        rows = cur.fetchall()
        conn.close()
    except sqlite3.Error:
        return []

    return [
        {
            "conversation_id": str(r[0] or ""),
            "title": str(r[1] or ""),
            "step_count": int(r[2] or 0),
            "last_modified_time": str(r[3] or ""),
            "status": str(r[4] or ""),
            "agent_name": str(r[5] or ""),
            "parent_conversation_id": str(r[6] or ""),
            "nesting_depth": int(r[7] or 1),
            "not_fully_idle": bool(r[8]),
            "killed": bool(r[9]),
        }
        for r in rows
    ]


def build_inspection_result(
    app_dir: Path,
    cid: str,
    latest_with_subagents_hint: str = "",
) -> InspectionResult:
    """Inspect `cid` (either a parent conversation or a subagent) and return structured data."""
    summaries_db = app_dir / "conversation_summaries.db"
    conv_db = app_dir / "conversations" / f"{cid}.db"
    transcript = app_dir / "brain" / cid / ".system_generated" / "logs" / "transcript.jsonl"

    summary_row = _fetch_summary_row(summaries_db, cid)
    rt_meta = extract_runtime_metadata(conv_db)
    latest_act, has_send, last_err, line_steps = inspect_transcript_tail(transcript)

    parent_id = (summary_row["parent_conversation_id"] if summary_row else "") or rt_meta.parent_id
    descendant_rows = _fetch_descendant_rows(summaries_db, cid)
    spawns = parse_parent_transcript_spawns(transcript)

    # A target is treated as a leaf subagent if it has a parent_id and has no children of its own.
    is_leaf_subagent = bool(parent_id) and not descendant_rows and not [
        k for k in spawns if not k.startswith("swarm:")
    ]

    db_status = summary_row["status"] if summary_row else ""
    not_idle = bool(summary_row["not_fully_idle"]) if summary_row else False
    killed = bool(summary_row["killed"]) if summary_row else False
    steps = (summary_row["step_count"] if summary_row else 0) or line_steps
    mtime = summary_row["last_modified_time"] if summary_row else ""
    title = summary_row["title"] if summary_row else ""

    result = InspectionResult(
        target_id=cid,
        title=title,
        is_subagent=is_leaf_subagent,
        parent_id=parent_id,
        root_id=rt_meta.root_id or parent_id,
        status=classify_status(db_status, not_idle, killed, has_send, last_err),
        step_count=steps,
        last_modified_time=mtime,
        runtime_model_id=rt_meta.model_id,
        runtime_model_label=rt_meta.model_label,
        latest_activity=latest_act,
        latest_with_subagents_hint=latest_with_subagents_hint,
    )

    if is_leaf_subagent:
        return result

    result.subagents = _merge_subagents(app_dir, cid, descendant_rows, spawns)
    return result


def _merge_subagents(
    app_dir: Path,
    root_cid: str,
    descendant_rows: list[dict[str, Any]],
    root_spawns: dict[str, SpawnSpec],
) -> list[SubagentRecord]:
    """Combine DB descendant rows and transcript spawn definitions into ordered `SubagentRecord`s."""
    spawns_by_id: dict[str, SpawnSpec] = dict(root_spawns)
    records_by_id: dict[str, SubagentRecord] = {}

    for idx, row in enumerate(descendant_rows, start=1):
        scid = row["conversation_id"]
        parent_cid = row["parent_conversation_id"]
        if parent_cid and parent_cid != root_cid:
            parent_tx = app_dir / "brain" / parent_cid / ".system_generated" / "logs" / "transcript.jsonl"
            for k, v in parse_parent_transcript_spawns(parent_tx).items():
                spawns_by_id.setdefault(k, v)

        records_by_id[scid] = _build_subagent_record(app_dir, row, spawns_by_id, idx)

    # Also include any subagents found in the parent transcript that aren't in conversation_summaries.db yet
    for scid in spawns_by_id:
        if scid.startswith("swarm:") or scid in records_by_id:
            continue
        synthetic_row = {
            "conversation_id": scid,
            "title": "",
            "step_count": 0,
            "last_modified_time": "",
            "status": "",
            "agent_name": "",
            "parent_conversation_id": root_cid,
            "nesting_depth": 1,
            "not_fully_idle": False,
            "killed": False,
        }
        records_by_id[scid] = _build_subagent_record(
            app_dir, synthetic_row, spawns_by_id, len(records_by_id) + 1
        )

    return sorted(records_by_id.values(), key=lambda r: (r.order, r.nesting_depth))


def _build_subagent_record(
    app_dir: Path,
    row: dict[str, Any],
    spawns_by_id: dict[str, SpawnSpec],
    default_order: int,
) -> SubagentRecord:
    """Construct a `SubagentRecord` for a single child subagent or swarm worker."""
    scid = row["conversation_id"]
    agent_name = row["agent_name"]
    spec = spawns_by_id.get(scid) or (spawns_by_id.get(f"swarm:{agent_name}") if agent_name else None)

    sub_db = app_dir / "conversations" / f"{scid}.db"
    sub_tx = app_dir / "brain" / scid / ".system_generated" / "logs" / "transcript.jsonl"

    rt = extract_runtime_metadata(sub_db)
    latest_act, has_send, last_err, tx_steps = inspect_transcript_tail(sub_tx)

    role = (
        spec.role
        if spec
        else (f"Swarm Worker (@{agent_name})" if agent_name else (row["title"] or "Subagent"))
    )
    type_name = (
        spec.type_name
        if spec
        else (rt.subagent_type or ("swarm" if agent_name else "self"))
    )
    cfg_model = spec.configured_model if spec else "inherit"
    steps = max(int(row["step_count"] or 0), tx_steps)
    mtime = str(row["last_modified_time"] or "")
    if (not mtime or mtime.startswith("0001-")) and sub_tx.is_file():
        mtime = datetime.datetime.fromtimestamp(
            sub_tx.stat().st_mtime, tz=datetime.timezone.utc
        ).isoformat()
    status = classify_status(
        row["status"],
        row["not_fully_idle"],
        row["killed"],
        has_send,
        last_err,
    )

    return SubagentRecord(
        conversation_id=scid,
        parent_id=row["parent_conversation_id"],
        nesting_depth=max(1, int(row["nesting_depth"] or 1)),
        role=role,
        type_name=type_name,
        configured_model=cfg_model,
        runtime_model_id=rt.model_id,
        runtime_model_label=rt.model_label,
        status=status,
        step_count=steps,
        last_modified_time=mtime,
        latest_activity=latest_act,
        killed=row["killed"],
        order=spec.order if (spec and spec.order) else default_order + 100,
    )


def format_relative_age(iso_ts: str) -> str:
    """Format an ISO-8601 UTC timestamp (`2026-04-19T19:13:04.228945Z`) as a compact relative age."""
    if not iso_ts or iso_ts.startswith("0001-"):
        return ""
    cleaned = re.sub(r"\.(\d{6})\d+", r".\1", iso_ts.strip()).replace("Z", "+00:00")
    try:
        dt = datetime.datetime.fromisoformat(cleaned)
    except ValueError:
        return iso_ts[:19].replace("T", " ")

    if dt.year < 2020:
        return ""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    now = datetime.datetime.now(datetime.timezone.utc)
    delta_s = max(0, int((now - dt).total_seconds()))

    for threshold, divisor, unit in ((60, 1, "s"), (3600, 60, "m"), (86400, 3600, "h")):
        if delta_s < threshold:
            return f"{delta_s // divisor}{unit} ago"
    return f"{delta_s // 86400}d ago"


def _status_badge(status: str, color: bool) -> str:
    """Return a status badge with emoji and optional ANSI color."""
    badges = {
        "RUNNING": ("🟢 RUNNING", C_GREEN),
        "COMPLETED": ("✅ COMPLETED", C_BLUE),
        "KILLED": ("🛑 KILLED", C_RED),
        "ERROR": ("❌ ERROR", C_RED),
        "IDLE": ("⏸️ IDLE", C_YELLOW),
    }
    label, ansi = badges.get(status, (f"⚪ {status}", C_DIM))
    return f"{ansi}{label}{C_RST}" if color else label


def _format_model_display(runtime_label: str, runtime_id: str, configured: str = "") -> str:
    """Format runtime + configured model info clearly."""
    if runtime_label and runtime_id:
        base = f"{runtime_label} [{runtime_id}]"
    elif runtime_id:
        base = runtime_id
    elif runtime_label:
        base = runtime_label
    else:
        base = configured or "unknown"

    if configured and configured != runtime_id:
        return f"{base} (configured: {configured})"
    return base


def render_human_report(res: InspectionResult, color: bool = True) -> str:
    """Render an `InspectionResult` as a human-friendly terminal report."""
    m = C_MAUVE if color else ""
    b = C_BOLD if color else ""
    d = C_DIM if color else ""
    t = C_TEAL if color else ""
    r = C_RST if color else ""

    lines: list[str] = []
    if res.is_subagent:
        lines.append(f"\n🔍 {m}[Target is a Subagent: {res.target_id}]{r}")
        lines.append(f"  Parent Conversation: {b}{res.parent_id or 'Unknown'}{r}")
        if res.root_id and res.root_id != res.parent_id:
            lines.append(f"  Root Conversation:   {res.root_id}")
        lines.append(f"  Runtime Model:       {t}{_format_model_display(res.runtime_model_label, res.runtime_model_id)}{r}")
        lines.append(f"  Status:              {_status_badge(res.status, color)} ({res.step_count} steps)")
        lines.append(f"  Current Activity:    {res.latest_activity}")
        lines.append("=" * 72 + "\n")
        return "\n".join(lines)

    title_sfx = f" — {res.title}" if res.title else ""
    lines.append(f"\n🤖 {m}[Subagents for Conversation: {res.target_id}{title_sfx}]{r}")
    root_model = _format_model_display(res.runtime_model_label, res.runtime_model_id)
    if root_model != "unknown":
        lines.append(f"  Root Model:  {t}{root_model}{r}  •  {res.step_count} steps")

    if not res.subagents:
        lines.append("  No subagents have been launched by this conversation.")
        if res.latest_with_subagents_hint:
            lines.append(
                f"  {d}Tip: Most recent conversation with subagents is {res.latest_with_subagents_hint[:8]}"
                f" (run `check-subagents -s`){r}"
            )
        lines.append("=" * 72 + "\n")
        return "\n".join(lines)

    counts = collections.Counter(s.status for s in res.subagents)
    summary_parts = [f"{len(res.subagents)} total"]
    summary_parts.extend(
        f"{counts[key]} {key.lower()}"
        for key in ("RUNNING", "COMPLETED", "IDLE", "KILLED", "ERROR")
        if counts[key]
    )
    lines.append(f"  Summary:     {', '.join(summary_parts)}")

    for idx, sub in enumerate(res.subagents, start=1):
        indent = "  " + ("  " * max(0, sub.nesting_depth - 1))
        tree_prefix = "↳ " if sub.nesting_depth > 1 else ""
        age = format_relative_age(sub.last_modified_time)
        age_sfx = f"  •  active {age}" if age else ""
        model_str = _format_model_display(sub.runtime_model_label, sub.runtime_model_id, sub.configured_model)

        lines.append(f"\n{indent}{tree_prefix}{b}#{idx}  {sub.role}{r} {d}({sub.type_name}){r}")
        lines.append(f"{indent}  Status:       {_status_badge(sub.status, color)}  •  {sub.step_count} steps{age_sfx}")
        lines.append(f"{indent}  Model:        {t}{model_str}{r}")
        lines.append(f"{indent}  Activity:     {sub.latest_activity}")
        lines.append(f"{indent}  Subagent ID:  {d}{sub.conversation_id}{r}")
        lines.append(f"{indent}  " + "-" * 64)

    lines.append("=" * 72 + "\n")
    return "\n".join(lines)


def _result_to_dict(res: InspectionResult) -> dict[str, Any]:
    """Serialize `InspectionResult` to a JSON-compatible dictionary."""
    return {
        "target_id": res.target_id,
        "title": res.title,
        "is_subagent": res.is_subagent,
        "parent_id": res.parent_id,
        "root_id": res.root_id,
        "status": res.status,
        "step_count": res.step_count,
        "last_modified_time": res.last_modified_time,
        "runtime_model_id": res.runtime_model_id,
        "runtime_model_label": res.runtime_model_label,
        "latest_activity": res.latest_activity,
        "subagents": [
            {
                "conversation_id": s.conversation_id,
                "parent_id": s.parent_id,
                "nesting_depth": s.nesting_depth,
                "role": s.role,
                "type_name": s.type_name,
                "configured_model": s.configured_model,
                "runtime_model_id": s.runtime_model_id,
                "runtime_model_label": s.runtime_model_label,
                "status": s.status,
                "step_count": s.step_count,
                "last_modified_time": s.last_modified_time,
                "latest_activity": s.latest_activity,
                "killed": s.killed,
            }
            for s in res.subagents
        ],
    }


def build_parser() -> argparse.ArgumentParser:
    """Create the CLI argument parser for `check-subagents`."""
    parser = argparse.ArgumentParser(
        prog="check-subagents",
        description="Inspect Antigravity active conversations, spawned subagents, models, and live status.",
    )
    parser.add_argument(
        "conversation_id",
        nargs="?",
        default=None,
        help="Optional conversation or subagent UUID (full ID or prefix)",
    )
    parser.add_argument(
        "-s",
        "--latest-with-subagents",
        action="store_true",
        help="Inspect the most recently active root conversation that has subagents",
    )
    parser.add_argument(
        "-w",
        "--watch",
        nargs="?",
        const=2.0,
        type=float,
        metavar="SEC",
        help="Refresh live status every SEC seconds (default: 2.0)",
    )
    parser.add_argument(
        "-j",
        "--json",
        action="store_true",
        help="Emit machine-readable JSON output",
    )
    parser.add_argument(
        "--app-dir",
        default=os.environ.get("AGY_APP_DIR", str(Path("~/.gemini/antigravity").expanduser())),
        help=argparse.SUPPRESS,
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """Run the `check-subagents` CLI entrypoint."""
    parser = build_parser()
    args = parser.parse_args(argv)
    app_dir = Path(args.app_dir).expanduser()

    cid, hint = resolve_target_conversation(
        app_dir,
        args.conversation_id,
        latest_with_subagents=args.latest_with_subagents,
    )
    if not cid:
        print("Error: Could not identify an active Antigravity conversation.", file=sys.stderr)
        return 1

    use_color = sys.stdout.isatty() and not os.environ.get("NO_COLOR")

    if args.watch and not args.json:
        interval = max(0.5, float(args.watch))
        try:
            while True:
                res = build_inspection_result(app_dir, cid, hint)
                sys.stdout.write("\033[2J\033[H" + render_human_report(res, color=use_color))
                sys.stdout.flush()
                time.sleep(interval)
        except KeyboardInterrupt:
            return 0

    res = build_inspection_result(app_dir, cid, hint)
    if args.json:
        print(json.dumps(_result_to_dict(res), indent=2))
    else:
        print(render_human_report(res, color=use_color), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
