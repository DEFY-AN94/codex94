#!/usr/bin/env python3
"""Exercise Codex preparation using isolated, local-only Git repositories."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


PROJECT = Path(__file__).resolve().parents[2]
PREPARER = PROJECT / "script/codex_prepare.py"
HOOK_CONFIG = PROJECT / ".codex/hooks.json"


class CodexPrepareIntegrationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="Codex94 prepare tests ")
        self.addCleanup(temporary.cleanup)
        self.temporary = Path(temporary.name)
        self.source = self.temporary / "source with spaces"
        (self.source / "script").mkdir(parents=True)
        shutil.copyfile(PREPARER, self.source / "script/codex_prepare.py")
        self.environment = {
            key: value for key, value in os.environ.items() if not key.startswith("GIT_")
        }
        self.environment.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                                GIT_TERMINAL_PROMPT="0")
        self.git(self.source, "init", "--quiet")
        self.git(self.source, "config", "user.name", "Synthetic Fixture")
        self.git(self.source, "config", "user.email", "test" + "@" + "example.com")
        self.git(self.source, "config", "commit.gpgsign", "false")
        self.git(self.source, "config", "core.hooksPath",
                 str(self.temporary / "disabled hooks"))
        self.commit("First fixture revision.\n")
        self.commit("Second fixture revision.\n")

    def git(self, root, *arguments):
        return subprocess.run(["git", "-C", str(root), *arguments], env=self.environment,
                              stdin=subprocess.DEVNULL, capture_output=True, text=True,
                              timeout=10, check=True)

    def commit(self, text):
        (self.source / "fixture.txt").write_text(text, encoding="utf-8")
        self.git(self.source, "add", "--all")
        self.git(self.source, "commit", "--quiet", "-m", "Synthetic preparation fixture")

    def clone(self):
        clone = self.temporary / "shallow clone with spaces"
        self.git(self.source, "clone", "--quiet", "--depth=1", self.source.as_uri(), str(clone))
        self.assertEqual(self.git(clone, "rev-parse", "--is-shallow-repository").stdout,
                         "true\n")
        return clone

    def prepare(self, root, *arguments, cwd=None, environment=None):
        return subprocess.run([sys.executable, "-I", str(root / "script/codex_prepare.py"),
                               *arguments], cwd=cwd or root,
                              env=environment or self.environment, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=40)

    def assert_failure_mode(self, result, hook):
        self.assertEqual(result.returncode, 0 if hook else 1, result.stdout + result.stderr)
        self.assertTrue(result.stdout.strip() if hook else result.stderr.strip())
        if hook:
            self.assertEqual(result.stderr, "")
        else:
            self.assertEqual(result.stdout, "")

    def test_real_shallow_clone_is_completed_when_called_from_subdirectory(self):
        clone = self.clone()
        child = clone / "nested directory" / "child"
        child.mkdir(parents=True)
        result = self.prepare(clone, cwd=child)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(self.git(clone, "rev-parse", "--is-shallow-repository").stdout,
                         "false\n")
        self.assertEqual(self.git(clone, "rev-list", "--count", "HEAD").stdout, "2\n")

        # Removing origin makes an accidental second fetch fail visibly.
        self.git(clone, "remote", "remove", "origin")
        second = self.prepare(clone, cwd=child)
        self.assertEqual((second.returncode, second.stdout, second.stderr), (0, "", ""))

    def test_complete_clone_without_origin_is_silent_in_both_modes(self):
        for arguments in [(), ("--hook",)]:
            with self.subTest(arguments=arguments):
                result = self.prepare(self.source, *arguments)
                self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))

    def test_inherited_git_overrides_cannot_redirect_preparation_to_another_checkout(self):
        clone = self.clone()
        environment = dict(self.environment, GIT_DIR=str(self.source / ".git"),
                           GIT_WORK_TREE=str(self.source),
                           GIT_COMMON_DIR=str(self.source / ".git"),
                           GIT_INDEX_FILE=str(self.temporary / "wrong index"),
                           GIT_OBJECT_DIRECTORY=str(self.temporary / "wrong objects"),
                           GIT_ALTERNATE_OBJECT_DIRECTORIES=str(self.temporary / "wrong alternate"),
                           GIT_SHALLOW_FILE=str(self.temporary / "wrong shallow file"))
        result = self.prepare(clone, cwd=self.source, environment=environment)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(self.git(clone, "rev-parse", "--is-shallow-repository").stdout,
                         "false\n")
        self.assertEqual(self.git(self.source, "remote").stdout, "")
        self.assertEqual(self.git(self.source, "status", "--porcelain").stdout, "")

    def test_registered_codex_hook_runs_from_a_subdirectory(self):
        config = json.loads(HOOK_CONFIG.read_text(encoding="utf-8"))
        registrations = config["hooks"]["SessionStart"]
        hooks = [(registration, hook) for registration in registrations
                 for hook in registration["hooks"]
                 if "script/codex_prepare.py" in hook.get("command", "")]
        self.assertEqual(len(hooks), 1)
        registration, hook = hooks[0]
        for event in ["startup", "resume", "clear", "compact"]:
            self.assertIsNotNone(re.fullmatch(registration["matcher"], event))
        self.assertEqual(hook["type"], "command")
        self.assertIn("--hook", hook["command"])
        self.assertNotIn(".claude", hook["command"])
        self.assertGreaterEqual(hook["timeout"], 50)

        clone = self.clone()
        child = clone / "nested directory"
        child.mkdir()
        result = subprocess.run(["/bin/sh", "-c", hook["command"]], cwd=child,
                                env=self.environment, stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=40)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(self.git(clone, "rev-parse", "--is-shallow-repository").stdout,
                         "false\n")

    def test_registered_hook_ignores_git_overrides_when_finding_its_checkout(self):
        config = json.loads(HOOK_CONFIG.read_text(encoding="utf-8"))
        command = next(hook["command"] for registration in config["hooks"]["SessionStart"]
                       for hook in registration["hooks"]
                       if "script/codex_prepare.py" in hook.get("command", ""))
        clone = self.clone()
        child = clone / "nested directory"
        child.mkdir()
        environment = dict(self.environment, GIT_DIR=str(self.source / ".git"),
                           GIT_WORK_TREE=str(self.source),
                           GIT_COMMON_DIR=str(self.source / ".git"),
                           GIT_INDEX_FILE=str(self.temporary / "wrong index"),
                           GIT_OBJECT_DIRECTORY=str(self.temporary / "wrong objects"),
                           GIT_ALTERNATE_OBJECT_DIRECTORIES=str(self.temporary / "wrong alternate"),
                           GIT_SHALLOW_FILE=str(self.temporary / "wrong shallow file"))
        result = subprocess.run(["/bin/sh", "-c", command], cwd=child, env=environment,
                                stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                timeout=40)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(self.git(clone, "rev-parse", "--is-shallow-repository").stdout,
                         "false\n")
        self.assertEqual(self.git(self.source, "remote").stdout, "")
        self.assertEqual(self.git(self.source, "status", "--porcelain").stdout, "")

    def test_missing_origin_fails_strictly_or_warns_for_hook(self):
        clone = self.clone()
        self.git(clone, "remote", "remove", "origin")
        for hook in [False, True]:
            with self.subTest(hook=hook):
                self.assert_failure_mode(self.prepare(clone, *(["--hook"] if hook else [])),
                                         hook)
        self.assertEqual(self.git(clone, "rev-parse", "--is-shallow-repository").stdout,
                         "true\n")

    def test_fetch_failure_does_not_echo_remote_or_git_errors(self):
        clone = self.clone()
        unavailable = (self.temporary / "missing remote private marker").as_uri()
        self.git(clone, "remote", "set-url", "origin", unavailable)
        for hook in [False, True]:
            with self.subTest(hook=hook):
                result = self.prepare(clone, *(["--hook"] if hook else []))
                self.assert_failure_mode(result, hook)
                self.assertNotIn(unavailable, result.stdout + result.stderr)
                self.assertNotIn("missing remote private marker", result.stdout + result.stderr)
                self.assertNotIn("fatal:", result.stdout + result.stderr)

    def test_missing_git_fails_strictly_or_warns_for_hook(self):
        empty_path = self.temporary / "empty executable path"
        empty_path.mkdir()
        environment = dict(self.environment, PATH=str(empty_path))
        for hook in [False, True]:
            with self.subTest(hook=hook):
                result = self.prepare(self.source, *(["--hook"] if hook else []),
                                      environment=environment)
                self.assert_failure_mode(result, hook)


class CodexPrepareFailureTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("codex_prepare_under_test", PREPARER)
        self.module = importlib.util.module_from_spec(spec)
        with mock.patch.object(sys, "dont_write_bytecode", True):
            spec.loader.exec_module(self.module)

    def invoke(self, runner, hook=False, kill_handler=None):
        stdout, stderr = io.StringIO(), io.StringIO()
        with mock.patch.object(self.module.subprocess, "Popen", side_effect=runner), \
             mock.patch.object(self.module.os, "killpg", side_effect=kill_handler) as kill_group, \
             contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            status = self.module.main(["--hook"] if hook else [])
        self.assertEqual(status, 0 if hook else 1)
        self.assertTrue(stdout.getvalue().strip() if hook else stderr.getvalue().strip())
        if hook:
            self.assertEqual(stderr.getvalue(), "")
        else:
            self.assertEqual(stdout.getvalue(), "")
        self.assertNotIn("synthetic private diagnostic", stdout.getvalue() + stderr.getvalue())
        return kill_group

    @staticmethod
    def result(arguments, stdout="", returncode=0):
        process = mock.Mock(returncode=returncode)
        process.communicate.return_value = (stdout, None)
        return process

    def test_unknown_empty_or_failed_shallow_detection_fails_closed(self):
        for output, returncode in [("unknown\n", 0), ("", 0), ("false\ntrue\n", 0),
                                   ("false\n", 7)]:
            for hook in [False, True]:
                with self.subTest(output=output, returncode=returncode, hook=hook):
                    def runner(arguments, **kwargs):
                        self.assertNotIn("fetch", arguments)
                        return self.result(arguments, output, returncode)
                    self.invoke(runner, hook)

    def test_successful_fetch_must_recheck_that_history_is_complete(self):
        for hook in [False, True]:
            calls = []
            with self.subTest(hook=hook):
                def runner(arguments, **kwargs):
                    calls.append(arguments)
                    output = "true\n" if "--is-shallow-repository" in arguments else "origin\n"
                    return self.result(arguments, output)
                self.invoke(runner, hook)
                self.assertEqual(sum("fetch" in args for args in calls), 1)
                self.assertGreaterEqual(sum("--is-shallow-repository" in args for args in calls),
                                        2)

    def test_fetch_timeout_is_bounded_noninteractive_and_sanitized(self):
        for hook in [False, True]:
            fetch_calls = []
            process = mock.Mock(pid=424242, returncode=-9)
            process.communicate.side_effect = [
                subprocess.TimeoutExpired("git", 30, stderr="synthetic private diagnostic"),
                ("", None),
            ]
            with self.subTest(hook=hook):
                def runner(arguments, **kwargs):
                    if "fetch" in arguments:
                        fetch_calls.append(arguments)
                        self.assertTrue(kwargs.get("start_new_session"))
                        self.assertEqual(kwargs.get("stdin"), subprocess.DEVNULL)
                        self.assertEqual(kwargs.get("stderr"), subprocess.DEVNULL)
                        self.assertEqual(kwargs.get("env", {}).get("GIT_TERMINAL_PROMPT"), "0")
                        self.assertEqual(kwargs.get("env", {}).get("GCM_INTERACTIVE"), "Never")
                        return process
                    output = "true\n" if "--is-shallow-repository" in arguments else "origin\n"
                    return self.result(arguments, output)
                kill_group = self.invoke(runner, hook)
                self.assertEqual(len(fetch_calls), 1)
                kill_group.assert_called_once_with(process.pid, self.module.signal.SIGKILL)
                self.assertEqual(process.communicate.call_args_list,
                                 [mock.call(timeout=30), mock.call()])

    def test_timeout_kills_group_before_reaping_even_when_group_already_exited(self):
        for already_exited in [False, True]:
            events = []
            process = mock.Mock(pid=424242, returncode=-9)
            with self.subTest(already_exited=already_exited):
                def communicate(timeout=None):
                    if timeout is not None:
                        events.append("wait")
                        raise subprocess.TimeoutExpired("git", timeout)
                    events.append("reap")
                    return "", None

                def kill_group(pid, sig):
                    self.assertEqual((pid, sig), (process.pid, self.module.signal.SIGKILL))
                    events.append("kill group")
                    if already_exited:
                        raise ProcessLookupError

                process.communicate.side_effect = communicate
                self.invoke(lambda *args, **kwargs: process, kill_handler=kill_group)
                self.assertEqual(events, ["wait", "kill group", "reap"])

    def test_git_keeps_network_settings_but_discards_repository_overrides(self):
        repository_keys = ["GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE",
                           "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES",
                           "GIT_SHALLOW_FILE"]
        network = {"HTTPS_PROXY": "http://proxy.invalid", "GIT_SSH_COMMAND": "ssh -oBatchMode=yes",
                   "GIT_CONFIG_NOSYSTEM": "1"}
        environment = dict.fromkeys(repository_keys, "synthetic other checkout")
        environment.update(network)
        process = self.result([], "false\n")
        with mock.patch.dict(self.module.os.environ, environment, clear=True), \
             mock.patch.object(self.module.subprocess, "Popen", return_value=process) as popen:
            self.module.git("rev-parse", "--is-shallow-repository")
            self.assertEqual(dict(self.module.os.environ), environment)
        passed_environment = popen.call_args.kwargs["env"]
        self.assertTrue(all(key not in passed_environment for key in repository_keys))
        for key, value in network.items():
            self.assertEqual(passed_environment[key], value)


if __name__ == "__main__":
    unittest.main()
