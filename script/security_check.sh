#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Codex94"
FORBIDDEN='account/rateLimitResetCredit/consume|HTTPCookie|backend-api/codex/usage|browser-cookie|auth[.]json|Authorization[^\n]*Bearer|SecItemCopyMatching|kSecClassGenericPassword|SecItem(Add|Update|Delete)|SecKeychain|URLCredentialStorage[.]shared'
SECRET_PATTERN='-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----|sk-(proj-|admin-|svcacct-)?[A-Za-z0-9_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|glpat-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{20,}|npm_[A-Za-z0-9]{30,}|pypi-[A-Za-z0-9_-]{30,}|hf_[A-Za-z0-9]{30,}|[sr]k_live_[A-Za-z0-9]{20,}|whsec_[A-Za-z0-9]{20,}|SG[.][A-Za-z0-9_-]{16,}[.][A-Za-z0-9_-]{16,}|Bearer[[:space:]]+[A-Za-z0-9._~+/-]{20,}|eyJ[A-Za-z0-9_-]{10,}[.][A-Za-z0-9_-]{10,}[.][A-Za-z0-9_-]{10,}|[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]/:@]+:[^[:space:]/@]+@|(api[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token|password|passwd)[[:space:]]*[:=][^[:alnum:]]{0,3}[A-Za-z0-9_./+=-]{16,}'
PII_PATTERN='(/Users/[A-Za-z0-9._/-]+)|(/(private/)?var/folders/[A-Za-z0-9._/-]+)|([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,})'
# Synthetic identities for account-switch/late-response tests, plus the exact
# trust-alias fixture path. This allowlist applies only to tests, including history.
ALLOWED_FIXTURE_PII='^(/Users/(example|private|another-person)(/[A-Za-z0-9._/-]+)?|/Users/synthetic/runtime|(user|test|private|account|first|late|second)@example[.]com)$'

for required_command in rg git sort python3; do
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

# Two exact HTTP implementation files; neither exception bypasses credential,
# cookie, reset-consumption, current-tree or Git-history secret scans below.
network_matches="$(scan_matches "network-client scan could not be completed" \
  rg -l --glob '*.swift' 'URLSession' "$SOURCE_DIR")"
while IFS= read -r source_file; do
  [[ -z "$source_file" || "$source_file" == "$SOURCE_DIR/Services/AppUpdateClient.swift" \
    || "$source_file" == "$SOURCE_DIR/Services/ClaudeOAuthUsageClient.swift" ]] || {
    echo "Security check failed: direct networking outside approved HTTP clients: $source_file" >&2
    exit 1
  }
done <<< "$network_matches"

# A narrow source contract complements the client's injected transport tests.
# This is deliberately not a whole-file credential exemption: only authorize's
# exact guarded header assignment is admitted. Changes to these boundaries need
# a corresponding explicit policy review, not a new path/directory wildcard.
python3 -I - "$SOURCE_DIR" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
client_path = root / "Services/ClaudeOAuthUsageClient.swift"
credential_path = root / "Models/ClaudeOAuthTypes.swift"
header_pattern = re.compile(r'"Authorization"|"Bearer(?:\s|"|\\)', re.IGNORECASE)

def fail(message):
    raise SystemExit("Security check failed: " + message)

def normalized(source):
    return "\n".join(line.strip() for line in source.splitlines()
                     if line.strip() and not line.lstrip().startswith("//"))

authorize = normalized('''
    func authorize(_ request: inout URLRequest, now: Date) throws {
        guard ClaudeOAuthUsageClient.isAllowed(request) else { throw ClaudeOAuthIssue.invalidDestination }
        guard scopes.contains("user:profile") else { throw ClaudeOAuthIssue.insufficientScope }
        guard expiresAt.map({ $0 > now }) ?? true else { throw ClaudeOAuthIssue.expired }
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
    }
''')
for path in root.rglob("*.swift"):
    source = path.read_text(encoding="utf-8")
    if not header_pattern.search(source):
        continue
    stripped = normalized(source)
    if path != credential_path or stripped.count(authorize) != 1:
        fail("credential headers outside the guarded OAuth authorize operation: " + str(path.relative_to(root)))
    if header_pattern.search(stripped.replace(authorize, "", 1)):
        fail("additional credential header access outside OAuth authorize: " + str(path.relative_to(root)))

