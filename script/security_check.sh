#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Codex94"
FORBIDDEN='URLSession|HTTPCookie|backend-api/codex/usage|browser-cookie|auth[.]json|Authorization[^\n]*Bearer|SecItemCopyMatching|kSecClassGenericPassword'
SECRET_PATTERN='-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----|sk-(proj-|admin-|svcacct-)?[A-Za-z0-9_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|glpat-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{20,}|npm_[A-Za-z0-9]{30,}|pypi-[A-Za-z0-9_-]{30,}|hf_[A-Za-z0-9]{30,}|[sr]k_live_[A-Za-z0-9]{20,}|whsec_[A-Za-z0-9]{20,}|SG[.][A-Za-z0-9_-]{16,}[.][A-Za-z0-9_-]{16,}|Bearer[[:space:]]+[A-Za-z0-9._~+/-]{20,}|eyJ[A-Za-z0-9_-]{10,}[.][A-Za-z0-9_-]{10,}[.][A-Za-z0-9_-]{10,}|[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]/:@]+:[^[:space:]/@]+@|(api[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token|password|passwd)[[:space:]]*[:=][^[:alnum:]]{0,3}[A-Za-z0-9_./+=-]{16,}'
PII_PATTERN='(/Users/[A-Za-z0-9._/-]+)|(/(private/)?var/folders/[A-Za-z0-9._/-]+)|([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,})'
ALLOWED_FIXTURE_PII='^(/Users/(example|private|another-person)(/[A-Za-z0-9._/-]+)?|(user|test|private|account)@example[.]com)$'

for required_command in rg git sort; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Security check failed: required command '$required_command' is unavailable." >&2
    exit 1
  fi
done

scan_matches() {
  local label="$1"
  shift

  local output
  local status
  if output="$("$@")"; then
    printf '%s' "$output"
    return 0
  else
    status=$?
  fi

  if [[ "$status" -eq 1 ]]; then
    return 0
  fi

  echo "Security check failed: $label (scanner exit $status)." >&2
  return "$status"
}

filter_matches() {
  local input="$1"
  local label="$2"
  shift 2

  if [[ -z "$input" ]]; then
    return 0
  fi

  local output
  local status
  if output="$("$@" <<< "$input")"; then
    printf '%s' "$output"
    return 0
  else
    status=$?
  fi

  if [[ "$status" -eq 1 ]]; then
    return 0
  fi

  echo "Security check failed: $label (filter exit $status)." >&2
  return "$status"
}

sort_unique_lines() {
  local input="$1"
  local label="$2"

  if [[ -z "$input" ]]; then
    return 0
  fi

  local output
  local status
  if output="$(sort -u <<< "$input")"; then
    printf '%s' "$output"
    return 0
  else
    status=$?
  fi

  echo "Security check failed: $label (sort exit $status)." >&2
  return "$status"
}

append_matches() {
  local variable_name="$1"
  local matches="$2"

  if [[ -z "$matches" ]]; then
    return 0
  fi

  if [[ -n "${!variable_name}" ]]; then
    printf -v "$variable_name" '%s\n%s' "${!variable_name}" "$matches"
  else
    printf -v "$variable_name" '%s' "$matches"
  fi
}

cd "$ROOT_DIR"

forbidden_matches="$(
  scan_matches \
    "prohibited source-pattern scan could not be completed" \
    rg -l --glob '*.swift' "$FORBIDDEN" "$SOURCE_DIR"
)"
if [[ -n "$forbidden_matches" ]]; then
  printf '%s\n' "$forbidden_matches" >&2
  echo "Security check failed: prohibited credential or direct-HTTP pattern found." >&2
  exit 1
fi

current_secret_matches="$(
  scan_matches \
    "current-tree credential scan could not be completed" \
    rg -n -I --hidden \
      --glob '!.git/**' \
      --glob '!.build/**' \
      --glob '!script/security_check.sh' \
      -- \
      "$SECRET_PATTERN" .
)"
if [[ -n "$current_secret_matches" ]]; then
  printf '%s\n' "$current_secret_matches" >&2
  echo "Security check failed: possible committed credential or private key found." >&2
  exit 1
fi

if ! history_commits="$(git rev-list --all)"; then
  echo "Security check failed: Git history enumeration could not be completed." >&2
  exit 1
fi
if [[ -z "$history_commits" ]]; then
  echo "Security check failed: Git history enumeration returned no commits." >&2
  exit 1
fi

history_matches=""
while IFS= read -r commit; do
  [[ -n "$commit" ]] || continue
  commit_secret_matches="$(
    scan_matches \
      "credential history scan could not read commit $commit" \
      git grep -l -I -E -e "$SECRET_PATTERN" "$commit" -- \
        . ':(exclude)script/security_check.sh'
  )"
  append_matches history_matches "$commit_secret_matches"
done <<< "$history_commits"
if [[ -n "$history_matches" ]]; then
  printf '%s\n' "$history_matches" >&2
  echo "Security check failed: possible credential or private key exists in Git history." >&2
  exit 1
