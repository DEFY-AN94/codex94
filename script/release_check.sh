#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT="$ROOT_DIR/Codex94.xcodeproj"
BUILD_ROOT="$ROOT_DIR/.build"
DERIVED_DATA="$BUILD_ROOT/DerivedData-ReleaseCheck"
MODULE_CACHE="$BUILD_ROOT/ModuleCache"
APP="$DERIVED_DATA/Build/Products/Release/Codex94.app"
VALIDATED_BUILD_ROOT=""
DISTRIBUTION_ROOT=""

fail() {
  echo "Release check failed: $*" >&2
  exit 1
}

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

for required_command in git jq rg; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    fail "required command '$required_command' is unavailable."
  fi
done
for required_tool in \
  /usr/bin/xcode-select \
  /usr/bin/xcodebuild \
  /usr/bin/plutil \
  /usr/bin/python3 \
  /usr/bin/dirname \
  /usr/libexec/PlistBuddy \
  /bin/bash \
  /bin/mkdir; do
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
METADATA_COMMAND=(/usr/bin/python3 -I "$ROOT_DIR/script/release_metadata.py")
if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  [[ -n "${GITHUB_SHA:-}" ]] || fail "CI must supply its tested commit SHA."
  METADATA_COMMAND+=(--revision "$GITHUB_SHA")
fi
METADATA_JSON="$("${METADATA_COMMAND[@]}")" ||
  fail "could not read the App target version/build."
EXPECTED_VERSION="$(jq -er '.version' <<<"$METADATA_JSON")"
EXPECTED_BUILD="$(jq -er '.build' <<<"$METADATA_JSON")"
/usr/bin/python3 -I "$ROOT_DIR/script/tests/test_release_metadata.py"
/bin/bash "$ROOT_DIR/script/tests/test_install.sh"
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
[[ "$VERSION" == "$EXPECTED_VERSION" ]] || fail "Release App version is $VERSION; expected $EXPECTED_VERSION."
[[ "$BUILD" == "$EXPECTED_BUILD" ]] || fail "Release App build is $BUILD; expected $EXPECTED_BUILD."

# package_dmg.sh owns the complete App verifier. Its create path checks this
# exact built App and the mounted payload, including both architecture slices.

resolve_distribution_root
./script/package_dmg.sh create "$APP" "$DISTRIBUTION_ROOT"

echo "Release check passed for Codex94 $VERSION ($BUILD): Universal App and unsigned DMG candidate verified."
