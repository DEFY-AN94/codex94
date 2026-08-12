#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Codex94.xcodeproj"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData-ReleaseCheck"
APP="$DERIVED_DATA/Build/Products/Release/Codex94.app"
ENTITLEMENTS="$DERIVED_DATA/Codex94-Release.entitlements.plist"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFT_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"

for required_command in git plutil jq rg xcodebuild codesign; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Release check failed: required command '$required_command' is unavailable." >&2
    exit 1
  fi
done

cd "$ROOT_DIR"
git diff HEAD --check --
PREVIOUS_TAG="$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)"
if [[ -n "$PREVIOUS_TAG" ]]; then
  git diff "$PREVIOUS_TAG"..HEAD --check --
else
  git diff-tree --check --root -r HEAD --
fi
plutil -lint Codex94/Info.plist >/dev/null
jq empty Codex94/Localizable.xcstrings
./script/security_check.sh

xcodebuild \
  -project "$PROJECT" \
  -scheme Codex94 \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  test

xcodebuild \
  -project "$PROJECT" \
  -scheme Codex94 \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  build

codesign --verify --deep --strict --verbose=2 "$APP"
if ! codesign -dvv "$APP" 2>&1 | rg -q 'flags=.*runtime'; then
  echo "Release check failed: Hardened Runtime signature is missing." >&2
  exit 1
fi

codesign -d --entitlements :- "$APP" >"$ENTITLEMENTS" 2>/dev/null
if [[ -s "$ENTITLEMENTS" ]] &&
  plutil -extract 'com\.apple\.security\.get-task-allow' raw -o /dev/null "$ENTITLEMENTS" 2>/dev/null; then
  echo "Release check failed: Release app allows debugger attachment." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
echo "Release check passed for Codex94 $VERSION ($BUILD)."
