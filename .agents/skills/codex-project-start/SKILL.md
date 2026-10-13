---
name: codex-project-start
description: Prepare this Codex94 repository at the start of a Codex Cloud task, or when asked to initialize or repair its development environment. Check Git history before running project security scans.
---

# Codex94 startup

Use this skill as the Codex Cloud environment's **Start skill**. It is a Codex
development helper, not a Claude Code hook or an App runtime feature.

1. Locate the Codex94 checkout containing this skill. Read its `AGENTS.md` and
   `docs/CODEX.md`. Run commands from that repository root, including when the
   environment contains multiple repositories.
2. Check that `git` and Python 3 are available. Run
   `python3 -I script/codex_prepare.py` without `--hook`. A nonzero exit means
   preparation is incomplete. Report the failure, diagnose the environment's
   access to `origin`, and retry only after resolving it. Never bypass the
   security scanner's shallow-history guard.
3. Verify `git rev-parse --is-shallow-repository` returns `false`. This covers
   the history available through the configured fetch refs, not unrequested
   remote branches. Do not change remotes, credentials, branches, or tags to
   make preparation succeed.
4. Check that `rg` and `jq` are available before project checks. If tools are
   missing, report them for the cloud environment's Install script; use the
   environment's approved package setup rather than changing authentication or
   network controls.
5. State whether preparation succeeded and which host-dependent checks are
   available. On Linux, leave Xcode, App tests, packaging, installer transactions,
   and UI smoke validation to macOS CI. Do not start the App or real provider
   CLIs as part of startup.

Repeat the preparation check after the task changes checkout or receives a
fresh repository snapshot. A cloud environment's published filesystem does not
prove the history state of every later task.
