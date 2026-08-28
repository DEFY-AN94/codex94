#!/usr/bin/python3 -I
"""Strict, local-only synthetic app-server for Codex94's disposable UI runner."""

import atexit
import fcntl
import json
import os
from pathlib import Path
import signal
import stat
import sys
import time


ROOT = Path(__file__).absolute().parent
MODE_NAMES = {"normal", "notLoggedIn", "serverError", "longName", "slow"}
mode_name = "normal"
log_ready = False


def require(condition):
    if not condition:
        raise RuntimeError("Synthetic fixture contract violation")


def regular_file(path):
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid())
    return path


def event(name):
    if not log_ready:
        return
    path = regular_file(ROOT / "request-log.jsonl")
    descriptor = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "a", encoding="utf-8") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        stream.write(json.dumps({"event": name, "pid": os.getpid(), "mode": mode_name}, sort_keys=True) + "\n")
        stream.flush()


def best_effort_event(name):
    try:
        event(name)
    except (OSError, RuntimeError, TypeError, ValueError):
        # Contract failures must not emit a traceback or unvalidated contents.
        pass


def read_message():
    line = sys.stdin.buffer.readline(1_048_577)
    require(bool(line) and len(line) <= 1_048_576)
    value = json.loads(line)
    require(isinstance(value, dict))
    if value.get("method") == "account/read":
        event("rejectedAccountRead")
        raise RuntimeError("Identity RPC is not allowed")
    return value


def reply(value):
    print(json.dumps(value, separators=(",", ":")), flush=True)


def main():
    global log_ready, mode_name
    require(ROOT.parent == Path("/private/tmp") and ROOT.name.startswith("codex94-v018-ui-"))
    require(ROOT == ROOT.resolve() and ROOT.stat().st_uid == os.getuid())
    require(stat.S_IMODE(ROOT.stat().st_mode) == 0o700)
    manifest = json.loads(regular_file(ROOT / "manifest.json").read_text(encoding="utf-8"))
    require(manifest["schemaVersion"] == 1 and manifest["fixtureRoot"] == str(ROOT))
    require(manifest["bundleID"] == "com.defyan94.codex94")
    require(manifest["runner"] == {"environment": "github-hosted", "os": "macOS"})
    require(manifest["executable"] == str(ROOT / "codex"))
    control = ROOT / "control"
    control_info = control.lstat()
    require(stat.S_ISDIR(control_info.st_mode) and control_info.st_uid == os.getuid())
    require(stat.S_IMODE(control_info.st_mode) == 0o700 and control.resolve() == control)
    mode_path = control / "mode.json"
    require(manifest["modePath"] == str(mode_path))
    log_ready = True
    if sys.argv[1:] == ["--version"]:
        event("version")
        print("codex-cli 9.4.0-ui-fixture", flush=True)
        return
    require(sys.argv[1:] == ["-s", "read-only", "-a", "never", "app-server", "--stdio"])

    mode = json.loads(regular_file(mode_path).read_text(encoding="utf-8"))
    require(isinstance(mode, dict))
    candidate_mode = mode.get("mode", "normal")
    require(isinstance(candidate_mode, str) and candidate_mode in MODE_NAMES)
    mode_name = candidate_mode
    default_used = mode.get("defaultUsedPercent", 68)
    spark_used = mode.get("sparkUsedPercent", 12)
    include_spark = mode.get("includeSpark", True)
    require(type(default_used) is int and 0 <= default_used <= 100)
    require(type(spark_used) is int and 0 <= spark_used <= 100)
    require(type(include_spark) is bool)
    event("launch")
    atexit.register(best_effort_event, "exit")
    signal.signal(signal.SIGTERM, lambda _signal, _frame: sys.exit(0))

    initialize = read_message()
    require(initialize.get("method") == "initialize" and initialize.get("id") == 1)
    event("initialize")
    reply({"id": 1, "result": {"serverInfo": {"name": "synthetic-codex94"}}})
    initialized = read_message()
    require(initialized.get("method") == "initialized" and "id" not in initialized)
    limits = read_message()
    require(limits.get("method") == "account/rateLimits/read" and limits.get("id") == 2)
    event("rateLimits")
    if mode_name in ("notLoggedIn", "serverError"):
        message = "not logged in" if mode_name == "notLoggedIn" else "synthetic server error"
        reply({"id": 2, "error": {"code": -32000, "message": message}})
        return
    if mode_name == "slow":
        time.sleep(3)
    resets = manifest["resetsAt"]

    def window(used, duration, reset):
        return {"usedPercent": used, "windowDurationMins": duration, "resetsAt": reset}

    default = {
        "limitId": "default-v2", "planType": "pro", "primary": None,
        "secondary": window(default_used, 10_080, resets["codexWeekly"]),
    }
    spark = {
        "limitName": manifest["longName"] if mode_name == "longName" else manifest["sparkName"],
        "planType": "pro", "primary": window(spark_used, 300, resets["sparkFiveHour"]),
        "secondary": window(min(spark_used + 8, 100), 10_080, resets["sparkWeekly"]),
    }
    buckets = {"default-v2": default}
    if include_spark:
        buckets["model-special"] = spark
    reply({"id": 2, "result": {"rateLimits": default, "rateLimitsByLimitId": buckets}})


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, RuntimeError, TypeError, ValueError):
        best_effort_event("contractFailure")
        sys.exit(70)
