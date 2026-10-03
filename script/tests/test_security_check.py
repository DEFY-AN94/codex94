#!/usr/bin/env python3
"""Exercise the real scanner in disposable Git repositories, never this history."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCANNER = Path(__file__).resolve().parents[1] / "security_check.sh"
PROJECT_ROOT = SCANNER.parent.parent
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

    def install_oauth_boundary(self):
        for relative in ["Codex94/Services/ClaudeOAuthUsageClient.swift", "Codex94/Models/ClaudeOAuthTypes.swift"]:
            self.write(relative, (PROJECT_ROOT / relative).read_text(encoding="utf-8"))

    def test_exact_oauth_client_and_anonymous_release_checker_are_allowed(self):
        self.install_oauth_boundary()
        relative = "Codex94/Services/AppUpdateClient.swift"
        self.write(relative, (PROJECT_ROOT / relative).read_text(encoding="utf-8"))
        self.scan()

    def test_network_client_outside_exact_two_files_is_rejected(self):
        for relative in ["Codex94/Services/OtherClient.swift", "Codex94/Views/ClaudeOAuthUsageClient.swift"]:
            with self.subTest(relative=relative):
                self.write(relative, "let session = URLSession.shared\n")
                self.scan("direct networking outside approved HTTP clients")
                (self.root / relative).unlink()

    def test_release_checker_and_other_files_cannot_gain_bearer_credentials(self):
        for relative in ["Codex94/Services/AppUpdateClient.swift", "Codex94/Other.swift"]:
            with self.subTest(relative=relative):
                self.write(relative, 'request.setValue("Bearer " + value, forHTTPHeaderField: "Authorization")\n')
                self.scan("credential headers outside the guarded OAuth authorize operation")
                (self.root / relative).unlink()

    def test_oauth_authorize_requires_its_guard_and_cannot_be_reused_elsewhere(self):
        self.install_oauth_boundary()
        relative = "Codex94/Models/ClaudeOAuthTypes.swift"
        original = (self.root / relative).read_text(encoding="utf-8")
        guard = "        guard ClaudeOAuthUsageClient.isAllowed(request) else { throw ClaudeOAuthIssue.invalidDestination }\n"
        self.assertIn(guard, original)
        self.write(relative, original.replace(guard, "", 1))
        self.scan("credential headers outside the guarded OAuth authorize operation")
        self.write(relative, original + '\nrequest.setValue("Bearer " + value, forHTTPHeaderField: "Authorization")\n')
        self.scan("additional credential header access outside OAuth authorize")

    def test_oauth_endpoint_method_transport_and_redirect_contracts_fail_closed(self):
        self.install_oauth_boundary()
        relative = "Codex94/Services/ClaudeOAuthUsageClient.swift"
        original = (self.root / relative).read_text(encoding="utf-8")
        cases = [
            ("https://api.anthropic.com/api/oauth/usage", "https://example.invalid/usage", "endpoint allowlist changed"),
            ('request.httpMethod = "GET"', 'request.httpMethod = "POST"', "GET/cache/cookie boundary changed"),
            ('return request.httpMethod == "GET"', 'return request.httpMethod == "POST"', "method/destination/budget validator changed"),
            ("        guard ClaudeOAuthUsageClient.isAllowed(request) else { throw ClaudeOAuthIssue.invalidDestination }\n", "", "transport destination guard changed"),
            ("completionHandler(nil)", "completionHandler(request)", "redirect rejection changed"),
            ("configuration.urlCache = nil", "configuration.urlCache = URLCache.shared", "GET/cache/cookie boundary changed"),
            ("configuration.httpShouldSetCookies = false", "configuration.httpShouldSetCookies = true", "GET/cache/cookie boundary changed"),
        ]
        for before, after, expected in cases:
            with self.subTest(expected=expected, changed=before):
                self.assertIn(before, original)
                self.write(relative, original.replace(before, after, 1))
                self.scan(expected)
        self.write(relative, original + "\nlet secondSession = URLSession.shared\n")
        self.scan("additional OAuth URLSession transport is not approved")

    def test_keychain_cookie_and_ambient_credentials_stay_forbidden_in_allowed_client(self):
        self.install_oauth_boundary()
        relative = "Codex94/Services/ClaudeOAuthUsageClient.swift"
        original = (self.root / relative).read_text(encoding="utf-8")
        for operation in ["SecItemCopyMatching(query, nil)", "SecItemAdd(query, nil)", "SecItemUpdate(query, value)",
                          "SecItemDelete(query)", "SecKeychainFindGenericPassword()", "HTTPCookieStorage.shared",
                          "URLCredentialStorage.shared", 'read("auth.json")']:
            with self.subTest(operation=operation):
                self.write(relative, original + "\n" + operation + "\n")
                self.scan("prohibited credential or direct-HTTP pattern found")

    def test_sensitive_access_in_other_production_files_still_fails(self):
        for operation in ["SecItemCopyMatching(query, nil)", "HTTPCookieStorage.shared", 'read("auth.json")']:
            with self.subTest(operation=operation):
                self.write("Codex94/Other.swift", operation + "\n")
                self.scan("prohibited credential or direct-HTTP pattern found")

    def test_oauth_exception_does_not_skip_current_or_historical_secret_scan(self):
        self.install_oauth_boundary()
        relative = "Codex94/Models/ClaudeOAuthTypes.swift"
        original = (self.root / relative).read_text(encoding="utf-8")
        self.write(relative, original + "\n// " + TOKEN + "\n")
        self.scan("possible committed credential or private key found")
        self.commit()
        self.write(relative, original)
        self.commit()
        self.scan("possible credential or private key exists in Git history")

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
