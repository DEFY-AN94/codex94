#!/usr/bin/python3 -I
"""Prepare synthetic AUT state before xcodebuild on a fresh GitHub-hosted Mac.

This is intentionally not a local bootstrap script. It never clears existing
state, reads credentials, changes system settings, or installs an application.
"""

import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import tempfile


BUNDLE_ID = "com.defyan94.codex94"
PREFIX = "codex94-v018-ui-"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def write_new(path, data, mode=0o600):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)


def json_bytes(value):
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode("utf-8")


def main():
    require(sys.platform == "darwin", "UI fixtures require macOS")
    require(os.environ.get("GITHUB_ACTIONS") == "true", "UI fixture preparation is CI-only")
    require(os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted", "A fresh hosted runner is required")
    require(os.environ.get("RUNNER_OS") == "macOS", "A hosted Mac is required")
    scenario = os.environ.get("CODEX94_UI_SCENARIO")
    require(scenario in ("display", "recovery"), "Unknown UI scenario")
    require(os.getuid() != 0, "Do not prepare UI fixtures as root")
    source_revision = os.environ.get("GITHUB_SHA", "")
    require(re.fullmatch(r"[0-9a-f]{40}", source_revision) is not None, "A tested source revision is required")
    output = os.environ.get("GITHUB_OUTPUT")
    require(bool(output), "GitHub step output channel is required")
    output_path = Path(output)
    require(output_path.is_absolute(), "GitHub step output channel must be absolute")
    output_info = output_path.lstat()
    require(
        stat.S_ISREG(output_info.st_mode) and output_info.st_uid == os.getuid(),
        "GitHub step output channel must be an owned regular file",
    )

    # Metadata-only checks, confined to the synthetic application's known paths.
    # Refuse a reused environment; never delete/restore somebody else's state.
    library = Path.home() / "Library"
    protected = [
        library / "Preferences" / (BUNDLE_ID + ".plist"),
        library / "Application Support" / "Codex94",
        library / "Saved Application State" / (BUNDLE_ID + ".savedState"),
        library / "Containers" / BUNDLE_ID,
        library / "Caches" / BUNDLE_ID,
    ]
    require(all(not os.path.lexists(path) for path in protected), "Existing AUT data: refuse to overwrite it")
    by_host = library / "Preferences" / "ByHost"
    require(
        not any(by_host.glob(BUNDLE_ID + ".*.plist")),
        "Existing host-specific AUT preferences: refuse to overwrite them",
    )

    fixture_source = Path(__file__).resolve().with_name("app_server.py")
    require(fixture_source.is_file() and not fixture_source.is_symlink(), "Missing regular fake executable source")
    root = Path(tempfile.mkdtemp(prefix=PREFIX, dir="/private/tmp"))
    require(root == root.resolve(), "Fixture root must not traverse a symlink")
    require(root.stat().st_uid == os.getuid(), "Fixture root owner mismatch")
    require(stat.S_IMODE(root.stat().st_mode) == 0o700, "Fixture root must be private")

    executable = root / "codex"
    invalid_executable = root / "invalid-codex"
    mode_path = root / "mode.json"
    request_log = root / "request-log.jsonl"
    artifacts = root / "artifacts"
    results = root / "results"
    artifacts.mkdir(mode=0o700)
    results.mkdir(mode=0o700)
    fake_bytes = fixture_source.read_bytes()
    write_new(executable, fake_bytes, 0o700)
    write_new(invalid_executable, b"Synthetic non-executable Codex94 UI fixture.\n")
    write_new(request_log, b"")
    write_new(mode_path, json_bytes({
        "mode": "normal", "defaultUsedPercent": 68, "sparkUsedPercent": 12, "includeSpark": True,
    }))

    initial_preferences = {
        "identityMode": "quotaOnly",
        "hasChosenIdentityMode": True,
        "manualCodexPath": str(executable if scenario == "display" else invalid_executable),
        "refreshInterval": 30,
        "theme": "terminalDark",
        "language": "english",
        "displayMode": "weekly",
        "menuBarLayout.v1": "ringAndPercentage",
        "statusAccentOverrides.v1": {
            "healthy": "27C8FF", "warning": "FF8C42", "critical": "DA70D6", "error": "FF3366",
        },
    }
    manifest = {
        "schemaVersion": 1,
        "scenario": scenario,
        "bundleID": BUNDLE_ID,
        "expectedVersion": "0.1.8",
        "expectedBuild": "9",
        "fixtureRoot": str(root),
        "executable": str(executable),
        "invalidExecutable": str(invalid_executable),
        "modePath": str(mode_path),
        "requestLogPath": str(request_log),
        "artifactDirectory": str(artifacts),
        "applicationProduct": str(root / "DerivedData" / "Build" / "Products" / "Debug" / "Codex94.app"),
        "applicationPaths": {
            "preferences": str(library / "Preferences" / (BUNDLE_ID + ".plist")),
            "quotaCache": str(library / "Application Support" / "Codex94" / "quota-snapshot.json"),
            "runtime": str(library / "Application Support" / "Codex94" / "Runtime"),
            "savedState": str(library / "Saved Application State" / (BUNDLE_ID + ".savedState")),
            "windowAutosaveDomain": BUNDLE_ID,
            "windowAutosaveKey": "NSWindow Frame Codex94Dashboard",
        },
        "sourceRevision": source_revision,
        "executableSHA256": hashlib.sha256(fake_bytes).hexdigest(),
        "resetsAt": {"codexWeekly": 2_000_000_000, "sparkFiveHour": 2_000_003_600, "sparkWeekly": 2_000_007_200},
        "sparkName": "GPT-5.3-Codex-Spark",
        "longName": "Synthetic Future Model " * 6,
        "timeZoneIdentifier": "system",
        "initialPreferences": initial_preferences,
        "runner": {"environment": "github-hosted", "os": "macOS"},
    }
    write_new(root / "manifest.json", json_bytes(manifest))
    seed = root / "initial-preferences.plist"
    write_new(seed, plistlib.dumps(initial_preferences, fmt=plistlib.FMT_XML, sort_keys=True))

    # The entire VM is disposable. This import happens before ANY AUT/test host
    # initialization, including PreferencesStore's migration/cache access.
    result = subprocess.run(
        ["/usr/bin/defaults", "import", BUNDLE_ID, str(seed)],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    require(result.returncode == 0, "Could not preseed the synthetic AUT preferences")

    # Run a fake-only protocol self-check before launching the real application.
    version = subprocess.run([str(executable), "--version"], capture_output=True, timeout=3, check=True)
    require(version.stdout == b"codex-cli 9.4.0-ui-fixture\n", "Unexpected fake version")
    transaction = '\n'.join([
        '{"id":1,"method":"initialize","params":{}}',
        '{"method":"initialized"}',
        '{"id":2,"method":"account/rateLimits/read"}',
    ]) + '\n'
    probe = subprocess.run(
        [str(executable), "-s", "read-only", "-a", "never", "app-server", "--stdio"],
        input=transaction.encode("utf-8"), capture_output=True, timeout=3, check=True,
    )
    responses = [json.loads(line) for line in probe.stdout.splitlines()]
    require([response["id"] for response in responses] == [1, 2], "Fake protocol self-check failed")
    require("rateLimitsByLimitId" in responses[1]["result"], "Fake buckets missing")
    # The self-check is accounted for explicitly; do not truncate its log.
    write_new(root / "prepared.json", json_bytes({"schemaVersion": 1, "selfCheckRateLimits": 1}))
    write_new(artifacts / "isolation.json", json_bytes({
        "schemaVersion": 1, "scenario": scenario,
        "runner": "github-hosted-macos", "preseededBeforeLaunch": True,
        "existingAUTDataRefused": True, "identityMode": "quotaOnly",
        "fakeProtocolSelfCheck": "passed", "selfCheckRateLimits": 1,
        "sourceRevision": source_revision,
        "rawTestResultsUploaded": False,
    }))

    descriptor = os.open(output_path, os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "a", encoding="utf-8") as stream:
        current_info = os.fstat(stream.fileno())
        require(
            stat.S_ISREG(current_info.st_mode) and current_info.st_uid == os.getuid()
            and (current_info.st_dev, current_info.st_ino) == (output_info.st_dev, output_info.st_ino),
            "GitHub step output channel changed during preparation",
        )
        stream.write("fixture-root=" + str(root) + "\n")
        stream.write("artifact-root=" + str(artifacts) + "\n")
    print("Prepared one fresh synthetic UI scenario; no existing AUT state was modified.")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as error:
        print("UI fixture preparation failed: " + str(error), file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        # No environment, preference contents, raw RPC, or personal paths in logs.
        print("UI fixture preparation failed: " + type(error).__name__, file=sys.stderr)
        sys.exit(1)
