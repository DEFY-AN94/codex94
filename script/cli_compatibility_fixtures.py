#!/usr/bin/python3 -I
"""Validate bounded, synthetic CLI replay data without executing its contents."""

import argparse
import datetime
import json
import math
import os
from pathlib import Path
import re
import stat
import sys


DEFAULT_ROOT = Path(__file__).resolve().parents[1] / "Codex94Tests/Fixtures/CLICompatibility"
MAX_FIXTURES = 64
MAX_FILE_BYTES = 262_144
MAX_TOTAL_BYTES = 1_048_576
MAX_EVENTS = 256
MAX_OUTPUT_BYTES = 65_536
SLUG = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
FIXTURE_PATH = re.compile(r"claude/[a-z0-9]+(?:-[a-z0-9]+)*\.json\Z")
UTC_TIMESTAMP = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\Z")
CLAUDE_VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.]+)? \(Claude Code\)\Z")


class FixtureValidationError(ValueError):
    """Messages are fixed categories: never include fixture payloads or paths."""


def require(condition, category):
    if not condition:
        raise FixtureValidationError(category)


def exact_keys(value, required, optional=()):
    require(isinstance(value, dict), "expected object")
    require(set(required) <= value.keys() and value.keys() <= set(required) | set(optional),
            "invalid object fields")


def bounded_text(value, maximum=256):
    require(isinstance(value, str) and 0 < len(value) <= maximum, "invalid text")
    try:
        value.encode("utf-8")
    except UnicodeError as error:
        raise FixtureValidationError("invalid unicode") from error


def timestamp(value):
    require(isinstance(value, str) and UTC_TIMESTAMP.fullmatch(value) is not None,
            "invalid timestamp")
    try:
        datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as error:
        raise FixtureValidationError("invalid timestamp") from error


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def reject_constant(_value):
    raise FixtureValidationError("nonfinite JSON number")


def read_json(path):
    """Reject symlink leaves and bound the bytes before JSON allocation."""
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode), "expected regular file")
        require(0 < info.st_size <= MAX_FILE_BYTES, "file size limit")
        payload = stream.read(MAX_FILE_BYTES + 1)
    require(len(payload) <= MAX_FILE_BYTES, "file size limit")
    try:
        value = json.loads(payload, object_pairs_hook=unique_object, parse_constant=reject_constant)
    except FixtureValidationError:
        raise
    except (UnicodeError, ValueError, RecursionError) as error:
        raise FixtureValidationError("invalid JSON") from error
    return value, len(payload)


def inventory(root):
    require(stat.S_ISDIR(root.lstat().st_mode), "expected fixture directory")
    result = set()
    entries_seen = 0

    def visit(directory, prefix=""):
        nonlocal entries_seen
        with os.scandir(directory) as entries:
            for entry in entries:
                entries_seen += 1
                require(entries_seen <= 128, "inventory size limit")
                require(not entry.is_symlink(), "symlink fixture entry")
                relative = prefix + entry.name
                if entry.is_dir(follow_symlinks=False):
                    require(relative == "claude", "unexpected fixture directory")
                    visit(Path(entry.path), relative + "/")
                else:
                    require(entry.is_file(follow_symlinks=False), "expected regular file")
                    if entry.name.endswith(".json"):
                        result.add(relative)

    visit(root)
    return result


