#!/usr/bin/python3 -I
"""Prepare synthetic AUT state before xcodebuild on a fresh GitHub-hosted Mac.

This is intentionally not a local bootstrap script. It never clears existing
state, reads credentials, changes system settings, or installs an application.
"""

import hashlib
import json
import os
from datetime import date, timedelta
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import tempfile


BUNDLE_ID = "com.defyan94.codex94"
PREFIX = "codex94-ui-v1-"
METADATA_HELPER = "script/release_metadata.py"

# Only these tracked build inputs may enter the disposable recovery source copy.
# No repository metadata, documentation, scripts, local state or directory copy.
BUILD_INPUTS = (
    "Codex94/Models/AppUpdateModels.swift",
    "Codex94/Services/AppUpdateClient.swift",
    "Codex94/Stores/AppUpdateController.swift",
    "Codex94/Views/Components/UpdateSettingsView.swift",
    "Codex94/Models/TokenUsageModels.swift",
    "Codex94/Services/TokenUsageFetching.swift",
    "Codex94/Services/TokenUsageParser.swift",
    "Codex94/Stores/TokenUsageStore.swift",
    "Codex94/Support/TokenUsagePresentation.swift",
    "Codex94/Views/Dashboard/TokenUsageView.swift",
    "Codex94/Views/Dashboard/TokenUsageSummaryView.swift",
    "Codex94/Views/Dashboard/TokenUsageChartView.swift",
    "Codex94/Views/Dashboard/TokenUsageDailyTable.swift",
    "Codex94/Views/Dashboard/TokenUsageCSVDocument.swift",
    "Codex94Tests/TokenUsageParserTests.swift",
    "Codex94Tests/TokenUsageStoreTests.swift",
    "Codex94Tests/TokenUsageRenderingTests.swift",
    "Codex94/Models/NotificationPreferences.swift",
    "Codex94/Models/MenuBarBucketSelection.swift",
    "Codex94/Models/GlobalHotKey.swift",
    "Codex94/Support/QuotaNotificationPolicy.swift",
    "Codex94/Services/NotificationController.swift",
    "Codex94/Services/GlobalHotKeyController.swift",
    "Codex94/Views/Components/ResetCreditsView.swift",
    "Codex94/Views/Components/MenuBarBucketPicker.swift",
    "Codex94/Views/Components/NotificationSettingsView.swift",
    "Codex94/Views/Components/HotKeySettingsView.swift",
    "Codex94Tests/NotificationPolicyTests.swift",
    "Codex94Tests/GlobalHotKeyTests.swift",
    "Codex94Tests/DualWindowTests.swift",
    "Codex94Tests/Version022RenderingTests.swift",
    "Codex94Tests/Version022StoreTests.swift",
    "Codex94.xcodeproj/project.pbxproj",
    "Codex94.xcodeproj/xcshareddata/xcschemes/Codex94.xcscheme",
    "Codex94.xcodeproj/xcshareddata/xcschemes/Codex94UI.xcscheme",
    "Codex94/App/AppDelegate.swift",
    "Codex94/App/Codex94App.swift",
    "Codex94/App/DashboardWindowController.swift",
    "Codex94/Assets.xcassets/AccentColor.colorset/Contents.json",
    "Codex94/Assets.xcassets/AppIcon.appiconset/Contents.json",
    "Codex94/Assets.xcassets/AppIcon.appiconset/icon_128x128.png",
    "Codex94/Assets.xcassets/AppIcon.appiconset/icon_128x128" + "@" + "2x.png",
    "Codex94/Assets.xcassets/AppIcon.appiconset/icon_16x16.png",
    "Codex94/Assets.xcassets/AppIcon.appiconset/icon_16x16" + "@" + "2x.png",
    "Codex94/Assets.xcassets/AppIcon.appiconset/icon_256x256.png",
    "Codex94/Assets.xcassets/AppIcon.appiconset/icon_256x256" + "@" + "2x.png",
    "Codex94/Assets.xcassets/AppIcon.appiconset/icon_32x32.png",
    "Codex94/Assets.xcassets/AppIcon.appiconset/icon_32x32" + "@" + "2x.png",
    "Codex94/Assets.xcassets/AppIcon.appiconset/icon_512x512.png",
    "Codex94/Assets.xcassets/AppIcon.appiconset/icon_512x512" + "@" + "2x.png",
    "Codex94/Assets.xcassets/Contents.json",
    "Codex94/Info.plist",
    "Codex94/Localizable.xcstrings",
    "Codex94/Models/DashboardWindowSize.swift",
    "Codex94/Models/MenuBarAppearance.swift",
    "Codex94/Models/QuotaModels.swift",
    "Codex94/Services/CodexAppServerClient.swift",
    "Codex94/Services/CodexExecutableLocator.swift",
    "Codex94/Services/LaunchAtLoginController.swift",
    "Codex94/Services/ProcessTerminator.swift",
    "Codex94/Services/SnapshotCache.swift",
    "Codex94/Stores/AppStore.swift",
    "Codex94/Stores/PreferencesStore.swift",
    "Codex94/Support/AppMetadata.swift",
    "Codex94/Support/DiagnosticsRedactor.swift",
    "Codex94/Support/Formatting.swift",
    "Codex94/Support/Localization.swift",
    "Codex94/Support/RefreshPolicy.swift",
    "Codex94/Support/StatusPresentation.swift",
    "Codex94/Support/Theme.swift",
    "Codex94/Views/Components/ConnectionBadgeView.swift",
    "Codex94/Views/Components/CopyTextButton.swift",
    "Codex94/Views/Components/QuotaBarView.swift",
    "Codex94/Views/Dashboard/DashboardView.swift",
    "Codex94/Views/Dashboard/DisplaySettingsView.swift",
    "Codex94/Views/Dashboard/OverviewView.swift",
    "Codex94/Views/MenuBar/MenuBarStatusView.swift",
    "Codex94/Views/MenuBar/QuotaPopoverView.swift",
    "Codex94Tests/AppServerClientTests.swift",
    "Codex94Tests/AppStoreTests.swift",
    "Codex94Tests/DashboardWindowSizeTests.swift",
    "Codex94Tests/DiagnosticsRedactorTests.swift",
    "Codex94Tests/ExecutableLocatorTests.swift",
    "Codex94Tests/LaunchAtLoginControllerTests.swift",
    "Codex94Tests/QuotaModelsTests.swift",
    "Codex94Tests/QuotaPopoverLayoutTests.swift",
    "Codex94Tests/RefreshPolicyTests.swift",
    "Codex94Tests/SnapshotCacheTests.swift",
    "Codex94Tests/StatusPresentationTests.swift",
    "Codex94UITests/Codex94UITests.swift",
)
FOCUS_TEMPLATE = "Codex94UITests/Fixtures/ReadOnlyFocusProbe.swift.txt"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def write_new(path, data, mode=0o600):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)