if client_path.exists() or credential_path.exists():
    if not client_path.is_file() or not credential_path.is_file():
        fail("OAuth HTTP boundary is incomplete")
    client = client_path.read_text(encoding="utf-8")
    compact = normalized(client)
    if normalized(credential_path.read_text(encoding="utf-8")).count(authorize) != 1:
        fail("OAuth credential destination/scope/expiry guard changed")
    urls = re.findall(r'https?://[^\s"\'<>]+', client)
    if urls != ["https://api.anthropic.com/api/oauth/usage", "https://api.anthropic.com/api/oauth/profile"]:
        fail("OAuth HTTP endpoint allowlist changed")
    allowed = normalized('''
    static func isAllowed(_ request: URLRequest) -> Bool {
        let maximumTimeout: TimeInterval
        switch request.url {
        case usageEndpoint: maximumTimeout = usageTimeout
        case profileEndpoint: maximumTimeout = profileTimeout
        default: return false
        }
        return request.httpMethod == "GET" && request.httpBody == nil && request.httpBodyStream == nil
            && request.timeoutInterval.isFinite && request.timeoutInterval > 0
            && request.timeoutInterval <= maximumTimeout
    }
    ''')
    if compact.count(allowed) != 1:
        fail("OAuth HTTP method/destination/budget validator changed")
    transport_entry = normalized('''
    func response(for request: URLRequest) async throws -> ClaudeOAuthHTTPResponse {
        guard ClaudeOAuthUsageClient.isAllowed(request) else { throw ClaudeOAuthIssue.invalidDestination }
        try Task.checkCancellation()
    ''')
    if compact.count(transport_entry) != 1:
        fail("OAuth transport destination guard changed")
    # Require exactly one reviewed assignment, so a later overriding write also
    # fails. The release checker remains anonymous via the header scan above.
    assignments = {
        "request.httpMethod": '"GET"',
        "request.httpShouldHandleCookies": "false",
        "configuration.urlCache": "nil",
        "configuration.httpCookieStorage": "nil",
        "configuration.urlCredentialStorage": "nil",
        "configuration.httpShouldSetCookies": "false",
        "configuration.requestCachePolicy": ".reloadIgnoringLocalCacheData",
    }
    for target, expected in assignments.items():
        values = re.findall(re.escape(target) + r'\s*=(?!=)\s*([^\n]+)', compact)
        if values != [expected]:
            fail("OAuth GET/cache/cookie boundary changed: " + target)
    for required in [
        "static let usageTimeout: TimeInterval = 10", "static let profileTimeout: TimeInterval = 2",
        "let configuration = URLSessionConfiguration.ephemeral",
        "let session = URLSession(configuration: configuration, delegate: ClaudeOAuthSessionDelegate(), delegateQueue: nil)",
        "let (bytes, rawResponse) = try await session.bytes(for: request)",
        "completionHandler: @escaping (URLRequest?) -> Void) {\ncompletionHandler(nil)\n}",
    ]:
        if compact.count(required) != 1:
            fail("OAuth bounded ephemeral transport or redirect rejection changed")
    if len(re.findall(r'URLSession\s*\(', client)) != 1 or "URLSession.shared" in client:
        fail("additional OAuth URLSession transport is not approved")
PY

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

# Git administration is a directory in a checkout and a pointer file in a
# linked worktree. Neither form is source content.
current_secret_matches="$(
  scan_matches \
    "current-tree credential scan could not be completed" \
    rg -n -I --hidden \
      --glob '!.git' \
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
    --glob '!.git' \
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