def validate_fixture(value):
    exact_keys(value, {
        "schemaVersion", "id", "provider", "kind", "scenario", "provenance",
        "fixtureDeclaredVersion", "referenceTime", "locale", "timezone", "events", "expected",
    })
    require(type(value["schemaVersion"]) is int and value["schemaVersion"] == 1, "unsupported schema")
    for field in ("id", "scenario"):
        bounded_text(value[field], 80)
        require(SLUG.fullmatch(value[field]) is not None, "invalid identifier")
    require(value["provider"] == "claude", "unsupported provider")
    require(value["kind"] in ("screen", "queries"), "unsupported fixture kind")
    require(value["locale"] == "en_US" and value["timezone"] == "UTC", "unsupported parsing context")
    timestamp(value["referenceTime"])
    bounded_text(value["fixtureDeclaredVersion"], 100)
    require(CLAUDE_VERSION.fullmatch(value["fixtureDeclaredVersion"]) is not None,
            "invalid simulated version")

    provenance = value["provenance"]
    exact_keys(provenance, {"kind", "sourceTests", "notes"})
    require(provenance["kind"] == "synthetic", "unsupported provenance")
    sources = provenance["sourceTests"]
    require(isinstance(sources, list) and 1 <= len(sources) <= 16, "invalid provenance sources")
    for source in sources:
        bounded_text(source)
    bounded_text(provenance["notes"], 1024)

    events = value["events"]
    require(isinstance(events, list) and 1 <= len(events) <= MAX_EVENTS, "event count limit")
    output_bytes = 0
    for event in events:
        exact_keys(event, {"type"}, {"text", "bytes", "expectedComplete"})
        require(event["type"] == "output", "unsupported event action")
        require(("text" in event) != ("bytes" in event), "invalid output encoding")
        if "text" in event:
            bounded_text(event["text"], MAX_OUTPUT_BYTES)
            output_bytes += len(event["text"].encode("utf-8"))
        else:
            data = event["bytes"]
            require(isinstance(data, list) and 0 < len(data) <= MAX_OUTPUT_BYTES,
                    "invalid byte output")
            require(all(type(byte) is int and 0 <= byte <= 255 for byte in data),
                    "invalid byte output")
            output_bytes += len(data)
        require(output_bytes <= MAX_OUTPUT_BYTES, "decoded output size limit")
        if "expectedComplete" in event:
            require(value["kind"] == "screen" and type(event["expectedComplete"]) is bool,
                    "invalid completeness checkpoint")

    expected = value["expected"]
    if value["kind"] == "queries":
        exact_keys(expected, {"replies"})
        replies = expected["replies"]
        require(isinstance(replies, list) and len(replies) <= 32, "reply count limit")
        for reply in replies:
            bounded_text(reply, 256)
    else:
        require(isinstance(expected, dict) and type(expected.get("complete")) is bool,
                "invalid expected completeness")
        if not expected["complete"]:
            exact_keys(expected, {"complete"})
        else:
            exact_keys(expected, {"complete", "ready", "refreshing", "windows"})
            require(type(expected["ready"]) is bool and type(expected["refreshing"]) is bool,
                    "invalid screen expectation")
            windows = expected["windows"]
            require(isinstance(windows, list) and len(windows) <= 2, "invalid expected windows")
            seen_windows = set()
            for window in windows:
                exact_keys(window, {"kind", "usedPercentage", "resetsAt"})
                kind = window["kind"]
                require(kind in ("fiveHour", "weekly") and kind not in seen_windows,
                        "invalid expected window kind")
                seen_windows.add(kind)
                percentage = window["usedPercentage"]
                require(type(percentage) in (int, float) and 0 <= percentage <= 100
                        and math.isfinite(percentage), "invalid expected percentage")
                if window["resetsAt"] is not None:
                    timestamp(window["resetsAt"])
    return value["id"]


def validate_catalog(root=DEFAULT_ROOT):
    """Return validated fixture IDs in catalog order; never execute sample data."""
    root = Path(root)
    try:
        found = inventory(root)
        catalog, total_bytes = read_json(root / "catalog.json")
        exact_keys(catalog, {"schemaVersion", "fixtures"})
        require(type(catalog["schemaVersion"]) is int and catalog["schemaVersion"] == 1,
                "unsupported schema")
        paths = catalog["fixtures"]
        require(isinstance(paths, list) and 1 <= len(paths) <= MAX_FIXTURES, "fixture count limit")
        for path in paths:
            require(isinstance(path, str) and len(path) <= 100
                    and FIXTURE_PATH.fullmatch(path) is not None, "invalid fixture reference")
        require(len(set(paths)) == len(paths), "duplicate fixture reference")
        require(found == {"catalog.json", *paths}, "catalog inventory mismatch")
        identifiers = []
        for path in paths:
            value, byte_count = read_json(root / path)
            total_bytes += byte_count
            require(total_bytes <= MAX_TOTAL_BYTES, "catalog byte limit")
            identifier = validate_fixture(value)
            require(identifier not in identifiers, "duplicate fixture identifier")
            identifiers.append(identifier)
        return identifiers
    except OSError as error:
        raise FixtureValidationError("fixture filesystem access failed") from error


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT,
                        help="Fixture directory containing catalog.json")
    arguments = parser.parse_args(argv)
    try:
        identifiers = validate_catalog(arguments.root)
    except FixtureValidationError as error:
        print(f"CLI compatibility fixtures invalid: {error}", file=sys.stderr)
        return 1
    print(f"Validated {len(identifiers)} synthetic CLI compatibility fixtures.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
