#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT="$ROOT_DIR/Codex94.xcodeproj"
BUILD_ROOT="$ROOT_DIR/.build"
DERIVED_DATA="$BUILD_ROOT/DerivedData-ReleaseCheck"
MODULE_CACHE="$BUILD_ROOT/ModuleCache"
APP="$DERIVED_DATA/Build/Products/Release/Codex94.app"
EXPECTED_VERSION="0.2.0"
EXPECTED_BUILD="11"
EXPECTED_BUNDLE_ID="com.defyan94.codex94"
EXPECTED_MINIMUM_SYSTEM_VERSION="14.0"

ENTITLEMENTS_TEMP=""
VALIDATED_BUILD_ROOT=""
DISTRIBUTION_ROOT=""

fail() {
  echo "Release check failed: $*" >&2
  exit 1
}

cleanup() {
  local exit_status=$?
  trap - EXIT
  if [[ -n "$ENTITLEMENTS_TEMP" && -f "$ENTITLEMENTS_TEMP" ]]; then
    /bin/rm -f "$ENTITLEMENTS_TEMP"
  fi
  exit "$exit_status"
}

trap cleanup EXIT

physical_directory() {
  (cd "$1" 2>/dev/null && pwd -P)
}

trim_trailing_slashes() {
  local path="$1"
  while [[ "$path" != "/" && "$path" == */ ]]; do
    path="${path%/}"
  done
  printf '%s\n' "$path"
}

