#!/usr/bin/env bash
set -euo pipefail

# Claude Code cloud sessions start from a shallow clone, while
# script/security_check.sh scans every commit. Complete the history before any
# check runs. Local Claude Code sessions exit here without touching the clone.
if [[ "${CLAUDE_CODE_REMOTE:-}" != "true" ]]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

if [[ "$(git rev-parse --is-shallow-repository)" != "true" ]]; then
  exit 0
fi

# SessionStart stdout is added to Claude's context, so report either outcome
# there. A failed fetch must not block the session.
if git fetch --unshallow --quiet origin; then
  echo "SessionStart hook: fetched the full Git history (git fetch --unshallow)."
else
  echo "SessionStart hook: git fetch --unshallow failed; the clone is still shallow. Run it before ./script/security_check.sh."
fi
