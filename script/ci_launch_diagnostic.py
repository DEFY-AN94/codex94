#!/usr/bin/python3 -I
"""Temporary, Providers-only CI diagnostic. Never emits raw logs or crash reports."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import selectors
import signal
import stat
import subprocess
import sys
import time


BUNDLE = "com.defyan94.codex94"
MAX_REPORT = 2 * 1024 * 1024


class Refused(Exception):
    pass


class SafeArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        raise Refused("arguments_invalid")


def require(value, code):
    if not value:
        raise Refused(code)


def regular_bytes(path, limit, executable=False):
    require(path.is_absolute() and path == path.resolve(), "noncanonical_file")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        require(stat.S_ISREG(before.st_mode) and before.st_uid == os.getuid()
                and before.st_nlink == 1 and 0 <= before.st_size <= limit,
                "unsafe_file")
        require(not executable or (before.st_mode & 0o111 and not before.st_mode & 0o022),
                "unsafe_executable")
        chunks = []
        remaining = limit + 1
        while remaining:
            chunk = os.read(fd, min(remaining, 65536))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        data = b"".join(chunks)
        after = os.fstat(fd)
        require((before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns,
                 before.st_uid, before.st_nlink) ==
                (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns,
                 after.st_uid, after.st_nlink) and len(data) == before.st_size,
                "changed_file")
        return data
    finally:
        os.close(fd)


def json_file(path, limit=131072):
    value = json.loads(regular_bytes(path, limit))
    require(isinstance(value, dict), "invalid_json_shape")
    return value


def command(arguments, timeout=10, maximum=65536):
    """No command output escapes this function without a specific parser."""
    process = subprocess.Popen(arguments, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=True)
    selector = selectors.DefaultSelector()
    for stream in (process.stdout, process.stderr):
        os.set_blocking(stream.fileno(), False)
        selector.register(stream, selectors.EVENT_READ)
    output = {process.stdout: bytearray(), process.stderr: bytearray()}
    deadline = time.monotonic() + timeout
    timed_out = False
    try:
        while selector.get_map():
            if time.monotonic() >= deadline:
                timed_out = True
                break
            for key, _ in selector.select(min(0.1, max(0, deadline - time.monotonic()))):
                chunk = os.read(key.fileobj.fileno(), 8192)
                if not chunk:
                    selector.unregister(key.fileobj)
                else:
                    target = output[key.fileobj]
                    if len(target) < maximum:
                        target.extend(chunk[:maximum - len(target)])
            if process.poll() is not None and not selector.get_map():
                break
    finally:
        selector.close()
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        process.wait(timeout=3)
        for stream in (process.stdout, process.stderr):
            stream.close()
    return process.returncode, bytes(output[process.stdout]), bytes(output[process.stderr]), timed_out


def fixture(root):
    require(sys.platform == "darwin" and os.getuid() != 0, "host_not_supported")
    require(os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted"
            and os.environ.get("RUNNER_OS") == "macOS", "host_not_isolated")
    require(root.is_absolute() and root == root.resolve() and root.parent == Path("/private/tmp")
            and re.fullmatch(r"codex94-ui-v1-[A-Za-z0-9_-]{6,64}", root.name), "fixture_root_invalid")
    info = root.lstat()
    require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid()
            and stat.S_IMODE(info.st_mode) == 0o700, "fixture_root_unsafe")
    manifest = json_file(root / "manifest.json")
    isolation = json_file(root / "artifacts/isolation.json")
    prepared = json_file(root / "prepared.json")
    revision = os.environ.get("GITHUB_SHA", "")
    require(re.fullmatch(r"[0-9a-f]{40}", revision) is not None, "source_invalid")
    require(manifest.get("schemaVersion") == 1 and manifest.get("scenario") == "providers"
            and manifest.get("bundleID") == BUNDLE and manifest.get("fixtureRoot") == str(root)
            and manifest.get("sourceRevision") == revision and manifest.get("instrumentedAUT") is False
            and manifest.get("runner") == {"environment": "github-hosted", "os": "macOS"},
            "manifest_not_providers")
    require(isolation.get("schemaVersion") == 1 and isolation.get("scenario") == "providers"
            and isolation.get("sourceRevision") == revision
            and isolation.get("runner") == "github-hosted-macos"
            and all(isolation.get(key) is True for key in
                    ("preseededBeforeLaunch", "existingAUTDataRefused", "claudeFakeOnly"))
            and isolation.get("normalProductSourceModified") is False
            and isolation.get("instrumentedAUT") is False
            and isolation.get("identityMode") == "quotaOnly"
            and isolation.get("fakeProtocolSelfCheck") == "passed"
            and prepared.get("schemaVersion") == 1 and prepared.get("selfCheckRateLimits") == 1,
            "isolation_not_proven")
    require(manifest.get("claudeIsolation") ==
            {"realConfigurationAbsent": True, "knownExecutablesAbsent": True}, "claude_isolation_invalid")
    expected = {
        "executable": root / "codex", "claudeExecutable": root / "claude",
        "claudeConfigDirectory": root / "control/claude-config",
        "applicationProduct": root / "DerivedData/Build/Products/Debug/Codex94.app",
        "modePath": root / "control/mode.json", "claudeModePath": root / "control/claude-mode.json",
    }
    for key, path in expected.items():
        require(manifest.get(key) == str(path) and path == path.resolve(), "fixture_path_invalid")
    repository = Path(__file__).resolve().parent.parent
    result, head, _, timed = command(["/usr/bin/git", "-C", str(repository), "rev-parse", "HEAD"])
    require(result == 0 and not timed and head.decode("ascii").strip() == revision, "checkout_mismatch")
    for key, source in (("executable", "app_server.py"), ("claudeExecutable", "claude_usage.py")):
        data = regular_bytes(expected[key], 262144, executable=True)
        require(stat.S_IMODE(expected[key].stat().st_mode) == 0o700, "fake_mode_invalid")
        require(hashlib.sha256(data).hexdigest() == manifest.get(key + "SHA256"), "fake_hash_invalid")
        result, tracked, _, timed = command(["/usr/bin/git", "-C", str(repository), "show",
                                            revision + ":Codex94UITests/Fixtures/" + source], maximum=262144)
        require(result == 0 and not timed and tracked == data, "fake_source_mismatch")
    for key in ("modePath", "claudeModePath"):
        json_file(expected[key], 16384)
    config = json_file(expected["claudeConfigDirectory"] / ".claude.json", 65536)
    require(set(config) == {"numStartups", "cachedUsageUtilization"}
            and config["cachedUsageUtilization"].get("accountUuid") == "00000000-0000-4000-8000-000000000001",
            "claude_fixture_not_synthetic")
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", str(manifest.get("expectedVersion")))
            and re.fullmatch(r"[0-9]+", str(manifest.get("expectedBuild"))), "metadata_invalid")
    home = Path.home()
    for path in (home / ".claude", home / ".claude.json", home / ".local/bin/claude",
                 home / "Library/Application Support/Claude", Path("/opt/homebrew/bin/claude"),
                 Path("/usr/local/bin/claude")):
        require(not os.path.lexists(path), "real_claude_present")
    preferences = home / "Library/Preferences" / (BUNDLE + ".plist")
    require(manifest.get("applicationPaths", {}).get("preferences") == str(preferences), "preferences_path_invalid")
    value = plistlib.loads(regular_bytes(preferences, 131072))
    require(value.get("manualCodexPath") == str(expected["executable"])
            and value.get("identityMode") == "quotaOnly"
            and value.get("hasChosenIdentityMode") is True, "preferences_not_synthetic")
    return manifest, expected


def candidate(manifest, paths):
    app = paths["applicationProduct"]
    binary = app / "Contents/MacOS/Codex94"
    data = regular_bytes(binary, 64 * 1024 * 1024, executable=True)
    info = plistlib.loads(regular_bytes(app / "Contents/Info.plist", 131072))
    require(info.get("CFBundleIdentifier") == BUNDLE and info.get("CFBundleExecutable") == "Codex94"
            and info.get("CFBundleShortVersionString") == manifest["expectedVersion"]
            and str(info.get("CFBundleVersion")) == str(manifest["expectedBuild"]), "candidate_metadata_mismatch")
    code, output, _, timeout = command(["/usr/bin/lipo", "-archs", str(binary)])
    archs = output.decode("ascii", errors="ignore").split()
    require(not timeout and code == 0 and archs and set(archs) <= {"arm64", "x86_64"}, "candidate_architecture_invalid")
    verified, _, _, timed = command(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)])
    return binary, {"version": manifest["expectedVersion"], "build": str(manifest["expectedBuild"]),
                    "architectures": archs, "executableSHA256": hashlib.sha256(data).hexdigest(),
                    "signatureVerificationExitCode": verified, "signatureVerificationTimedOut": timed}


def category(value, pattern, fallback="unknown"):
    return value if (isinstance(value, str) and re.fullmatch(pattern, value)
                     and not re.search(r"0[xX][0-9a-fA-F]+", value)) else fallback


def crashes(binary):
    directory = Path.home() / "Library/Logs/DiagnosticReports"
    if not directory.exists():
        return {"matchingReports": [], "rejectedReports": 0}
    require(directory == directory.resolve() and directory.stat().st_uid == os.getuid(), "crash_directory_unsafe")
    candidates = sorted(directory.glob("Codex94-*.ips"), key=lambda p: p.name, reverse=True)[:12]
    results, rejected = [], 0
    for path in candidates:
        try:
            text = regular_bytes(path, MAX_REPORT).decode("utf-8")
            decoder = json.JSONDecoder()
            first, end = decoder.raw_decode(text.lstrip())
            remaining = text.lstrip()[end:].lstrip()
            report = decoder.raw_decode(remaining)[0] if remaining else first
            require(isinstance(report, dict) and report.get("procName") == "Codex94"
                    and report.get("procPath") == str(binary)
                    and report.get("bundleInfo", {}).get("CFBundleIdentifier") == BUNDLE,
                    "crash_not_candidate")
            exception, termination = report.get("exception", {}), report.get("termination", {})
            item = {"exceptionType": category(exception.get("type"), r"EXC_[A-Z0-9_]{1,48}"),
                    "signal": category(exception.get("signal"), r"SIG[A-Z0-9]{1,16}"),
                    "terminationNamespace": category(termination.get("namespace"), r"[A-Z][A-Z0-9_-]{0,31}"),
                    "terminationCode": termination.get("code") if type(termination.get("code")) is int else None,
                    "faultingFrames": []}
            index, threads, images = report.get("faultingThread"), report.get("threads", []), report.get("usedImages", [])
            if type(index) is int and 0 <= index < len(threads):
                for frame in threads[index].get("frames", [])[:8]:
                    image_index = frame.get("imageIndex")
                    module = "unknown"
                    if type(image_index) is int and 0 <= image_index < len(images):
                        module = category(images[image_index].get("name"), r"[A-Za-z0-9_.+-]{1,80}")
                    symbol = category(frame.get("symbol"), r"[A-Za-z_.$][A-Za-z0-9_.$:<>()+\-\[\] ,*&?~]{0,159}")
                    item["faultingFrames"].append({"module": module, "symbol": symbol})
            results.append(item)
            if len(results) == 4:
                break
        except Exception:
            rejected += 1
    return {"matchingReports": results, "rejectedReports": rejected}


def direct_launch(root, paths, binary, identity):
    require(identity["signatureVerificationExitCode"] == 0
            and not identity["signatureVerificationTimedOut"], "launch_signature_invalid")
    code, _, _, timed = command(["/usr/bin/pgrep", "-x", "Codex94"])
    require(not timed and code == 1, "existing_app_or_process_check_failed")
    # Recheck the exact candidate immediately before execution.
    require(hashlib.sha256(regular_bytes(binary, 64 * 1024 * 1024, executable=True)).hexdigest()
            == identity["executableSHA256"], "candidate_changed")
    environment = {key: os.environ[key] for key in ("HOME", "USER", "LOGNAME", "TMPDIR") if key in os.environ}
    environment.update({"PATH": str(root) + ":/usr/bin:/bin", "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8",
                        "CLAUDE_CONFIG_DIR": str(paths["claudeConfigDirectory"])})
    process = subprocess.Popen([str(binary), "--show-popover"], cwd=root, env=environment,
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.PIPE, start_new_session=True)
    os.set_blocking(process.stderr.fileno(), False)
    selector = selectors.DefaultSelector()
    selector.register(process.stderr, selectors.EVENT_READ)
    stderr = bytearray()
    deadline = time.monotonic() + 5
    running = False
    try:
        while time.monotonic() < deadline:
            for key, _ in selector.select(0.1):
                chunk = os.read(key.fileobj.fileno(), 8192)
                if not chunk:
                    selector.unregister(key.fileobj)
                elif len(stderr) < 65536:
                    stderr.extend(chunk[:65536 - len(stderr)])
            if process.poll() is not None:
                break
        running = process.poll() is None
        natural_code = process.poll()
    finally:
        selector.close()
        # Only the newly created session/process group is eligible for cleanup.
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        process.wait(timeout=2)
        process.stderr.close()
    lowered = bytes(stderr).lower()
    categories = [name for name, markers in {
        "metal_device": (b"mtlloader", b"target device architecture is nil"),
        "swift_fatal": (b"fatal error", b"precondition failed"),
        "dynamic_loader": (b"dyld", b"library not loaded"),
        "signature": (b"code signature", b"codesigning"),
        "window_server": (b"windowserver", b"window server"),
        "launch_services": (b"launchservices", b"launch services"),
        "xpc": (b"xpc",),
    }.items() if any(marker in lowered for marker in markers)]
    return {"observationSeconds": 5, "runningAtDeadline": running,
            "naturalExitCode": natural_code if natural_code is None or natural_code >= 0 else None,
            "naturalSignal": -natural_code if natural_code is not None and natural_code < 0 else None,
            "cleanupExitCode": process.returncode, "stderrCategories": categories,
            "stderrPresent": bool(stderr), "rawOutputRetained": False}


def main():
    parser = SafeArgumentParser(add_help=False)
    parser.add_argument("--fixture-root", required=True)
    parser.add_argument("--launch", action="store_true")
    # Invalid arguments are normalized below; argparse never prints paths.
    try:
        arguments, unknown = parser.parse_known_args()
        require(not unknown, "arguments_invalid")
    except (SystemExit, Refused):
        return {"schemaVersion": 1, "status": "blocked", "reason": "arguments_invalid"}
    result = {"schemaVersion": 1, "diagnosticOnly": True, "status": "blocked", "rawOutputRetained": False}
    try:
        root = Path(arguments.fixture_root)
        manifest, paths = fixture(root)
        binary, identity = candidate(manifest, paths)
        result.update({"candidate": identity, "beforeLaunch": crashes(binary)})
        if arguments.launch:
            result["directLaunch"] = direct_launch(root, paths, binary, identity)
            time.sleep(2)
            result["afterLaunch"] = crashes(binary)
        result["status"] = "complete"
    except Refused as error:
        result["reason"] = str(error)
    except Exception:
        result["reason"] = "diagnostic_unavailable"
    return result


if __name__ == "__main__":
    # No traceback, command output, paths, report names or raw crash fields.
    try:
        report = main()
        encoded = json.dumps(report, sort_keys=True, separators=(",", ":"))
        if len(encoded.encode("utf-8")) > 24576:
            encoded = '{"schemaVersion":1,"status":"blocked","reason":"output_limit"}'
        print(encoded)
    except BaseException:
        print('{"schemaVersion":1,"status":"blocked","reason":"diagnostic_failed"}')
