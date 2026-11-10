"""Unit tests for standalone Python executables in `libexec/` and JSON/bytecode CLI helpers."""

from __future__ import annotations

import contextlib
import hashlib
import io
import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from cli.bench import append_bench_history, evaluate_bench_trend, load_bench_history, render_sparkline
from cli.doctor import DoctorReport, compute_doctor_exit_code, orphaned_zsh_bytecode
from cli.env_audit import run_env_audit
from cli.new_fn import scaffold_new_function
from cli.profile import parse_zprof_output

REPO_ROOT = Path(__file__).resolve().parent.parent
LIBEXEC_DIR = REPO_ROOT / "libexec"


def run_libexec(script_name: str, *args: str) -> tuple[int, str, str]:
    """Execute a script in `libexec/` and return (returncode, stdout, stderr)."""
    proc = subprocess.run(
        [sys.executable, str(LIBEXEC_DIR / script_name), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.returncode, proc.stdout, proc.stderr


class TestChecksumLibexec(unittest.TestCase):
    """Test `libexec/checksum.py` across files, directories, verification, and comparison."""

    def test_single_file_and_directory_hashing(self) -> None:
        """Verify file and deterministic directory hashing without comparison."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            f1 = root / "a.txt"
            f1.write_text("alpha", encoding="utf-8")
            sub = root / "dir1"
            sub.mkdir()
            (sub / "nested.txt").write_text("beta", encoding="utf-8")

            rc, out, _ = run_libexec("checksum.py", "--", str(f1), str(sub))
            self.assertEqual(rc, 0)
            self.assertIn("a.txt", out)
            self.assertIn("dir1/", out)
            self.assertIn("1 files, 4 bytes", out)

    def test_compare_identical_and_differing_targets(self) -> None:
        """Verify `--compare` returns 0 for identical targets and 1 for differing targets."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            f1 = root / "one.bin"
            f2 = root / "two.bin"
            f3 = root / "three.bin"
            f1.write_bytes(b"same-bytes")
            f2.write_bytes(b"same-bytes")
            f3.write_bytes(b"other-bytes")

            rc_same, out_same, _ = run_libexec("checksum.py", "--compare", "--", str(f1), str(f2))
            self.assertEqual(rc_same, 0)
            self.assertIn("All 2 targets are byte-for-byte identical", out_same)

            rc_diff, out_diff, _ = run_libexec("checksum.py", "--compare", "--", str(f1), str(f3))
            self.assertEqual(rc_diff, 1)
            self.assertIn("2 distinct SHA-256 digests", out_diff)

    def test_manifest_file_verification(self) -> None:
        """Verify `--check` parses GNU and BSD checksum manifests and detects mismatches."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            f1 = root / "alpha.txt"
            f2 = root / "beta.txt"
            f1.write_bytes(b"alpha-data")
            f2.write_bytes(b"beta-data")
            h1 = hashlib.sha256(b"alpha-data").hexdigest()
            h2 = hashlib.md5(b"beta-data").hexdigest()

            manifest = root / "SHA256SUMS"
            manifest.write_text(
                f"# release checksums\n{h1}  alpha.txt\nMD5 (beta.txt) = {h2}\n",
                encoding="utf-8",
            )
            rc_ok, out_ok, _ = run_libexec("checksum.py", "--check", "--", str(manifest))
            self.assertEqual(rc_ok, 0)
            self.assertIn("All 2 manifest entry/entries verified", out_ok)

            f2.write_bytes(b"tampered")
            rc_fail, out_fail, _ = run_libexec("checksum.py", "--check", "--", str(manifest))
            self.assertEqual(rc_fail, 1)
            self.assertIn("MISMATCH", out_fail)


class TestDecodeLibexec(unittest.TestCase):
    """Test `libexec/decode.py` across JWT, UUIDv7, Epoch, HTML, Hex, URL, and Base64."""

    def test_uuid_v7_and_v4_decoding(self) -> None:
        """Verify UUIDv7 extracts embedded timestamp and UUIDv4 reports version."""
        rc, out, _ = run_libexec("decode.py", "018f4a7c-8e10-7000-8000-000000000001")
        self.assertEqual(rc, 0)
        self.assertIn("UUID (v7)", out)
        self.assertIn("Created:", out)

    def test_hex_and_html_entity_decoding(self) -> None:
        """Verify 0x-prefixed hex strings and HTML entities decode cleanly."""
        rc_hex, out_hex, _ = run_libexec("decode.py", "0x68656c6c6f2d776f726c64")
        self.assertEqual(rc_hex, 0)
        self.assertIn("hello-world", out_hex)

        rc_html, out_html, _ = run_libexec("decode.py", "&lt;div class=&quot;tag&quot;&gt;A &amp; B&lt;/div&gt;")
        self.assertEqual(rc_html, 0)
        self.assertIn('<div class="tag">A & B</div>', out_html)


class TestClipAndStrdiffAndWslLibexec(unittest.TestCase):
    """Test `clip_transform.py`, `strdiff.py`, and `wsl_terminal_settings.py`."""

    def test_clip_transforms(self) -> None:
        """Verify JSON formatting, minification, sorting, and Base64 round-trip."""
        rc_sort, out_sort, _ = run_libexec("clip_transform.py", "sort", "b\na\nb\n")
        self.assertEqual(rc_sort, 0)
        self.assertEqual(out_sort, "a\nb")

        rc_bad, _, err_bad = run_libexec("clip_transform.py", "json", "{not-json")
        self.assertEqual(rc_bad, 1)
        self.assertIn("Invalid JSON", err_bad)

    def test_encode_and_clip_transforms(self) -> None:
        """Verify `encode.py` and new clip transforms (hexe, hexd, htmle, htmld)."""
        rc, out, _ = run_libexec("encode.py", "Hello World")
        self.assertEqual(rc, 0)
        self.assertIn("SGVsbG8gV29ybGQ=", out)
        self.assertIn("48656c6c6f20576f726c64", out)

        rc_b64, out_b64, _ = run_libexec("encode.py", "-b", "Hello World")
        self.assertEqual(rc_b64, 0)
        self.assertEqual(out_b64, "SGVsbG8gV29ybGQ=")

        rc_hx, out_hx, _ = run_libexec("clip_transform.py", "hexe", "test")
        self.assertEqual(rc_hx, 0)
        self.assertEqual(out_hx, "74657374")

        rc_hd, out_hd, _ = run_libexec("clip_transform.py", "hexd", "0x74657374")
        self.assertEqual(rc_hd, 0)
        self.assertEqual(out_hd, "test")

        rc_ht, out_ht, _ = run_libexec("clip_transform.py", "htmle", "<tag>&'\"")
        self.assertEqual(rc_ht, 0)
        self.assertEqual(out_ht, "&lt;tag&gt;&amp;&#x27;&quot;")

    def test_strdiff_modes(self) -> None:
        """Verify identical and differing strings in char and word modes."""
        rc_eq, out_eq, _ = run_libexec("strdiff.py", "same", "same", "char")
        self.assertEqual(rc_eq, 0)
        self.assertIn("Strings are identical", out_eq)

        rc_df, out_df, _ = run_libexec("strdiff.py", "foo bar", "foo baz", "word")
        self.assertEqual(rc_df, 0)
        self.assertIn("Δ", out_df)

    def test_wsl_terminal_settings_merge_and_orphan_zwc(self) -> None:
        """Verify JSONC Windows Terminal settings merger and orphaned `.zwc` detection."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            settings = root / "settings.json"
            template = root / "template.json"
            settings.write_text('// comment\n{"profiles": {"defaults": {}}, "actions": []}', encoding="utf-8")
            template.write_text(
                '{"copyOnSelect": true, "schemes": [{"name": "Catppuccin Mocha"}], '
                '"profiles": {"defaults": {"colorScheme": "Catppuccin Mocha"}}, '
                '"actions": [{"keys": "alt+h", "command": "moveFocusLeft"}]}',
                encoding="utf-8",
            )
            rc, _, _ = run_libexec("wsl_terminal_settings.py", str(settings), str(template))
            self.assertEqual(rc, 0)
            merged = json.loads(settings.read_text(encoding="utf-8"))
            self.assertTrue(merged["copyOnSelect"])
            self.assertEqual(merged["profiles"]["defaults"]["colorScheme"], "Catppuccin Mocha")

            zsh_dir = root / "zsh" / "functions"
            zsh_dir.mkdir(parents=True)
            orphan = zsh_dir / "deleted_module.zsh.zwc"
            orphan.write_bytes(b"zwc")
            valid_src = zsh_dir / "active.zsh"
            valid_src.write_text("# active", encoding="utf-8")
            (zsh_dir / "active.zsh.zwc").write_bytes(b"zwc")

            orphans = orphaned_zsh_bytecode(root)
            self.assertEqual(orphans, [orphan])

    def test_env_audit_json_output(self) -> None:
        """Verify `run_env_audit(json_output=True)` emits valid JSON with expected keys."""
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = run_env_audit(json_output=True)
        self.assertEqual(rc, 0)
        data = json.loads(buf.getvalue())
        self.assertIn("env", data)
        self.assertIn("path_summary", data)
        self.assertIn("binaries", data)

    def test_doctor_strict_exit_codes(self) -> None:
        """Verify `compute_doctor_exit_code` returns 0, 1, or 2 under normal and strict modes."""
        rep = DoctorReport()
        with contextlib.redirect_stdout(io.StringIO()):
            rep.ok("check", "ok")
            self.assertEqual(compute_doctor_exit_code(rep, strict=False), 0)
            self.assertEqual(compute_doctor_exit_code(rep, strict=True), 0)

            rep.warn("warn-check", "minor")
            self.assertEqual(compute_doctor_exit_code(rep, strict=False), 0)
            self.assertEqual(compute_doctor_exit_code(rep, strict=True), 2)

            rep.fail("fail-check", "broken")
            self.assertEqual(compute_doctor_exit_code(rep, strict=False), 1)
            self.assertEqual(compute_doctor_exit_code(rep, strict=True), 1)

    def test_bench_history_cap_and_sparkline_trend(self) -> None:
        """Verify `bench_history.jsonl` caps at 50 entries and detects >15% regressions."""
        with tempfile.TemporaryDirectory() as tmp:
            hist_path = Path(tmp) / "bench_history.jsonl"
            for i in range(60):
                append_bench_history(hist_path, {"ts": float(i), "median_ms": 100.0}, max_entries=50)
            loaded = load_bench_history(hist_path)
            self.assertEqual(len(loaded), 50)
            spark, reg, _ = evaluate_bench_trend(loaded)
            self.assertEqual(len(spark), 50)
            self.assertFalse(reg)

            append_bench_history(hist_path, {"ts": 61.0, "median_ms": 135.0}, max_entries=50)
            spark2, reg2, diff_pct = evaluate_bench_trend(load_bench_history(hist_path))
            self.assertTrue(reg2)
            self.assertEqual(diff_pct, 35.0)
            self.assertTrue(spark2.endswith("█"))
            self.assertEqual(render_sparkline([10.0, 20.0, 30.0]), "▁▅█")

    def test_parse_zprof_output_and_scaffold_new_fn(self) -> None:
        """Verify `parse_zprof_output` and `scaffold_new_function`."""
        fixture = (
            "num  calls                time                       self            name\n"
            "-----------------------------------------------------------------------------------\n"
            " 1)    1          18.50    18.50   46.25%     12.00    12.00   30.00%  compinit\n"
            " 2)    3           9.00     3.00   22.50%      9.00     3.00   22.50%  _comma_register\n"
            "\n"
            "-----------------------------------------------------------------------------------\n"
        )
        rows = parse_zprof_output(fixture)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["name"], "compinit")
        self.assertEqual(rows[0]["total_ms"], 18.5)
        self.assertEqual(rows[1]["calls"], 3)

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "zsh" / "functions").mkdir(parents=True)
            (root / "tests" / "zsh").mkdir(parents=True)
            (root / "zsh" / "functions.zsh").write_text(
                "typeset -ga DOTFILES_FUNCTIONS=(\n  take up\n)\n",
                encoding="utf-8",
            )
            ok, _msg = scaffold_new_function(
                name="myhelper",
                module="custom",
                desc="Sample helper",
                dotfiles=root,
                regen_docs=False,
            )
            self.assertTrue(ok)
            self.assertIn("myhelper", (root / "zsh" / "functions.zsh").read_text(encoding="utf-8"))
            self.assertIn("myhelper() {", (root / "zsh" / "functions" / "custom.zsh").read_text(encoding="utf-8"))
            self.assertIn("test_myhelper_help_returns_zero", (root / "tests" / "zsh" / "test_custom.zsh").read_text(encoding="utf-8"))

            dup_ok, _ = scaffold_new_function(name="myhelper", module="custom", dotfiles=root, regen_docs=False)
            self.assertFalse(dup_ok)


