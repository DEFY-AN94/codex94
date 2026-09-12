#!/usr/bin/python3 -I
"""Exercise version parsing and committed-helper loading with disposable Git data."""

import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "script/release_metadata.py"
METADATA = runpy.run_path(str(HELPER))
FIXTURE = runpy.run_path(str(ROOT / "Codex94UITests/Fixtures/prepare.py"))
parse_app_version = METADATA["parse_app_version"]
read_app_version = METADATA["read_app_version"]
committed_app_version = FIXTURE["committed_app_version"]


def project(version="1.2.3", build="42"):
    return """// Synthetic object graph, unrelated target metadata must be ignored.
{
		APP /* Codex94 */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = CONFIGS /* Configurations */;
			name = Codex94;
			productType = "com.apple.product-type.application";
		};
		CONFIGS /* Configurations */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				DEBUG /* Debug */,
				RELEASE /* Release */,
			);
		};
		DEBUG /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				MARKETING_VERSION = VERSION;
				CURRENT_PROJECT_VERSION = BUILD;
			};
			name = Debug;
		};
		RELEASE /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				MARKETING_VERSION = VERSION;
				CURRENT_PROJECT_VERSION = BUILD;
			};
			name = Release;
		};
		UNRELATED /* Tests */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				MARKETING_VERSION = 9.9.9;
				CURRENT_PROJECT_VERSION = 999;
			};
			name = Debug;
		};
}
""".replace("= VERSION;", "= " + version + ";").replace("= BUILD;", "= " + build + ";")


class ParserTests(unittest.TestCase):
    def test_target_metadata_ignores_unrelated_values(self):
        self.assertEqual(parse_app_version(project()), ("1.2.3", "42"))
        self.assertEqual(parse_app_version(project("2.7.0", "100")), ("2.7.0", "100"))

    def test_debug_release_disagreement_is_rejected(self):
        for old, new in (("= 1.2.3;", "= 1.2.4;"), ("= 42;", "= 43;")):
            with self.subTest(field=old), self.assertRaisesRegex(RuntimeError, "must match"):
                parse_app_version(project().replace(old, new, 1))

    def test_missing_or_duplicate_field_is_rejected(self):
        field = "\t\t\t\tMARKETING_VERSION = 1.2.3;\n"
        for replacement in ("", field + field):
            with self.subTest(replacement=replacement), self.assertRaises(RuntimeError):
                parse_app_version(project().replace(field, replacement, 1))

    def test_invalid_version_and_build_are_rejected(self):
        for version in ("01.2.3", "1.2", "1.2.3-beta", '"1.2.3"', "$(CURRENT_VERSION)"):
            with self.subTest(version=version), self.assertRaises(RuntimeError):
                parse_app_version(project(version=version))
        for build in ("0", "01", "-1", "1.5", "$(BUILD_NUMBER)"):
            with self.subTest(build=build), self.assertRaises(RuntimeError):
                parse_app_version(project(build=build))

    def test_duplicate_app_target_is_rejected(self):
        app = """		OTHER /* Codex94 */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = CONFIGS /* Configurations */;
			name = Codex94;
			productType = "com.apple.product-type.application";
		};
"""
        with self.assertRaisesRegex(RuntimeError, "one Codex94 App target"):
            parse_app_version(project() + app)

    def test_duplicate_configuration_object_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "ambiguous"):
            parse_app_version(project() + "\t\tDEBUG /* Debug */ = {\n};\n")


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="codex94-metadata-test-")
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        self.project_path = self.repository / METADATA["PROJECT_FILE"]
        self.project_path.parent.mkdir()
        self.project_path.write_text(project(), encoding="utf-8")
        self.helper_path = self.repository / "script/release_metadata.py"
        self.helper_path.parent.mkdir()
        self.helper_path.write_bytes(HELPER.read_bytes())
        self.git("init", "--quiet")
        self.git("add", "--", METADATA["PROJECT_FILE"], "script/release_metadata.py")
        self.git("-c", "commit.gpgSign=false", "-c", "core.hooksPath=/dev/null",
                 "commit", "--quiet", "-m", "Synthetic metadata fixture")
        self.revision = self.git("rev-parse", "HEAD").stdout.strip()

    def git(self, *arguments):
        environment = os.environ.copy()
        environment.update({
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_AUTHOR_NAME": "Fixture", "GIT_COMMITTER_NAME": "Fixture",
            "GIT_AUTHOR_EMAIL": "fixture@invalid", "GIT_COMMITTER_EMAIL": "fixture@invalid",
        })
        return subprocess.run(
            ["/usr/bin/git", *arguments], cwd=self.repository, env=environment,
            check=True, capture_output=True, text=True,
        )

    def test_worktree_and_revision_modes_use_their_declared_source(self):
        self.project_path.write_text(project("3.4.5", "101"), encoding="utf-8")
        self.assertEqual(read_app_version(self.repository), ("3.4.5", "101"))
        self.assertEqual(read_app_version(self.repository, self.revision), ("1.2.3", "42"))
        self.assertEqual(committed_app_version(self.repository, self.revision), ("1.2.3", "42"))

    def test_revision_must_be_the_full_checked_out_sha(self):
        for revision in ("HEAD", self.revision[:12], "0" * 40):
            with self.subTest(revision=revision), self.assertRaises(RuntimeError):
                read_app_version(self.repository, revision)

    def test_cli_keeps_isolated_python_and_emits_only_json(self):
        for arguments in ([], ["--revision", self.revision]):
            result = subprocess.run(
                [sys.executable, "-I", str(self.helper_path), *arguments],
                cwd=self.repository, check=True, capture_output=True, text=True,
            )
            self.assertEqual(json.loads(result.stdout), {"version": "1.2.3", "build": "42"})
            self.assertEqual(result.stderr, "")

    def test_fixture_rejects_modified_helper_before_execution(self):
        with self.helper_path.open("a", encoding="utf-8") as stream:
            stream.write("\nraise AssertionError('untrusted helper was executed')\n")
        with self.assertRaisesRegex(RuntimeError, "changed after checkout"):
            committed_app_version(self.repository, self.revision)

    def test_fixture_rejects_helper_symlink(self):
        copied_helper = self.repository / "copied-helper.py"
        self.helper_path.rename(copied_helper)
        self.helper_path.symlink_to(copied_helper)
        with self.assertRaisesRegex(RuntimeError, "symbolic links"):
            committed_app_version(self.repository, self.revision)

    def test_fixture_rejects_untracked_helper(self):
        self.git("rm", "--cached", "--", "script/release_metadata.py")
        self.git("-c", "commit.gpgSign=false", "-c", "core.hooksPath=/dev/null",
                 "commit", "--quiet", "-m", "Remove helper from synthetic commit")
        revision = self.git("rev-parse", "HEAD").stdout.strip()
        with self.assertRaises(RuntimeError):
            committed_app_version(self.repository, revision)

    def test_worktree_rejects_project_symlink(self):
        copied_project = self.repository / "copied-project.pbxproj"
        self.project_path.rename(copied_project)
        self.project_path.symlink_to(copied_project)
        with self.assertRaisesRegex(RuntimeError, "symlink"):
            read_app_version(self.repository)


if __name__ == "__main__":
    unittest.main()
