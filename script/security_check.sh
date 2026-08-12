#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Codex94"
FORBIDDEN='URLSession|HTTPCookie|backend-api/codex/usage|browser-cookie|auth[.]json|Authorization[^\n]*Bearer|SecItemCopyMatching|kSecClassGenericPassword'

if rg -n --glob '*.swift' "$FORBIDDEN" "$SOURCE_DIR"; then
  echo "Security check failed: prohibited credential or direct-HTTP pattern found." >&2
  exit 1
fi

if ! rg -q '"-s", "read-only", "-a", "untrusted", "app-server", "--stdio"' \
  "$SOURCE_DIR/Services/CodexAppServerClient.swift"; then
  echo "Security check failed: hardened app-server arguments changed." >&2
  exit 1
fi

echo "Static security check passed."

