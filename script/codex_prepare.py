#!/usr/bin/env python3
"""Prepare Git history for Codex sessions without weakening the security gate."""

import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
FETCH_TIMEOUT = 30


class PreparationError(Exception):
    """A bounded, non-sensitive explanation suitable for session context."""


def git(*arguments, timeout=10):
    environment = os.environ.copy()
    # Session preparation must target this checkout even when invoked from a
    # shell with repository-local Git overrides. Keep network/auth configuration.
    for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE",
                "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES",
                "GIT_SHALLOW_FILE"):
        environment.pop(key, None)
    environment["GIT_TERMINAL_PROMPT"] = "0"
    environment["GCM_INTERACTIVE"] = "Never"
    command = ["git", *arguments]
    try:
        process = subprocess.Popen(
            command, cwd=ROOT, env=environment,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, start_new_session=True,
        )
    except OSError:
        raise PreparationError("Git could not be started in the project checkout.") from None
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        # Git can spawn transport/credential helpers. Stop the entire group so
        # a timed-out fetch does not outlive the session preparation step.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.communicate()
        raise PreparationError("Git operation timed out.") from None
    return subprocess.CompletedProcess(command, process.returncode, output)


def shallow_state():
    result = git("rev-parse", "--is-shallow-repository")
    state = result.stdout.strip()
    if result.returncode != 0 or state not in ("true", "false"):
        raise PreparationError("Could not determine whether Git history is shallow.")
    return state == "true"


def prepare():
    if not shallow_state():
        return
    result = git("fetch", "--unshallow", "--quiet", "origin", timeout=FETCH_TIMEOUT)
    if result.returncode != 0:
        raise PreparationError("Could not complete Git history from origin.")
    if shallow_state():
        raise PreparationError("Git history is still shallow after fetching origin.")
    print("Codex preparation: Git history is no longer shallow.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hook", action="store_true",
                        help="Report preparation failures without blocking a Codex session.")
    arguments = parser.parse_args(argv)
    try:
        prepare()
    except PreparationError as error:
        message = (
            f"Codex preparation warning: {error} "
            "Resolve Git access, run 'git fetch --unshallow origin' if shallow, "
            "and rerun 'python3 -I script/codex_prepare.py' before security checks. "
            "Do not use --allow-shallow-history for development or release validation."
        )
        print(message, file=sys.stdout if arguments.hook else sys.stderr)
        return 0 if arguments.hook else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