def json_bytes(value):
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode("utf-8")


def git_output(repository, arguments, maximum_bytes):
    result = subprocess.run(
        ["/usr/bin/git", *arguments], cwd=repository,
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        check=False,
    )
    require(result.returncode == 0 and 0 < len(result.stdout) <= maximum_bytes,
            "Could not read the tested Git object")
    return result.stdout


def committed_app_version(repository, source_revision):
    """Load only the tested helper bytes, without changing isolated import paths."""
    head = git_output(repository, ["rev-parse", "HEAD"], 128).decode("ascii").strip()
    require(head == source_revision, "The checked-out HEAD must equal GITHUB_SHA")
    record = git_output(
        repository, ["ls-tree", "-z", source_revision, "--", METADATA_HELPER], 1024
    )
    records = list(filter(None, record.split(b"\0")))
    require(len(records) == 1, "The metadata helper must be uniquely tracked")
    metadata, name = records[0].split(b"\t", 1)
    mode, kind, digest = metadata.split(b" ")
    require(mode == b"100644" and kind == b"blob" and name.decode("utf-8") == METADATA_HELPER,
            "The metadata helper must be a regular tracked source file")
    helper_path = repository / METADATA_HELPER
    require(helper_path == helper_path.resolve(strict=True),
            "The metadata helper must not traverse symbolic links")
    descriptor = os.open(helper_path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()
                and 0 < info.st_size <= 1_048_576, "Invalid bounded metadata helper")
        payload = stream.read(1_048_577)
    require(0 < len(payload) <= 1_048_576, "The metadata helper exceeded its size bound")
    blob = b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    require(hashlib.sha1(blob).hexdigest() == digest.decode("ascii"),
            "The metadata helper changed after checkout")
    # Execute the bytes already checked, not a second file read or a sys.path import.
    namespace = {"__name__": "codex94_release_metadata", "__file__": str(helper_path)}
    exec(compile(payload, str(helper_path), "exec"), namespace)
    return namespace["read_app_version"](repository, source_revision)