fi

current_pii_raw_matches="$(
  scan_matches \
    "current-tree privacy scan could not be completed" \
  rg -n -o -I -i --hidden \
    --glob '!.git/**' \
    --glob '!.build/**' \
    --glob '!Codex94Tests/**' \
    --glob '!Codex94/Assets.xcassets/**' \
    --glob '!script/security_check.sh' \
    -- "$PII_PATTERN" .
)"
current_pii_matches="$(
  filter_matches \
    "$current_pii_raw_matches" \
    "current-tree privacy allowlist filter could not be completed" \
    rg -v '(^|:)git@github[.]com$'
)"
if [[ -n "$current_pii_matches" ]]; then
  printf '%s\n' "$current_pii_matches" >&2
  echo "Security check failed: machine path or email found outside approved fixtures." >&2
  exit 1
fi

fixture_pii_raw="$(
  scan_matches \
    "test-fixture privacy scan could not be completed" \
    rg -o -I -i --no-filename -- "$PII_PATTERN" Codex94Tests
)"
fixture_pii="$(
  sort_unique_lines "$fixture_pii_raw" "test-fixture privacy results could not be sorted"
)"
unexpected_fixture_pii="$(
  filter_matches \
    "$fixture_pii" \
    "test-fixture privacy allowlist filter could not be completed" \
    rg -v "$ALLOWED_FIXTURE_PII"
)"
if [[ -n "$unexpected_fixture_pii" ]]; then
  printf '%s\n' "$unexpected_fixture_pii" >&2
  echo "Security check failed: unapproved identity fixture found in tests." >&2
  exit 1
fi

history_pii_matches=""
while IFS= read -r commit; do
  [[ -n "$commit" ]] || continue
  commit_pii_raw_matches="$(
    scan_matches \
      "privacy history scan could not read commit $commit" \
      git grep -n -o -I -i -E -e "$PII_PATTERN" "$commit" -- \
      . \
      ':(exclude)Codex94Tests/**' \
      ':(exclude)Codex94/Assets.xcassets/**' \
      ':(exclude)script/security_check.sh'
  )"
  commit_pii_matches="$(
    filter_matches \
      "$commit_pii_raw_matches" \
      "privacy history allowlist filter failed at commit $commit" \
      rg -v '(^|:)git@github[.]com$'
  )"
  append_matches history_pii_matches "$commit_pii_matches"
done <<< "$history_commits"
if [[ -n "$history_pii_matches" ]]; then
  printf '%s\n' "$history_pii_matches" >&2
  echo "Security check failed: machine path or email exists in Git history." >&2
  exit 1
fi

history_fixture_pii_raw=""
while IFS= read -r commit; do
  [[ -n "$commit" ]] || continue
  commit_fixture_pii="$(
    scan_matches \
      "test-fixture privacy history scan could not read commit $commit" \
      git grep -h -I -i -o -E -e "$PII_PATTERN" "$commit" -- Codex94Tests
  )"
  append_matches history_fixture_pii_raw "$commit_fixture_pii"
done <<< "$history_commits"
history_fixture_pii="$(
  sort_unique_lines \
    "$history_fixture_pii_raw" \
    "test-fixture privacy history results could not be sorted"
)"
unexpected_history_fixture_pii="$(
  filter_matches \
    "$history_fixture_pii" \
    "test-fixture privacy history allowlist filter could not be completed" \
    rg -v "$ALLOWED_FIXTURE_PII"
)"
if [[ -n "$unexpected_history_fixture_pii" ]]; then
  printf '%s\n' "$unexpected_history_fixture_pii" >&2
  echo "Security check failed: unapproved identity fixture exists in Git history." >&2
  exit 1
fi

if ! rg -q '"-s", "read-only", "-a", "never", "app-server", "--stdio"' \
  "$SOURCE_DIR/Services/CodexAppServerClient.swift"; then
  echo "Security check failed: hardened app-server arguments changed." >&2
  exit 1
fi

removed_policy_matches="$(
  scan_matches \
    "removed approval-policy scan could not be completed" \
    rg -n '"-a", "untrusted"' "$SOURCE_DIR"
)"
if [[ -n "$removed_policy_matches" ]]; then
  printf '%s\n' "$removed_policy_matches" >&2
  echo "Security check failed: removed Codex approval policy 'untrusted' is still used." >&2
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

identity_cache_matches="$(
  scan_matches \
    "quota-cache identity scan could not be completed" \
    rg -n 'let[[:space:]]+(email|account)(:|[[:space:]])' \
      "$SOURCE_DIR/Services/SnapshotCache.swift"
)"
if [[ -n "$identity_cache_matches" ]]; then
  printf '%s\n' "$identity_cache_matches" >&2
  echo "Security check failed: identity data must not enter the quota cache." >&2
  exit 1
fi

echo "Static security check passed."
