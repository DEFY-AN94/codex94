#!/usr/bin/python3 -I
"""Validate replay metadata using only synthetic, disposable test directories."""

import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "script/cli_compatibility_fixtures.py"
MODULE = runpy.run_path(str(HELPER))
validate_catalog = MODULE["validate_catalog"]
validate_fixture = MODULE["validate_fixture"]
FixtureValidationError = MODULE["FixtureValidationError"]


def fixture(identifier="weekly-only"):
    return {
        "schemaVersion": 1,
        "id": identifier,
        "provider": "claude",
        "kind": "screen",
        "scenario": "weekly-only",
        "provenance": {
            "kind": "synthetic",
            "sourceTests": ["SyntheticFixtureTests.testWeekly"],
            "notes": "Invented terminal values; no real CLI compatibility claim.",
        },
        "fixtureDeclaredVersion": "2.1.999 (Claude Code)",
        "referenceTime": "2033-05-18T03:33:20Z",
        "locale": "en_US",
        "timezone": "UTC",
        "events": [{"type": "output", "text": "Current week\r\n62.5% used\r\n",
                    "expectedComplete": True}],
        "expected": {"complete": True, "ready": False, "refreshing": False,
                     "windows": [{"kind": "weekly", "usedPercentage": 62.5, "resetsAt": None}]},
    }


class FixtureValidationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="Codex94ReplaySchema-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "claude").mkdir()
        self.path = self.root / "claude/weekly-only.json"
        self.write_fixture(fixture())
        self.write_catalog(["claude/weekly-only.json"])

    def write_fixture(self, value, path=None):
        (path or self.path).write_text(json.dumps(value), encoding="utf-8")

    def write_catalog(self, paths):
        (self.root / "catalog.json").write_text(
            json.dumps({"schemaVersion": 1, "fixtures": paths}), encoding="utf-8")

    def assert_invalid_fixture(self, value):
        with self.assertRaises(FixtureValidationError):
            validate_fixture(value)

    def test_valid_catalog_returns_ordered_ids_and_does_not_change_files(self):
        before = {path: path.read_bytes() for path in self.root.rglob("*.json")}
        self.assertEqual(validate_catalog(self.root), ["weekly-only"])
        self.assertEqual(before, {path: path.read_bytes() for path in self.root.rglob("*.json")})

    def test_query_and_incomplete_screen_expectations(self):
        value = fixture()
        value["kind"] = "queries"
        value["events"] = [{"type": "output", "bytes": [27, 91, 54, 110]}]
        value["expected"] = {"replies": ["\u001b[1;1R"]}
        self.assertEqual(validate_fixture(value), "weekly-only")
        value = fixture()
        value["expected"] = {"complete": False}
        self.assertEqual(validate_fixture(value), "weekly-only")
        value["expected"]["windows"] = []
        self.assert_invalid_fixture(value)

    def test_schema_unknown_fields_and_missing_fields(self):
        for mutation in (
            lambda value: value.update(schemaVersion=2),
            lambda value: value.update(schemaVersion=True),
            lambda value: value.update(command="synthetic-forbidden-action"),
            lambda value: value.pop("provenance"),
            lambda value: value.update(provider="other"),
            lambda value: value.update(kind="shell"),
        ):
            with self.subTest(mutation=mutation):
                value = fixture()
                mutation(value)
                self.assert_invalid_fixture(value)
        catalog = {"schemaVersion": 1, "fixtures": ["claude/weekly-only.json"], "unknown": 1}
        (self.root / "catalog.json").write_text(json.dumps(catalog))
        with self.assertRaises(FixtureValidationError):
            validate_catalog(self.root)

    def test_duplicate_json_keys_and_nonfinite_constants(self):
        valid = self.path.read_text()
        for invalid in (
            valid.replace('"schemaVersion": 1', '"schemaVersion": 1, "schemaVersion": 1'),
            valid.replace('62.5, "resetsAt"', 'NaN, "resetsAt"'),
            valid.replace('62.5, "resetsAt"', 'Infinity, "resetsAt"'),
        ):
            with self.subTest(payload_kind=invalid[:20]):
                self.path.write_text(invalid)
                with self.assertRaises(FixtureValidationError):
                    validate_catalog(self.root)

    def test_malformed_encoding_deep_json_and_large_numbers_are_bounded_failures(self):
        for payload in (b"\xff", b"{", b"[" * 2000 + b"]" * 2000,
                        b'{"value": ' + b"9" * 5000 + b"}"):
            self.path.write_bytes(payload)
            with self.assertRaises(FixtureValidationError):
                validate_catalog(self.root)
        value = fixture()
        value["expected"]["windows"][0]["usedPercentage"] = 10 ** 1000
        self.assert_invalid_fixture(value)

    def test_duplicate_reference_and_duplicate_id(self):
        self.write_catalog(["claude/weekly-only.json"] * 2)
        with self.assertRaises(FixtureValidationError):
            validate_catalog(self.root)
        other = self.root / "claude/other.json"
        self.write_fixture(fixture(), path=other)
        self.write_catalog(["claude/weekly-only.json", "claude/other.json"])
        with self.assertRaises(FixtureValidationError):
            validate_catalog(self.root)

    def test_references_cannot_escape_or_alias_paths(self):
        for reference in ("../outside.json", "/tmp/outside.json", "claude/../catalog.json",
                          "claude//weekly-only.json", "claude\\weekly-only.json", "claude/UPPER.json", 9):
            with self.subTest(reference=reference):
                self.write_catalog([reference])
                with self.assertRaises(FixtureValidationError):
                    validate_catalog(self.root)

    def test_missing_and_uncatalogued_json_are_rejected(self):
        other = self.root / "claude/uncatalogued.json"
        self.write_fixture(fixture("uncatalogued"), path=other)
        with self.assertRaises(FixtureValidationError):
            validate_catalog(self.root)
        other.unlink()
        self.path.unlink()
        with self.assertRaises(FixtureValidationError):
            validate_catalog(self.root)

    def test_file_directory_and_root_symlinks_are_rejected(self):
        target = self.root / "payload.txt"
        target.write_text(self.path.read_text())
        self.path.unlink()
        self.path.symlink_to(target)
        with self.assertRaises(FixtureValidationError):
            validate_catalog(self.root)
        self.path.unlink()
        self.path.write_text(target.read_text())
        (self.root / "extra-link").symlink_to(self.root / "claude", target_is_directory=True)
        with self.assertRaises(FixtureValidationError):
            validate_catalog(self.root)
        (self.root / "extra-link").unlink()
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(FixtureValidationError):
            validate_catalog(alias)

    def test_provenance_must_be_explicitly_synthetic(self):
        for provenance in (
            {"kind": "captured", "sourceTests": ["Test.name"], "notes": "Synthetic"},
            {"kind": "synthetic", "sourceTests": [], "notes": "Synthetic"},
            {"kind": "synthetic", "sourceTests": [""], "notes": "Synthetic"},
            {"kind": "synthetic", "sourceTests": ["Test.name"], "notes": ""},
        ):
            value = fixture()
            value["provenance"] = provenance
            self.assert_invalid_fixture(value)

    def test_text_identifiers_versions_and_dates_are_bounded(self):
        for field, invalid in (
            ("id", "Not a slug"), ("scenario", "a" * 81),
            ("fixtureDeclaredVersion", "UNKNOWN_VERSION"),
            ("referenceTime", "2033-02-30T03:33:20Z"),
            ("referenceTime", "2033-05-18T03:33:20+00:00"),
            ("referenceTime", "2033-05-18T03:33:20.123Z"),
            ("timezone", "Australia/Melbourne"), ("locale", "other"),
        ):
            with self.subTest(field=field, invalid=invalid):
                value = fixture()
                value[field] = invalid
                self.assert_invalid_fixture(value)
        value = fixture()
        value["events"][0]["text"] = "\ud800"
        self.assert_invalid_fixture(value)

    def test_output_xor_actions_and_byte_types(self):
        for event in (
            {"type": "output"},
            {"type": "output", "text": "x", "bytes": [1]},
            {"type": "execute", "text": "synthetic"},
            {"type": "output", "bytes": [True]},
            {"type": "output", "bytes": [-1]},
            {"type": "output", "bytes": [256]},
            {"type": "output", "bytes": [1.5]},
            {"type": "output", "bytes": []},
            {"type": "output", "text": "x", "expectedComplete": 1},
            {"type": "output", "text": "x", "script": "synthetic"},
        ):
            value = fixture()
            value["events"] = [event]
            self.assert_invalid_fixture(value)

    def test_screen_and_query_expectations_are_separate(self):
        value = fixture()
        value["kind"] = "queries"
        value["expected"] = {"replies": []}
        self.assert_invalid_fixture(value)  # screen-only checkpoint retained
        value["events"][0].pop("expectedComplete")
        self.assertEqual(validate_fixture(value), "weekly-only")
        for expected in ({"replies": [""]}, {"replies": ["x"] * 33}, {"replies": [], "complete": True}):
            value["expected"] = expected
            self.assert_invalid_fixture(value)

    def test_expected_values_reject_boolean_percentages_and_duplicate_windows(self):
        for percentage in (True, False, -1, 101, float("nan"), float("inf"), "62.5"):
            value = fixture()
            value["expected"]["windows"][0]["usedPercentage"] = percentage
            self.assert_invalid_fixture(value)
        for update in ({"ready": 0}, {"complete": 1}, {"refreshing": "false"}):
            value = fixture()
            value["expected"].update(update)
            self.assert_invalid_fixture(value)
        value = fixture()
        value["expected"]["windows"] *= 2
        self.assert_invalid_fixture(value)
        value = fixture()
        value["expected"]["windows"][0]["resetsAt"] = "2033-05-18"
        self.assert_invalid_fixture(value)

    def test_event_decoded_byte_and_file_limits(self):
        value = fixture()
        value["events"] = [{"type": "output", "text": "x"}] * 257
        self.assert_invalid_fixture(value)
        value["events"] = [{"type": "output", "text": "界" * 21_846}]
        self.assert_invalid_fixture(value)
        value["events"] = [{"type": "output", "text": "x" * 32_768}] * 2
        self.assertEqual(validate_fixture(value), "weekly-only")
        value["events"].append({"type": "output", "text": "x"})
        self.assert_invalid_fixture(value)
        self.path.write_bytes(b" " * (MODULE["MAX_FILE_BYTES"] + 1))
        with self.assertRaises(FixtureValidationError):
            validate_catalog(self.root)

    def test_catalog_count_and_total_byte_limits(self):
        self.write_catalog(["claude/weekly-only.json"] * 65)
        with self.assertRaises(FixtureValidationError):
            validate_catalog(self.root)
        paths = []
        for index in range(5):
            identifier = f"fixture-{index}"
            path = self.root / f"claude/{identifier}.json"
            self.write_fixture(fixture(identifier), path=path)
            with path.open("a") as stream:
                stream.write(" " * (MODULE["MAX_FILE_BYTES"] - path.stat().st_size))
            paths.append(f"claude/{identifier}.json")
        self.path.unlink()
        self.write_catalog(paths)
        with self.assertRaisesRegex(FixtureValidationError, "catalog byte limit"):
            validate_catalog(self.root)

    def test_cli_failure_does_not_echo_payload_or_filesystem_path(self):
        sentinel = "SYNTHETIC_PRIVATE_SENTINEL"
        self.path.write_text('{"invalid": "' + sentinel + '"}')
        result = subprocess.run([sys.executable, "-I", str(HELPER), "--root", str(self.root)],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn(sentinel, result.stdout + result.stderr)
        self.assertNotIn(str(self.root), result.stdout + result.stderr)
        self.assertLess(len(result.stderr), 200)


if __name__ == "__main__":
    unittest.main()
