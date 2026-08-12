#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Codex94"
FORBIDDEN='URLSession|HTTPCookie|backend-api/codex/usage|browser-cookie|auth[.]json|Authorization[^\n]*Bearer|SecItemCopyMatching|kSecClassGenericPassword'
SECRET_PATTERN='-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|sk-(proj-|admin-|svcacct-)?[A-Za-z0-9_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{20,}'

for required_command in rg git; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Security check failed: required command '$required_command' is unavailable." >&2
    exit 1
  fi
done

cd "$ROOT_DIR"

if rg -l --glob '*.swift' "$FORBIDDEN" "$SOURCE_DIR"; then
  echo "Security check failed: prohibited credential or direct-HTTP pattern found." >&2
  exit 1
fi

if rg -l --hidden \
  --glob '!.git/**' \
  --glob '!.build/**' \
  --glob '!script/security_check.sh' \
  -- \
  "$SECRET_PATTERN" "$ROOT_DIR"; then
  echo "Security check failed: possible committed credential or private key found." >&2
  exit 1
fi

history_matches="$(
  while IFS= read -r commit; do
    git grep -l -I -E -e "$SECRET_PATTERN" "$commit" -- \
      . ':(exclude)script/security_check.sh' || true
  done < <(git rev-list --all)
)"
if [[ -n "$history_matches" ]]; then
  printf '%s\n' "$history_matches" >&2
  echo "Security check failed: possible credential or private key exists in Git history." >&2
  exit 1
fi

if ! rg -q '"-s", "read-only", "-a", "untrusted", "app-server", "--stdio"' \
  "$SOURCE_DIR/Services/CodexAppServerClient.swift"; then
  echo "Security check failed: hardened app-server arguments changed." >&2
  exit 1
fi

if ! rg -q 'ENABLE_HARDENED_RUNTIME = YES;' "$ROOT_DIR/Codex94.xcodeproj/project.pbxproj"; then
  echo "Security check failed: Hardened Runtime is not enabled." >&2
  exit 1
fi

if ! rg -q 'ENABLE_APP_SANDBOX = NO;' "$ROOT_DIR/Codex94.xcodeproj/project.pbxproj"; then
  echo "Security check failed: the documented subprocess sandbox boundary changed." >&2
  exit 1
fi

if rg -q 'let[[:space:]]+(email|account)(:|[[:space:]])' \
  "$SOURCE_DIR/Services/SnapshotCache.swift"; then
  echo "Security check failed: identity data must not enter the quota cache." >&2
  exit 1
fi

echo "Static security check passed."