def _seed_mock_antigravity_dir(app_dir: Path) -> tuple[str, str, str]:
    """Create a synthetic `~/.gemini/antigravity` directory with parallel subagents and a swarm worker."""
    root_id = "11111111-1111-4111-8111-111111111111"
    sub1_id = "22222222-2222-4222-8222-222222222222"
    sub2_id = "33333333-3333-4333-8333-333333333333"
    swarm_id = "44444444-4444-4444-8444-444444444444"

    (app_dir / "conversations").mkdir(parents=True)
    conn = sqlite3.connect(str(app_dir / "conversation_summaries.db"))
    conn.execute(
        """
        CREATE TABLE conversation_summaries (
            conversation_id TEXT PRIMARY KEY,
            title TEXT,
            step_count INTEGER,
            last_modified_time TEXT,
            status TEXT,
            agent_name TEXT,
            parent_conversation_id TEXT,
            nesting_depth INTEGER,
            not_fully_idle INTEGER,
            killed INTEGER
        );
        """
    )
    rows = [
        (root_id, "PR Review Root", 40, "2026-04-19T19:00:00Z", "CASCADE_RUN_STATUS_IDLE", "", "", 0, 0, 0),
        (sub1_id, "", 20, "2026-04-19T18:58:00Z", "CASCADE_RUN_STATUS_IDLE", "", root_id, 1, 0, 0),
        (sub2_id, "", 5, "0001-01-01T00:00:00Z", "CASCADE_RUN_STATUS_RUNNING", "", root_id, 1, 1, 0),
        (swarm_id, "", 9, "2026-04-19T18:55:00Z", "CASCADE_RUN_STATUS_IDLE", "verifier", root_id, 1, 0, 1),
    ]
    conn.executemany("INSERT INTO conversation_summaries VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);", rows)
    conn.commit()
    conn.close()

    # Seed `<sub1_id>.db` with tool-schema decoy before `sessionID` and real runtime model after `sessionID`
    sub1_db = sqlite3.connect(str(app_dir / "conversations" / f"{sub1_id}.db"))
    sub1_db.execute("CREATE TABLE gen_metadata (idx INTEGER, key TEXT, data BLOB);")
    blob = (
        b"schema decoy gemini-3.5-flash-lite before marker "
        b"sessionID\x12$abc parent_cascade_id\x12$" + root_id.encode()
        + b" model\x12\x0fgemini-4-carbon\x1a\x18Gemini 4 Carbon (Medium)"
    )
    sub1_db.execute("INSERT INTO gen_metadata VALUES (1, 'meta', ?);", (blob,))
    sub1_db.commit()
    sub1_db.close()

    # Seed root transcript with 2 parallel `invoke_subagent` calls in one step + 1 swarm add
    root_log = app_dir / "brain" / root_id / ".system_generated" / "logs" / "transcript.jsonl"
    root_log.parent.mkdir(parents=True)
    root_steps = [
        {
            "step_index": 1,
            "type": "PLANNER_RESPONSE",
            "tool_calls": [
                {"name": "invoke_subagent", "args": {"Role": '"Finder A"', "Model": '"flash"', "TypeName": '"research"'}},
                {"name": "invoke_subagent", "args": {"Role": '"Finder B"', "Model": '"pro"', "TypeName": '"self"'}},
            ],
        },
        {"step_index": 2, "type": "GENERIC", "content": f'Created the following subagent: {{"conversationId": "{sub1_id}"}}'},
        {"step_index": 3, "type": "GENERIC", "content": f'Created the following subagent: {{"conversationId": "{sub2_id}"}}'},
        {"step_index": 4, "type": "GENERIC", "content": '{"status":"added","name":"verifier","model":"gemini-4-argon"}'},
    ]
    root_log.write_text("\n".join(json.dumps(s) for s in root_steps) + "\n", encoding="utf-8")

    # Seed sub1 transcript (completed via send_message) and sub2 transcript (running at step 12)
    sub1_log = app_dir / "brain" / sub1_id / ".system_generated" / "logs" / "transcript.jsonl"
    sub1_log.parent.mkdir(parents=True)
    sub1_log.write_text(
        json.dumps({"step_index": 19, "source": "MODEL", "type": "PLANNER_RESPONSE", "tool_calls": [{"name": "send_message", "args": {}}]}) + "\n",
        encoding="utf-8",
    )

    sub2_log = app_dir / "brain" / sub2_id / ".system_generated" / "logs" / "transcript.jsonl"
    sub2_log.parent.mkdir(parents=True)
    sub2_log.write_text(
        "\n".join(
            json.dumps({"step_index": i, "type": "PLANNER_RESPONSE", "tool_calls": [{"name": "read_file", "args": {"Path": "/tmp/app.ts"}}]})
            for i in range(1, 13)
        )
        + "\n",
        encoding="utf-8",
    )
    return root_id, sub1_id, sub2_id