is_strict_descendant() {
  local candidate="$1"
  local base="$2"

  [[ "$candidate" != "$base" ]] || return 1
  case "$candidate" in
    "$base"/*) return 0 ;;
    *) return 1 ;;
  esac
}

prepare_build_root() {
  local build_root="$BUILD_ROOT"
  local build_physical

  if [[ ! -e "$build_root" && ! -L "$build_root" ]]; then
    /bin/mkdir "$build_root" || fail "could not create the exact project .build directory."
  fi
  [[ -d "$build_root" ]] || fail "project .build must be a directory."
  [[ ! -L "$build_root" ]] || fail "project .build must not be a symlink."
  build_physical="$(physical_directory "$build_root")" ||
    fail "project .build could not be resolved physically."
  [[ "$build_physical" == "$BUILD_ROOT" ]] ||
    fail "project .build does not resolve to the expected directory inside the repository."
  VALIDATED_BUILD_ROOT="$build_physical"
}

prepare_build_subdirectory() {
  local path="$1"
  local label="$2"
  local physical

  [[ -n "$VALIDATED_BUILD_ROOT" ]] || fail "project .build must be validated first."
  is_strict_descendant "$path" "$VALIDATED_BUILD_ROOT" ||
    fail "$label must be a strict descendant of the validated project .build directory."
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    /bin/mkdir "$path" || fail "could not create the exact $label directory."
  fi
  [[ -d "$path" ]] || fail "$label must be a directory."
  [[ ! -L "$path" ]] || fail "$label must not be a symlink."
  physical="$(physical_directory "$path")" || fail "$label could not be resolved physically."
  [[ "$physical" == "$path" ]] ||
    fail "$label does not resolve to its exact location inside the project .build directory."
}

resolve_distribution_root() {
  local build_root="$VALIDATED_BUILD_ROOT"
  local distribution_root
  local distribution_physical
  local release_runs_root
  local release_runs_physical

  [[ -n "$build_root" ]] || fail "project .build must be validated before resolving distribution output."
  if [[ -n "${CODEX94_DISTRIBUTION_ROOT+x}" ]]; then
    distribution_root="$(trim_trailing_slashes "${CODEX94_DISTRIBUTION_ROOT}")"
    case "$distribution_root" in
      /*) ;;
      *) fail "CODEX94_DISTRIBUTION_ROOT must be absolute." ;;
    esac
    [[ -d "$distribution_root" ]] ||
      fail "custom CODEX94_DISTRIBUTION_ROOT must already exist; release_check.sh does not create custom parents."
    [[ ! -L "$distribution_root" ]] || fail "custom CODEX94_DISTRIBUTION_ROOT must not be a symlink."
    distribution_physical="$(physical_directory "$distribution_root")" ||
      fail "custom CODEX94_DISTRIBUTION_ROOT could not be resolved physically."

    release_runs_root="$build_root/ReleaseRuns"
    [[ -d "$release_runs_root" && ! -L "$release_runs_root" ]] ||
      fail "custom runs require a pre-created, non-symlink .build/ReleaseRuns directory."
    release_runs_physical="$(physical_directory "$release_runs_root")" ||
      fail ".build/ReleaseRuns could not be resolved physically."
    [[ "$release_runs_physical" == "$release_runs_root" ]] ||
      fail ".build/ReleaseRuns must remain inside the real project .build directory."
    is_strict_descendant "$distribution_physical" "$release_runs_physical" ||
      fail "custom CODEX94_DISTRIBUTION_ROOT must be a unique pre-created directory inside .build/ReleaseRuns."
  else
    distribution_root="$build_root/Distribution"
    if [[ -e "$distribution_root" || -L "$distribution_root" ]]; then
      [[ -d "$distribution_root" && ! -L "$distribution_root" ]] ||
        fail "default .build/Distribution exists but is not a real directory."
    else
      /bin/mkdir -p "$distribution_root" || fail "could not create the exact default .build/Distribution directory."
    fi
    distribution_physical="$(physical_directory "$distribution_root")" ||
      fail "default .build/Distribution could not be resolved physically."
    [[ "$distribution_physical" == "$build_root/Distribution" ]] ||
      fail "default .build/Distribution escaped the project .build directory."
  fi

  DISTRIBUTION_ROOT="$distribution_physical"
}

validate_exact_architectures() {
  local executable="$1"
  local archs
  local arch
  local count=0
  local has_arm64=0
  local has_x86_64=0

  [[ -f "$executable" && -x "$executable" && ! -L "$executable" ]] ||
    fail "main executable is missing or not executable: $executable"
  archs="$(/usr/bin/lipo -archs "$executable")" ||
    fail "main executable is not a readable Mach-O file."
  for arch in $archs; do
    count=$((count + 1))
    case "$arch" in
      arm64) has_arm64=$((has_arm64 + 1)) ;;
      x86_64) has_x86_64=$((has_x86_64 + 1)) ;;
      *) fail "unexpected Release architecture '$arch'." ;;
    esac
  done
  [[ "$count" -eq 2 && "$has_arm64" -eq 1 && "$has_x86_64" -eq 1 ]] ||
    fail "Release architectures must be exactly arm64 and x86_64 (found: $archs)."
}

validate_entitlements_for_architecture() {
  local app_path="$1"
  local arch="$2"
  local entitlements_json

  ENTITLEMENTS_TEMP="$(/usr/bin/mktemp "$DERIVED_DATA/Codex94-$arch-entitlements.XXXXXX")" ||
    fail "could not create a temporary $arch entitlement file."
  if ! /usr/bin/codesign -d --arch "$arch" --entitlements - --xml "$app_path" \
    >"$ENTITLEMENTS_TEMP"; then
    fail "could not read the $arch entitlement state."
  fi
  if [[ -s "$ENTITLEMENTS_TEMP" ]]; then
    /usr/bin/plutil -lint "$ENTITLEMENTS_TEMP" >/dev/null ||
      fail "$arch entitlement output is not a valid property list."
    entitlements_json="$(/usr/bin/plutil -convert json -o - "$ENTITLEMENTS_TEMP")" ||
      fail "$arch entitlement output could not be normalized."
    [[ "$entitlements_json" == "{}" ]] ||
      fail "$arch contains one or more entitlements; Release requires an empty dictionary."
  fi
  /bin/rm -f "$ENTITLEMENTS_TEMP"
  ENTITLEMENTS_TEMP=""
}

validate_signature_for_architecture() {
  local app_path="$1"
  local arch="$2"
  local details
  local line
  local signature_ok=0
  local team_ok=0
  local runtime_ok=0
  local flags

  details="$(/usr/bin/codesign -dvvv --arch "$arch" "$app_path" 2>&1)" ||
    fail "could not inspect the $arch code signature."
  while IFS= read -r line; do
    case "$line" in
      Signature=adhoc) signature_ok=1 ;;
      TeamIdentifier="not set") team_ok=1 ;;
      CodeDirectory*"flags="*"("*")"*)
        flags="${line#*\(}"
        flags="${flags%%\)*}"
        case ",$flags," in
          *,runtime,*) runtime_ok=1 ;;
        esac
        ;;
    esac
  done <<<"$details"

  [[ "$signature_ok" -eq 1 ]] || fail "$arch signature is not ad-hoc."
  [[ "$runtime_ok" -eq 1 ]] || fail "$arch signature is missing Hardened Runtime."
  [[ "$team_ok" -eq 1 ]] || fail "$arch signature unexpectedly contains a Team ID."
  validate_entitlements_for_architecture "$app_path" "$arch"
}

for required_command in git jq rg; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    fail "required command '$required_command' is unavailable."
  fi
done
for required_tool in \
  /usr/bin/xcode-select \
  /usr/bin/xcodebuild \
  /usr/bin/codesign \
  /usr/bin/lipo \
  /usr/bin/plutil \
  /usr/bin/mktemp \
  /usr/bin/dirname \
  /usr/libexec/PlistBuddy \
  /bin/mkdir \
  /bin/rm; do
  [[ -x "$required_tool" ]] || fail "required system tool '$required_tool' is unavailable."
done
[[ -x "$ROOT_DIR/script/package_dmg.sh" ]] || fail "script/package_dmg.sh is missing or not executable."

prepare_build_root
prepare_build_subdirectory "$DERIVED_DATA" "Release DerivedData"
prepare_build_subdirectory "$MODULE_CACHE" "module cache"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE"

XCODE_SELECT_PATH="$(/usr/bin/xcode-select -p)" || fail "xcode-select could not report its developer directory."
[[ -n "$XCODE_SELECT_PATH" ]] || fail "xcode-select reported an empty developer directory."
echo "xcode-select developer directory: $XCODE_SELECT_PATH"
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  echo "Caller DEVELOPER_DIR: $DEVELOPER_DIR"
else
  echo "Caller DEVELOPER_DIR: not set; xcodebuild will use the current xcode-select selection."
fi
/usr/bin/xcodebuild -version

cd "$ROOT_DIR"
git diff HEAD --check --
PREVIOUS_TAG="$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)"
if [[ -n "$PREVIOUS_TAG" ]]; then
  git diff "$PREVIOUS_TAG"..HEAD --check --
else
  git diff-tree --check --root -r HEAD --
fi
/usr/bin/plutil -lint Codex94/Info.plist >/dev/null
jq empty Codex94/Localizable.xcstrings
./script/security_check.sh

/usr/bin/xcodebuild \
  -project "$PROJECT" \
  -scheme Codex94 \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  test

/usr/bin/xcodebuild \
  -project "$PROJECT" \
  -scheme Codex94 \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  build

INFO_PLIST="$APP/Contents/Info.plist"
[[ -f "$INFO_PLIST" && ! -L "$INFO_PLIST" ]] || fail "Release App Info.plist is missing or is a symlink."
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")" ||
  fail "Release App version is missing."
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")" ||
  fail "Release App build is missing."
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")" ||
  fail "Release App bundle identifier is missing."
MINIMUM_SYSTEM_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")" ||
  fail "Release App minimum system version is missing."
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")" ||
  fail "Release App executable name is missing."
case "$EXECUTABLE_NAME" in
  *$'\n'*) fail "Release App executable name contains a newline." ;;
esac

[[ "$VERSION" == "$EXPECTED_VERSION" ]] || fail "Release App version is $VERSION; expected $EXPECTED_VERSION."
[[ "$BUILD" == "$EXPECTED_BUILD" ]] || fail "Release App build is $BUILD; expected $EXPECTED_BUILD."
[[ "$BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] || fail "Release App bundle identifier is $BUNDLE_ID; expected $EXPECTED_BUNDLE_ID."
[[ "$MINIMUM_SYSTEM_VERSION" == "$EXPECTED_MINIMUM_SYSTEM_VERSION" ]] ||
  fail "Release App minimum system version is $MINIMUM_SYSTEM_VERSION; expected $EXPECTED_MINIMUM_SYSTEM_VERSION."
[[ -n "$EXECUTABLE_NAME" && "$EXECUTABLE_NAME" == "${EXECUTABLE_NAME##*/}" ]] ||
  fail "Release App executable name is unsafe."

EXECUTABLE="$APP/Contents/MacOS/$EXECUTABLE_NAME"
validate_exact_architectures "$EXECUTABLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 --all-architectures "$APP" ||
  fail "Release App code-signature integrity verification failed."
for arch in arm64 x86_64; do
  validate_signature_for_architecture "$APP" "$arch"
done

resolve_distribution_root
./script/package_dmg.sh create "$APP" "$DISTRIBUTION_ROOT"

echo "Release check passed for Codex94 $VERSION ($BUILD): Universal App and unsigned DMG candidate verified."
