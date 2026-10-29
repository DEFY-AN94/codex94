#!/usr/bin/env python3
"""Check the Run script with disposable source and non-launching fake tools."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "script/build_and_run.sh"
BUILD_STOP = 73


class BuildAndRunTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="Codex94 run tests ")
        self.addCleanup(temporary.cleanup)
        self.temporary = Path(temporary.name)
        self.source = self.temporary / "source with spaces"
        (self.source / "script").mkdir(parents=True)
        self.script = self.source / "script/build_and_run.sh"
        shutil.copyfile(SCRIPT, self.script)
        self.bin = self.temporary / "tools"
        self.bin.mkdir()
        self.build_environment = self.temporary / "build-environment"
        self.build_arguments = self.temporary / "build-arguments"
        self.kill_marker = self.temporary / "fake-pkill-called"
        self.security_marker = self.temporary / "fake-security-called"
        self.selection = "/Applications/Xcode_16.4.app/Contents/Developer"
        self.environment = dict(os.environ)
        self.environment.pop("DEVELOPER_DIR", None)
        self.environment.update(
            PATH=str(self.bin) + ":/usr/bin:/bin",
            CODEX94_TEST_BUILD_ENV=str(self.build_environment),
            CODEX94_TEST_BUILD_ARGS=str(self.build_arguments),
            CODEX94_TEST_KILL_MARKER=str(self.kill_marker),
            CODEX94_TEST_SECURITY_MARKER=str(self.security_marker),
            CODEX94_TEST_SELECTED_DEVELOPER_DIR=self.selection,
        )
        self.write_tool("pkill", 'printf \'%s\\n\' "$*" > "$CODEX94_TEST_KILL_MARKER"\nexit 1\n')
        self.write_tool("xcode-select", 'printf \'%s\\n\' "$CODEX94_TEST_SELECTED_DEVELOPER_DIR"\n')
        self.write_tool("xcodebuild", """
printf '%s\\n' "${DEVELOPER_DIR-__UNSET__}" > "$CODEX94_TEST_BUILD_ENV"
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  printf '%s\\n' "$DEVELOPER_DIR" >> "$CODEX94_TEST_BUILD_ENV"
else
  xcode-select -p >> "$CODEX94_TEST_BUILD_ENV"
fi
printf '%s\\n' "$@" > "$CODEX94_TEST_BUILD_ARGS"
# Stop before the real script's absolute codesign/open/log calls.
exit 73
""")
        security = self.source / "script/security_check.sh"
        security.write_text(
            '#!/bin/bash\nprintf \'checked\\n\' > "$CODEX94_TEST_SECURITY_MARKER"\n',
            encoding="utf-8",
        )
        security.chmod(0o700)

    def write_tool(self, name, body):
        tool = self.bin / name
        tool.write_text("#!/bin/bash\nset -eu\n" + body, encoding="utf-8")
        tool.chmod(0o700)

    def run_script(self, *arguments):
        return subprocess.run(
            ["/bin/bash", str(self.script), *arguments], cwd=self.source,
            env=self.environment, stdin=subprocess.DEVNULL,
            capture_output=True, text=True, timeout=10,
        )

    def assert_stopped_at_build(self, result):
        self.assertEqual(result.returncode, BUILD_STOP, result.stdout + result.stderr)
        self.assertEqual(self.kill_marker.read_text(encoding="utf-8"), "-x Codex94\n")
        self.assertTrue((self.source / ".build/ModuleCache").is_dir())
        self.assertEqual(self.build_arguments.read_text(encoding="utf-8").splitlines(), [
            "-project", str(self.source / "Codex94.xcodeproj"),
            "-scheme", "Codex94", "-configuration", "Debug",
            "-destination", "platform=macOS", "-derivedDataPath",
            str(self.source / ".build/DerivedData"), "build",
        ])

    def test_unset_override_uses_system_selection(self):
        result = self.run_script()
        self.assert_stopped_at_build(result)
        self.assertEqual(self.build_environment.read_text(encoding="utf-8").splitlines(),
                         ["__UNSET__", self.selection])

    def test_empty_override_is_treated_as_unset(self):
        self.environment["DEVELOPER_DIR"] = ""
        result = self.run_script()
        self.assert_stopped_at_build(result)
        self.assertEqual(self.build_environment.read_text(encoding="utf-8").splitlines(),
                         ["__UNSET__", self.selection])

    def test_explicit_override_is_preserved_including_spaces(self):
        for developer in ["/Applications/Xcode-beta.app/Contents/Developer",
                          "/Synthetic Tools/Xcode 27.app/Contents/Developer"]:
            with self.subTest(developer=developer):
                self.environment["DEVELOPER_DIR"] = developer
                result = self.run_script()
                self.assert_stopped_at_build(result)
                self.assertEqual(self.build_environment.read_text(encoding="utf-8").splitlines(),
                                 [developer, developer])

    def test_system_selection_with_spaces_is_not_replaced(self):
        developer = "/Synthetic Tools/Xcode Stable.app/Contents/Developer"
        self.environment["CODEX94_TEST_SELECTED_DEVELOPER_DIR"] = developer
        result = self.run_script()
        self.assert_stopped_at_build(result)
        self.assertEqual(self.build_environment.read_text(encoding="utf-8").splitlines(),
                         ["__UNSET__", developer])

    def test_valid_modes_stop_at_fake_build_before_launching(self):
        for mode in ["run", "--debug", "debug", "--logs", "logs", "--telemetry",
                     "telemetry", "--verify", "verify"]:
            with self.subTest(mode=mode):
                self.security_marker.unlink(missing_ok=True)
                result = self.run_script(mode)
                self.assert_stopped_at_build(result)
                self.assertEqual(self.security_marker.exists(), mode in ["--verify", "verify"])

    def test_invalid_arguments_do_not_stop_an_app_or_create_build_output(self):
        for arguments in [("--unknown",), ("run", "extra")]:
            with self.subTest(arguments=arguments):
                result = self.run_script(*arguments)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn("usage:", result.stderr)
                self.assertFalse(self.kill_marker.exists())
                self.assertFalse(self.build_environment.exists())
                self.assertFalse(self.security_marker.exists())
                self.assertFalse((self.source / ".build").exists())


if __name__ == "__main__":
    unittest.main()