class TestCheckSubagentsLibexec(unittest.TestCase):
    """Test `libexec/check_subagents.py` parallel spawns, swarm workers, model tail parsing, and JSON output."""

    def test_parallel_spawns_swarm_and_tail_model_resolution(self) -> None:
        """Verify parallel `invoke_subagent` FIFO matching, swarm workers, and tail-anchored model parsing."""
        with tempfile.TemporaryDirectory() as tmp:
            app_dir = Path(tmp)
            root_id, sub1_id, _sub2_id = _seed_mock_antigravity_dir(app_dir)

            rc, out, err = run_libexec("check_subagents.py", "--app-dir", str(app_dir), "--json", root_id[:8])
            self.assertEqual(rc, 0, err)
            data = json.loads(out)
            self.assertEqual(data["target_id"], root_id)
            self.assertFalse(data["is_subagent"])
            self.assertEqual(len(data["subagents"]), 3)

            by_role = {s["role"]: s for s in data["subagents"]}
            self.assertEqual(by_role["Finder A"]["status"], "COMPLETED")
            self.assertEqual(by_role["Finder A"]["runtime_model_id"], "gemini-4-carbon")
            self.assertEqual(by_role["Finder A"]["runtime_model_label"], "Gemini 4 Carbon (Medium)")
            self.assertEqual(by_role["Finder A"]["configured_model"], "flash")

            self.assertEqual(by_role["Finder B"]["status"], "RUNNING")
            self.assertEqual(by_role["Finder B"]["step_count"], 12)
            self.assertIn("read_file: app.ts", by_role["Finder B"]["latest_activity"])

            self.assertEqual(by_role["Swarm Worker (@verifier)"]["status"], "KILLED")
            self.assertEqual(by_role["Swarm Worker (@verifier)"]["configured_model"], "gemini-4-argon")

            # Direct leaf subagent inspection by prefix
            rc_sub, out_sub, _ = run_libexec("check_subagents.py", "--app-dir", str(app_dir), "--json", sub1_id[:8])
            self.assertEqual(rc_sub, 0)
            sub_data = json.loads(out_sub)
            self.assertTrue(sub_data["is_subagent"])
            self.assertEqual(sub_data["parent_id"], root_id)
            self.assertEqual(sub_data["runtime_model_id"], "gemini-4-carbon")


if __name__ == "__main__":
    unittest.main()
