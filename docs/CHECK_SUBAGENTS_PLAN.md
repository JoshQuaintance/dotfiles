# Phase 1 Plan: `check-subagents` CLI Utility

## Goal Description
Build and link `check-subagents` as a first-class dotfiles CLI utility to inspect Antigravity subagents and native swarm workers for the latest (or any specified) conversation — fixing **7 real schema/transcript bugs** discovered by inspecting `~/.gemini/antigravity/` on this machine.

Per your request, **Phase 2 (`list-conversations`) is intentionally deferred** until `check-subagents` is confirmed, implemented, and verified so we can plan `list-conversations` with its own dedicated requirements.

---

## Key Improvements Over the Initial Draft (Grounded in Live `~/.gemini/antigravity` Data)

1. **Fixes Parallel `invoke_subagent` Drop Bug (8-way fan-out in one step)**
   - *Draft bug:* Stored `last_tc` in a single scalar variable. When a `PLANNER_RESPONSE` emits multiple parallel `invoke_subagent` calls in one step (e.g., 8 parallel `research` subagents in steps `35 -> 36..43`), 7 of the 8 subagents were silently lost.
   - *Improvement:* Match `invoke_subagent` calls via a FIFO queue **and** merge with `conversation_summaries.db` ground-truth child records so zero subagents are ever dropped.

2. **Detects Native `swarm` Workers & Multi-Level Nested Subagent Trees**
   - *Draft bug:* Only scanned `invoke_subagent` in `transcript.jsonl`, completely missing `/swarm` workers (`apispec`, `backend`, `verifier`, `monitor`) and nested descendants (`nesting_depth` 2–3 under `teamwork_preview`).
   - *Improvement:* Use a recursive SQLite CTE (`WITH RECURSIVE descendants AS (...)`) on `conversation_summaries.parent_conversation_id` as the primary discovery backbone, enriched with Role, TypeName, and Swarm metadata from parent transcripts, rendered with tree indentation for nested subagents.

3. **Accurate Runtime Model Resolution (Fixes Tool-Schema False Match & Resolves `inherit`)**
   - *Draft bug:* `re.search(r"(gemini-...|claude-...)", txt)` from byte 0 of `gen_metadata` matched `'gemini-3.5-flash-lite'` inside the embedded `invoke_subagent` tool schema description rather than the actual model used! Also, parent transcripts usually record `Model: "inherit"`, hiding what model actually ran.
   - *Improvement:* Parse the **tail** of the latest `gen_metadata` protobuf record (after the final `sessionID` marker) in `conversations/<subagent_id>.db` to extract both the **human-readable model** (e.g., `Gemini 4 Carbon (Medium)`) and **canonical model ID** (e.g., `gemini-4-carbon`, `gemini-3.8-flash-tiered`, `claude-...`), alongside configured policy (`inherit`, `flash`, pinned swarm model).

4. **True Live Lifecycle Status (No False `🟢 RUNNING` Zombies)**
   - *Draft bug:* Defaulted every subagent to `RUNNING` unless `send_message` appeared in its last 5 transcript lines — falsely marking killed workers, sleeping swarm workers, and server-restarted/interrupted agents as `🟢 RUNNING`.
   - *Improvement:* Combine `conversation_summaries` (`status`, `not_fully_idle`, `killed`, `step_count`, `last_modified_time`) with `transcript.jsonl`:
     - `🟢 RUNNING` — `status == 'CASCADE_RUN_STATUS_RUNNING'` or `not_fully_idle == 1`
     - `✅ COMPLETED` — Idle and delivered final `send_message` report to parent
     - `🛑 KILLED` — `killed == 1` (terminated via `manage_subagents` or `swarm kill`)
     - `⏸️ IDLE / STOPPED` — `CASCADE_RUN_STATUS_IDLE` without `send_message` (sleeping swarm worker or stopped on restart)
     - `❌ ERROR` — Latest step `status == 'ERROR'` or stream error in metadata

5. **Rich Activity Preview & Elapsed / Relative Timing**
   - Instead of raw `Step 3: GENERIC`, show total step count, relative last-active age (e.g., `12s ago`, `4m ago`), and the latest tool action/summary (e.g., `Step 81 • run_command: "Verify clean worktree"`).

6. **Ergonomic CLI Flags (`argparse`)**
   - `check-subagents` — Inspect the most recently active root conversation (with fallback if the latest root conversation has 0 subagents: optionally hint or pass `--latest-with-subagents` / `-s`).
   - `check-subagents <id-or-prefix>` — Supports **short UUID prefixes** (e.g. `check-subagents 3e9b6d` or `check-subagents 76448c`) for both parent conversations and individual subagents!
   - `check-subagents -w [sec]`, `--watch [sec]` — Live-refreshing TUI dashboard (default `2s` interval) while subagents are running in the background.
   - `check-subagents -j`, `--json` — Structured JSON output (consistent with `dot status --json` / `dot doctor --json`).
   - `check-subagents -h`, `--help` — Clean exit-0 usage help.

7. **Read-Only SQLite URI Connections (`?mode=ro`)**
   - Connects via `sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=2.0)` so inspecting live conversations never locks or contends with Antigravity's active WAL writers.

---

## Dotfiles Architecture & Integration

Following our established `~/.dotfiles` layout so every linter, typechecker, doc generator, and palette picker works automatically:

### Proposed Changes

