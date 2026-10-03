#!/usr/bin/python3 -I
"""Synthetic Claude terminal used only inside a fresh registered CI fixture.

No credentials, home-directory configuration, network or conversation input.
The only accepted interactive command is the built-in /usage fixture action.
"""
import datetime
import json
import os
from pathlib import Path
import stat
import sys
import time


def require(value):
    if not value:
        raise RuntimeError("Invalid synthetic Claude fixture")


def main():
    executable = Path(__file__).resolve()
    root = executable.parent
    require(root.parent == Path("/private/tmp"))
    require(root.name.startswith("codex94-ui-v1-"))
    require(root.stat().st_uid == os.getuid() and stat.S_IMODE(root.stat().st_mode) == 0o700)
    require(executable.name == "claude" and not executable.is_symlink())
    if sys.argv[1:] == ["--version"]:
        print("2.1.999 (Claude Code)")
        return
    require(sys.argv[1:] == [
        "--setting-sources", "", "--settings", '{"disableAllHooks":true,"remoteControlAtStartup":false}',
        "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
        "--tools", "", "--permission-mode", "plan", "--no-chrome",
    ])
    print("? for shortcuts", flush=True)
    require(sys.stdin.readline(128).strip() == "/usage")
    mode_file = root / "control" / "claude-mode.json"
    require(not mode_file.is_symlink() and mode_file.stat().st_size <= 1024)
    mode = json.loads(mode_file.read_bytes())["mode"]
    require(mode in ("normal", "error", "slow"))
    descriptor = os.open(root / "claude-request-log.jsonl", os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "a", encoding="utf-8") as stream:
        require(os.fstat(stream.fileno()).st_uid == os.getuid())
        stream.write(json.dumps({"event": "usage", "mode": mode}, sort_keys=True) + "\n")
    if mode == "slow":
        time.sleep(3)
    if mode == "error":
        print("Not logged in. Sign in with Claude Code.", flush=True)
    else:
        now = datetime.datetime.now(datetime.timezone.utc)
        five = now + datetime.timedelta(hours=2)
        week = now + datetime.timedelta(days=3)
        print("\033[2J\033[HCurrent session\n24.5% used")
        print("Resets " + five.strftime("%H:%M") + " (UTC)\n")
        print("Current week (all models)\n61.2% used")
        print("Resets " + week.strftime("%b %d at %H:%M") + " (UTC)\n")
        print("Esc to close", flush=True)
    # Keep the terminal alive so EOF cannot stand in for a completed UI frame.
    while True:
        time.sleep(60)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError):
        print("Synthetic Claude fixture refused the invocation", file=sys.stderr)
        sys.exit(66)
