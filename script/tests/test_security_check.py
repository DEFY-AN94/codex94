#!/usr/bin/env python3
"""Exercise the real scanner in disposable Git repositories, never this history."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCANNER = Path(__file__).resolve().parents[1] / "security_check.sh"
# Assemble test data at runtime so these script sources contain no machine path
# or credential-shaped literal outside the scanner's existing test boundary.
TRUST_PATH = "/" + "Users/" + "synthetic/" + "runtime"
TOKEN = "gh" + "p_" + "A" * 36


class SecurityCheckFixtureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="Codex94SecurityTests-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.environment.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        (self.root / "script").mkdir()
        shutil.copyfile(SCANNER, self.root / "script/security_check.sh")
        self.write("Codex94/Services/CodexAppServerClient.swift",
                   'let arguments = ["-s", "read-only", "-a", "never", "app-server", "--stdio"]\n')
        self.write("Codex94/Services/SnapshotCache.swift", "struct SnapshotCache {}\n")
        self.write("Codex94.xcodeproj/project.pbxproj",
                   "ENABLE_HARDENED_RUNTIME = YES;\nENABLE_APP_SANDBOX = NO;\n")
        self.write("Codex94Tests/Fixture.swift", "// Synthetic fixture.\n")
        self.git("init", "--quiet")
        self.git("config", "user.name", "Synthetic Fixture")
        self.git("config", "user.email", "test" + "@" + "example.com")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "core.hooksPath", str(self.root / "disabled-hooks"))
        self.commit()

    def git(self, *arguments):
        return subprocess.run(["git", *arguments], cwd=self.root, env=self.environment,
                              stdin=subprocess.DEVNULL, capture_output=True, text=True,
                              timeout=10, check=True)

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def commit(self):
        self.git("add", "--all")
        self.git("commit", "--quiet", "-m", "Synthetic scanner fixture")

    def scan(self, expected_error=None):
        result = subprocess.run(["/bin/bash", str(self.root / "script/security_check.sh")],
                                cwd=self.root, env=self.environment, stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=30)
        if expected_error is None:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Static security check passed.", result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(expected_error, result.stderr)

    def historical_only(self, relative, text):
        self.write(relative, text)
        self.commit()
        self.write(relative, "// Removed synthetic observation.\n")
        self.commit()

    def test_exact_trust_path_and_private_alias_allowed_in_current_and_history_tests(self):
        self.scan()
        contents = TRUST_PATH + "\n/private" + TRUST_PATH + "\n"
        self.write("Codex94Tests/Fixture.swift", contents)
        self.scan()
        self.historical_only("Codex94Tests/Fixture.swift", contents)
        self.scan()

    def test_other_synthetic_paths_and_same_prefix_are_rejected_in_current_tests(self):
        for path in [TRUST_PATH + "/child", TRUST_PATH + "-other",
                     TRUST_PATH.removesuffix("runtime") + "elsewhere"]:
            with self.subTest(path=path):
                self.write("Codex94Tests/Fixture.swift", path + "\n")
                self.scan("unapproved identity fixture found in tests")

    def test_other_synthetic_path_is_rejected_in_history_tests(self):
        self.historical_only("Codex94Tests/Fixture.swift", TRUST_PATH + "/child\n")
        self.scan("unapproved identity fixture exists in Git history")

    def test_exact_path_remains_rejected_in_current_production(self):
        self.write("Codex94/Production.swift", TRUST_PATH + "\n")
        self.scan("machine path or email found outside approved fixtures")

    def test_exact_path_remains_rejected_in_production_history(self):
        self.historical_only("Codex94/Production.swift", TRUST_PATH + "\n")
        self.scan("machine path or email exists in Git history")

    def test_credentials_remain_rejected_in_current_tests(self):
        self.write("Codex94Tests/Fixture.swift", TOKEN + "\n")
        self.scan("possible committed credential or private key found")

    def test_credentials_remain_rejected_in_test_history(self):
        self.historical_only("Codex94Tests/Fixture.swift", TOKEN + "\n")
        self.scan("possible credential or private key exists in Git history")


if __name__ == "__main__":
    unittest.main()
