#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Codex94"
BUNDLE_ID="com.defyan94.codex94"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Codex94.xcodeproj"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFT_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
mkdir -p "$ROOT_DIR/.build/logs" "$ROOT_DIR/.build/ModuleCache"

if [[ "$MODE" == "--verify" || "$MODE" == "verify" ]]; then
  "$ROOT_DIR/script/security_check.sh"
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  build

if [[ "$MODE" == "--debug" || "$MODE" == "debug" ]]; then
  /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
else
  /usr/bin/codesign --force --deep --options runtime --sign - "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "Codex94 build, security check, and launch verification passed."
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
