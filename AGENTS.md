# Codex94 development

Project rules live in `CONTRIBUTING.md`, `SECURITY.md`, `PRIVACY.md`, and
`docs/RELEASING.md`. Read the applicable rules before changing the project.

## Session preparation

At the start of a task in this repository, run
`python3 -I script/codex_prepare.py` from the repository root. It does nothing
when the checkout is not shallow and otherwise attempts to fetch missing
history from `origin`. On failure, report the limitation and resolve Git access
before claiming a history scan passed. Never use `--allow-shallow-history` for
development or release validation; that flag is reserved for the source
installer's explicitly limited scan.

Codex local sessions also have a project `SessionStart` hook. Configure Codex
Cloud with the repository's `codex-project-start` skill as its Start skill;
see `docs/CODEX.md`. Do not assume local hooks run in cloud orchestration.
Claude's `.claude/` configuration is independent and must not be reused as a
Codex hook.

## Validation

On all supported development hosts, run focused script tests as applicable:

- `python3 -I script/tests/test_codex_prepare.py`
- `python3 -I script/tests/test_security_check.py`
- `python3 -I script/tests/test_release_metadata.py`
- `./script/security_check.sh`
- `git diff --check`

The macOS/Xcode release gate is `./script/release_check.sh`. Linux/cloud hosts
cannot validate the App build, hosted unit tests, DMG packaging, installer
transactions, or UI smokes. Report those as pending macOS CI rather than passed.
Use synthetic fixtures; do not invoke real provider CLIs or modify an installed
App to validate documentation or session preparation.

Keep `README.md` and `README.zh-CN.md` synchronized. Describe current features
there and record version-specific changes in `CHANGELOG.md`.
