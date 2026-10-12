# Codex94 notes for Claude Code

`CONTRIBUTING.md`, `SECURITY.md`, `PRIVACY.md` and `docs/RELEASING.md` are the
source of truth for project rules. This file only records where each check can
run.

## Platform split

Codex94 is a macOS 14+ SwiftUI/AppKit App built with Xcode. GitHub CI
(`.github/workflows/ci.yml`, `macos-15`, Xcode 16.4) owns `release_check.sh`,
the `Codex94` unit tests, the Release build, DMG packaging and the `Codex94UI`
smoke scenarios.

## Cloud (Linux) sessions

Claude Code cloud environments are Linux containers without Xcode.

- Never report `xcodebuild` build/test, `release_check.sh`, DMG packaging or UI
  smoke as passed from a cloud session; list them as pending CI.
- `script/tests/test_install.sh` sources `script/install.sh`, which relies on
  BSD `stat`/`mv` and `codesign`; treat it as macOS-only.
- Before `security_check.sh`, run `git rev-parse --is-shallow-repository`. If it
  prints `true`, run `git fetch --unshallow` so the history scans cover every
  commit.
- Checks expected to run without Xcode, from the repository root:
  - `python3 -I script/tests/test_release_metadata.py`
  - `python3 -I script/tests/test_security_check.py`
  - `./script/security_check.sh` (needs ripgrep and git)
  - `jq empty Codex94/Localizable.xcstrings`
  - `python3 -I -c "import plistlib; plistlib.load(open('Codex94/Info.plist', 'rb'))"`
    (stands in for `plutil -lint`)
  - `git diff HEAD --check --`
- Report each check that ran separately, and name every skipped check as
  pending rather than passed.