def recovery_project(repository, root, source_revision, expected_version, expected_build):
    """Inject a read-only observer into one private copy, never the checkout."""
    require(repository == repository.resolve(), "The build checkout must be canonical")
    head = subprocess.run(
        ["/usr/bin/git", "rev-parse", "HEAD"], cwd=repository,
        capture_output=True, check=True,
    ).stdout.decode("ascii").strip()
    require(head == source_revision, "The recovery copy must use the tested commit")
    requested = set(BUILD_INPUTS) | {FOCUS_TEMPLATE}
    records = subprocess.run(
        ["/usr/bin/git", "ls-tree", "-r", "-z", "HEAD", "--", *sorted(requested)],
        cwd=repository, capture_output=True, check=True,
    ).stdout.split(b"\0")
    hashes = {}
    for record in filter(None, records):
        metadata, name = record.split(b"\t", 1)
        mode, kind, digest = metadata.split(b" ")
        relative = name.decode("utf-8")
        require(mode == b"100644" and kind == b"blob" and relative in requested,
                "Only regular tracked build inputs are permitted")
        require(relative not in hashes, "Duplicate tracked build input")
        hashes[relative] = digest.decode("ascii")
    require(set(hashes) == requested, "The explicit recovery build-input allowlist is incomplete")
    contents = {}
    for relative in sorted(requested):
        source = repository / relative
        require(source == source.resolve(strict=True), "Build inputs must not traverse symbolic links")
        descriptor = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(descriptor, "rb") as stream:
            info = os.fstat(stream.fileno())
            require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()
                    and 0 <= info.st_size <= 16_777_216, "Invalid bounded tracked build input")
            data = stream.read(16_777_217)
        require(len(data) <= 16_777_216, "Build input exceeded its size bound")
        # The Git blob identity binds each copied byte to GITHUB_SHA, not merely
        # to an index entry or a same-named untracked/modified local file.
        blob = b"blob " + str(len(data)).encode("ascii") + b"\0" + data
        require(hashlib.sha1(blob).hexdigest() == hashes[relative], "A tracked build input changed after checkout")
        contents[relative] = data
    require(sum(map(len, contents.values())) <= 67_108_864, "Recovery source copy exceeded its size bound")

    original = contents["Codex94/App/AppDelegate.swift"]
    source_text = original.decode("utf-8")
    anchor = "        configurePopover()\n"
    require(source_text.count(anchor) == 1, "The bounded AppDelegate injection anchor changed")
    source_text = source_text.replace(
        anchor,
        "        configurePopover()\n"
        "        _ = Codex94CIReadOnlyFocusProbe.start(popover: popover)\n",
        1,
    )
    template = contents[FOCUS_TEMPLATE].decode("utf-8")
    replacements = {
        "__CODEX94_CI_FIXTURE_ROOT_LITERAL__": str(root),
        "__CODEX94_CI_EXPECTED_VERSION_LITERAL__": expected_version,
        "__CODEX94_CI_EXPECTED_BUILD_LITERAL__": expected_build,
    }
    for placeholder, value in replacements.items():
        require(template.count(placeholder) == 1,
                "Each read-only observer placeholder must be unique")
        template = template.replace(placeholder, json.dumps(value), 1)
    instrumented = (source_text + "\n" + template).encode("utf-8")

    copy_root = root / "recovery-source"
    copy_root.mkdir(mode=0o700)  # No reuse or overwrite of a previous copy.
    for relative in BUILD_INPUTS:
        directory = copy_root
        for component in Path(relative).parts[:-1]:
            directory = directory / component
            if not directory.exists():
                directory.mkdir(mode=0o700)
            info = directory.lstat()
            require(directory == directory.resolve() and stat.S_ISDIR(info.st_mode)
                    and info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o700,
                    "Recovery source directories must remain private and canonical")
        payload = instrumented if relative == "Codex94/App/AppDelegate.swift" else contents[relative]
        write_new(copy_root / relative, payload)
    metadata = {
        "enabled": True,
        "temporarySourceDirectory": str(copy_root),
        "originalAppDelegateSHA256": hashlib.sha256(original).hexdigest(),
        "instrumentedAppDelegateSHA256": hashlib.sha256(instrumented).hexdigest(),
        "templateSHA256": hashlib.sha256(contents[FOCUS_TEMPLATE]).hexdigest(),
        "trackedBuildInputsSHA256": hashlib.sha256(json_bytes({
            relative: hashlib.sha256(contents[relative]).hexdigest() for relative in BUILD_INPUTS
        })).hexdigest(),
    }
    return copy_root / "Codex94.xcodeproj", metadata


