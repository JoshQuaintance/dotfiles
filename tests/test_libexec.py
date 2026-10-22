"""Unit tests for standalone Python executables in `libexec/` and JSON/bytecode CLI helpers."""

from __future__ import annotations

import contextlib
import hashlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from cli.doctor import orphaned_zsh_bytecode
from cli.env_audit import run_env_audit

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


if __name__ == "__main__":
    unittest.main()
