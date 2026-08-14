#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Codex94"
FORBIDDEN='URLSession|HTTPCookie|backend-api/codex/usage|browser-cookie|auth[.]json|Authorization[^\n]*Bearer|SecItemCopyMatching|kSecClassGenericPassword'
SECRET_PATTERN='-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----|sk-(proj-|admin-|svcacct-)?[A-Za-z0-9_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|glpat-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{20,}|npm_[A-Za-z0-9]{30,}|pypi-[A-Za-z0-9_-]{30,}|hf_[A-Za-z0-9]{30,}|[sr]k_live_[A-Za-z0-9]{20,}|whsec_[A-Za-z0-9]{20,}|SG[.][A-Za-z0-9_-]{16,}[.][A-Za-z0-9_-]{16,}|Bearer[[:space:]]+[A-Za-z0-9._~+/-]{20,}|eyJ[A-Za-z0-9_-]{10,}[.][A-Za-z0-9_-]{10,}[.][A-Za-z0-9_-]{10,}|[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]/:@]+:[^[:space:]/@]+@|(api[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token|password|passwd)[[:space:]]*[:=][^[:alnum:]]{0,3}[A-Za-z0-9_./+=-]{16,}'
PII_PATTERN='(/Users/[A-Za-z0-9._/-]+)|(/(private/)?var/folders/[A-Za-z0-9._/-]+)|([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,})'
ALLOWED_FIXTURE_PII='^(/Users/(example|private|another-person)(/[A-Za-z0-9._/-]+)?|(user|test|private|account)@example[.]com)$'

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

current_secret_matches="$(
  rg -n -I --hidden \
  --glob '!.git/**' \
  --glob '!.build/**' \
  --glob '!script/security_check.sh' \
  -- \
  "$SECRET_PATTERN" . || true
)"
if [[ -n "$current_secret_matches" ]]; then
  printf '%s\n' "$current_secret_matches" >&2
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

current_pii_matches="$(
  rg -n -I -i --hidden \
    --glob '!.git/**' \
    --glob '!.build/**' \
    --glob '!Codex94Tests/**' \
    --glob '!Codex94/Assets.xcassets/**' \
    --glob '!script/security_check.sh' \
    -- "$PII_PATTERN" . | rg -v 'git@github[.]com' || true
)"
if [[ -n "$current_pii_matches" ]]; then
  printf '%s\n' "$current_pii_matches" >&2
  echo "Security check failed: machine path or email found outside approved fixtures." >&2
  exit 1
fi

fixture_pii="$(
  rg -o -I -i --no-filename -- "$PII_PATTERN" Codex94Tests | sort -u || true
)"
unexpected_fixture_pii="$(
  if [[ -n "$fixture_pii" ]]; then
    printf '%s\n' "$fixture_pii" | rg -v "$ALLOWED_FIXTURE_PII" || true
  fi
)"
if [[ -n "$unexpected_fixture_pii" ]]; then
  printf '%s\n' "$unexpected_fixture_pii" >&2
  echo "Security check failed: unapproved identity fixture found in tests." >&2
  exit 1
fi

history_pii_matches="$(
  while IFS= read -r commit; do
    git grep -n -I -i -E -e "$PII_PATTERN" "$commit" -- \
      . \
      ':(exclude)Codex94Tests/**' \
      ':(exclude)Codex94/Assets.xcassets/**' \
      ':(exclude)script/security_check.sh' | rg -v 'git@github[.]com' || true
  done < <(git rev-list --all)
)"
if [[ -n "$history_pii_matches" ]]; then
  printf '%s\n' "$history_pii_matches" >&2
  echo "Security check failed: machine path or email exists in Git history." >&2
  exit 1
fi

history_fixture_pii="$(
  while IFS= read -r commit; do
    git grep -h -I -i -o -E -e "$PII_PATTERN" "$commit" -- Codex94Tests || true
  done < <(git rev-list --all) | sort -u
)"
unexpected_history_fixture_pii="$(
  if [[ -n "$history_fixture_pii" ]]; then
    printf '%s\n' "$history_fixture_pii" | rg -v "$ALLOWED_FIXTURE_PII" || true
  fi
)"
if [[ -n "$unexpected_history_fixture_pii" ]]; then
  printf '%s\n' "$unexpected_history_fixture_pii" >&2
  echo "Security check failed: unapproved identity fixture exists in Git history." >&2
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
