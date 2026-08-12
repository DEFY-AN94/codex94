#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Codex94"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Codex94.xcodeproj"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData-Release"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
STAGING_APP="$INSTALL_DIR/.$APP_NAME.installing.app"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFT_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"

"$ROOT_DIR/script/security_check.sh"
mkdir -p "$ROOT_DIR/.build/ModuleCache"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  build

mkdir -p "$INSTALL_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$STAGING_APP"
/usr/bin/ditto "$BUILT_APP" "$STAGING_APP"
/usr/bin/codesign --force --deep --options runtime --sign - "$STAGING_APP"
rm -rf "$INSTALLED_APP"
mv "$STAGING_APP" "$INSTALLED_APP"

if [[ "${1:-}" != "--no-launch" ]]; then
  /usr/bin/open -n "$INSTALLED_APP"
fi

echo "Installed $INSTALLED_APP"