def main():
    require(sys.platform == "darwin", "UI fixtures require macOS")
    require(os.environ.get("GITHUB_ACTIONS") == "true", "UI fixture preparation is CI-only")
    require(os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted", "A fresh hosted runner is required")
    require(os.environ.get("RUNNER_OS") == "macOS", "A hosted Mac is required")
    scenario = os.environ.get("CODEX94_UI_SCENARIO")
    require(scenario in ("display", "recovery", "usage"), "Unknown UI scenario")
    require(os.getuid() != 0, "Do not prepare UI fixtures as root")
    source_revision = os.environ.get("GITHUB_SHA", "")
    require(re.fullmatch(r"[0-9a-f]{40}", source_revision) is not None, "A tested source revision is required")
    repository = Path(__file__).resolve().parents[2]
    require(repository == repository.resolve(), "The build checkout must be canonical")
    expected_version, expected_build = committed_app_version(repository, source_revision)
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
    require(not any(root.iterdir()), "A fresh fixture root must be empty")

    executable = root / "codex"
    invalid_executable = root / "invalid-codex"
    control = root / "control"
    mode_path = control / "mode.json"
    request_log = root / "request-log.jsonl"
    artifacts = root / "artifacts"
    results = root / "results"
    entitlements_file = root / "ui-test.entitlements"
    control.mkdir(mode=0o700)
    artifacts.mkdir(mode=0o700)
    results.mkdir(mode=0o700)
    writable_directories = [str(control) + "/", str(artifacts) + "/"]
    read_only_preference_domains = [BUNDLE_ID]
    # Only the sandboxed external UI runner receives these temporary exceptions.
    # Do not grant it writes to the manifest, fake, request log, AUT state or
    # build products. Xcode retains its standard XCTest runner entitlements.
    write_new(entitlements_file, plistlib.dumps({
        "com.apple.security.temporary-exception.files.absolute-path.read-write": writable_directories,
        "com.apple.security.temporary-exception.shared-preference.read-only": read_only_preference_domains,
    }, fmt=plistlib.FMT_XML, sort_keys=True))
    fake_bytes = fixture_source.read_bytes()
    write_new(executable, fake_bytes, 0o700)
    write_new(invalid_executable, b"Synthetic non-executable Codex94 UI fixture.\n")
    write_new(request_log, b"")
    write_new(mode_path, json_bytes({
        "mode": "normal", "defaultUsedPercent": 68, "sparkUsedPercent": 12, "includeSpark": True,
        "tokenUsageMode": "complete",
    }))

    project = repository / "Codex94.xcodeproj"
    focus_probe = {"enabled": False}
    if scenario == "recovery":
        project, focus_probe = recovery_project(
            repository, root, source_revision, expected_version, expected_build
        )

    initial_preferences = {
        "identityMode": "quotaOnly",
        "hasChosenIdentityMode": True,
        "manualCodexPath": str(invalid_executable if scenario == "recovery" else executable),
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
        "expectedVersion": expected_version,
        "expectedBuild": expected_build,
        "fixtureRoot": str(root),
        "executable": str(executable),
        "invalidExecutable": str(invalid_executable),
        "modePath": str(mode_path),
        "requestLogPath": str(request_log),
        "artifactDirectory": str(artifacts),
        "testEntitlements": str(entitlements_file),
        "testPermissions": {
            "writableDirectories": writable_directories,
            "readOnlyPreferenceDomains": read_only_preference_domains,
        },
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
        "instrumentedAUT": scenario == "recovery",
        "readOnlyFocusProbe": focus_probe,
        "executableSHA256": hashlib.sha256(fake_bytes).hexdigest(),
        "resetsAt": {"codexWeekly": 2_000_000_000, "sparkFiveHour": 2_000_003_600, "sparkWeekly": 2_000_007_200},
        "sparkName": "GPT-5.3-Codex-Spark",
        "longName": "Synthetic Future Model " * 6,
        # Fixed aggregate-only data. No account identity, task title, rollout,
        # credential, or private path may be part of this screenshot source.
        "tokenUsage": {
            "summary": {
                "lifetimeTokens": 1_234_567, "peakDailyTokens": 450_000,
                "longestRunningTurnSec": 3_671, "currentStreakDays": 7,
                "longestStreakDays": 21,
            },
            "dailyUsageBuckets": [
                {"startDate": (date(2033, 4, 14) + timedelta(days=index)).isoformat(),
                 "tokens": 0 if index == 31 else (index + 1) * 1_000}
                for index in range(35)
            ],
        },
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
    system_alias = Path("/tmp") / root.name / "codex"
    require(
        Path("/tmp").resolve() == Path("/private/tmp") and system_alias.resolve() == executable,
        "The system temporary alias must resolve to the exact fake executable",
    )
    for version_executable in (executable, system_alias):
        version = subprocess.run([str(version_executable), "--version"], capture_output=True, timeout=3, check=True)
        require(version.stdout == b"codex-cli 9.4.0-ui-fixture\n", "Unexpected fake version")
    transaction = '\n'.join([
        '{"id":1,"method":"initialize","params":{}}',
        '{"method":"initialized"}',
        '{"id":2,"method":"account/rateLimits/read"}',
    ]) + '\n'
    probe = subprocess.run(
        [str(system_alias), "-s", "read-only", "-a", "never", "app-server", "--stdio"],
        input=transaction.encode("utf-8"), capture_output=True, timeout=3, check=True,
    )
    responses = [json.loads(line) for line in probe.stdout.splitlines()]
    require([response["id"] for response in responses] == [1, 2], "Fake protocol self-check failed")
    require("rateLimitsByLimitId" in responses[1]["result"], "Fake buckets missing")
    self_check_usage = 0
    if scenario == "usage":
        transaction = '\n'.join([
            '{"id":1,"method":"initialize","params":{}}',
            '{"method":"initialized"}',
            '{"id":2,"method":"account/usage/read"}',
        ]) + '\n'
        usage_probe = subprocess.run(
            [str(system_alias), "-s", "read-only", "-a", "never", "app-server", "--stdio"],
            input=transaction.encode("utf-8"), capture_output=True, timeout=3, check=True,
        )
        usage_responses = [json.loads(line) for line in usage_probe.stdout.splitlines()]
        require([response["id"] for response in usage_responses] == [1, 2], "Fake usage self-check failed")
        require(usage_responses[1]["result"] == manifest["tokenUsage"], "Fake usage aggregate mismatch")
        self_check_usage = 1
    # The self-check is accounted for explicitly; do not truncate its log.
    write_new(root / "prepared.json", json_bytes({
        "schemaVersion": 1, "selfCheckRateLimits": 1, "selfCheckTokenUsage": self_check_usage,
    }))
    write_new(artifacts / "isolation.json", json_bytes({
        "schemaVersion": 1, "scenario": scenario,
        "runner": "github-hosted-macos", "preseededBeforeLaunch": True,
        "existingAUTDataRefused": True, "identityMode": "quotaOnly",
        "fakeProtocolSelfCheck": "passed", "selfCheckRateLimits": 1,
        "selfCheckTokenUsage": self_check_usage,
        "fakeSystemTmpAliasChecked": True,
        "sourceRevision": source_revision,
        "instrumentedAUT": scenario == "recovery",
        "readOnlyFocusDiagnostic": scenario == "recovery",
        "normalProductSourceModified": False,
        "runnerWriteScope": ["synthetic-control", "synthetic-artifacts"],
        "runnerPreferenceAccess": "read-only-synthetic-app-domain",
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
        stream.write("entitlements-file=" + str(entitlements_file) + "\n")
        stream.write("project-file=" + str(project) + "\n")
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