#### [NEW] `libexec/check_subagents.py`
- Full Python 3 implementation (`chmod +x`, stdlib-only: `argparse`, `collections`, `datetime`, `json`, `os`, ` pathlib`, `re`, `sqlite3`, `sys`, `time`) with complete type annotations so `ruff` and `mypy` (`lefthook` `pre-commit`) check it automatically.
- Modular, testable functions (all compliant with Ruff complexity/argument rules):
  - `resolve_conversation_id( summaries_db, conv_dir, prefix_or_none, latest_with_subs )`
  - `extract_runtime_model_and_parent( conv_db_path )`
  - `parse_parent_transcript_spawns( transcript_path )` (handles queued parallel `invoke_subagent` + `swarm` `add` calls)
  - `fetch_descendant_tree( summaries_db, root_cid )` (recursive CTE + fallback to transcript if DB row absent)
  - `classify_subagent_status( db_row, transcript_path )`
  - `render_report( target_info, subagents )` (Catppuccin Mocha ANSI styling when stdout is a TTY, plain text when piped)

#### [NEW] `bin/check-subagents`
- Executable POSIX wrapper (`chmod +x`) with `# Description:` header so `,check-subagents` (in `,`), `fa`, and `docs/COMMANDS.md` (`libexec/gen_docs.py`) register it automatically:
```sh
#!/bin/sh
# Description: Inspect Antigravity conversations, subagents, models, and live status
SOURCE="$0"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  case "$SOURCE" in /*) ;; *) SOURCE="$DIR/$SOURCE" ;; esac
done
DOTFILES_DIR="$(cd -P "$(dirname "$SOURCE")/.." >/dev/null 2>&1 && pwd)"
exec python3 "$DOTFILES_DIR/libexec/check_subagents.py" "$@"
```

#### [SYMLINK] `~/.local/bin/check-subagents` -> `~/.dotfiles/bin/check-subagents`
- Symlinked into `~/.local/bin/check-subagents` (which is already on `$PATH` in `zsh/.zshrc` and `cli/manifest.py`), and `install/install-cli.sh` already auto-symlinks every executable in `$DOTFILES_DIR/bin/*` to `~/.local/bin/` on fresh installs. (We will also ensure any missing `bin/*` symlink like `testdiff` is linked in `~/.local/bin/`.)

#### [MODIFY] `tests/test_libexec.py` & `docs/COMMANDS.md`
- Add unit tests in `tests/test_libexec.py` using temporary SQLite DBs + fixture `transcript.jsonl` files covering:
  1. Multi-way parallel `invoke_subagent` calls in a single step
  2. Native `swarm` workers + nested subagents
  3. Tail-anchored `gen_metadata` model extraction (verifying tool-schema model names earlier in the blob are ignored)
  4. Status classification (`RUNNING`, `COMPLETED`, `KILLED`, `IDLE`) and UUID prefix resolution
- Regenerate `docs/COMMANDS.md` via `python3 libexec/gen_docs.py`.

---

## Sample Output Preview

```text
╭──────────────────────────────────────────────────────────────────────╮
│  Antigravity Subagents — SALES-3884 PR Review (3e9b6d0c-2fc3-...)    │
╰──────────────────────────────────────────────────────────────────────╯
  Root Model:   Gemini 4 Carbon (Medium) [gemini-4-carbon]
  Summary:      9 total (8 running, 1 completed, 0 killed)

  #1  Codebase Context Builder (self)
      Status:   ✅ COMPLETED  •  86 steps  •  active 4m ago
      Model:    Gemini 3.8 Flash [gemini-3.8-flash-tiered] (configured: inherit)
      Latest:   Step 84 • send_message → parent
      ID:       73678252-7fef-4056-9221-3e277df65363

  #2  Functionality & Regressions Reviewer (research)
      Status:   🟢 RUNNING    •  14 steps  •  active 2s ago
      Model:    Gemini 3.8 Flash [gemini-3.8-flash-tiered] (configured: inherit)
      Latest:   Step 14 • read_file: projects/sales-ui/src/app/...
      ID:       b8df4ed9-b528-4ed3-bd53-343e7d393257
```

---

## Open Questions to Confirm Before Implementing `check-subagents`

> [!IMPORTANT]
> 1. **Default target when called with no arguments (`check-subagents`)**: Should it inspect the **most recently modified root conversation** (even if it has 0 subagents), OR default to the **most recently active conversation that has subagents** (with `-l` / `--latest` to force the absolute latest conversation)?
> 2. **Watch mode (`-w` / `--watch`) & `--json`**: Include both `-w [seconds]` live polling and `-j` / `--json` output in `check-subagents`?
> 3. **Short alias**: Would you also like a short alias in `.aliases` (e.g. `agysub` or `subagents`), or keep it strictly as `check-subagents` (and `,check-subagents` via `,`)?

## Verification Plan
1. `lefthook run pre-commit --all-files` (Ruff, mypy, shellcheck, shfmt, zsh-syntax, typos, actionlint)
2. `python3 -m unittest discover -s tests -v`
3. `./bin/dot test`
4. Live verification in terminal:
   - `check-subagents --help`
   - `check-subagents` (on live Antigravity data)
   - `check-subagents 3e9b6d` (prefix lookup on 8-subagent parallel conversation)
   - `check-subagents f4b5ad` (swarm worker conversation)
   - `check-subagents 736782` (direct subagent target inspection)
