#!/usr/bin/env bash
set -euo pipefail

# Keep top-level allowlist checks honest: ordinary '*' globs must include hidden
# entries, and an empty directory must expand to an empty array.
shopt -s dotglob nullglob

SCRIPT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
EXPECTED_BUNDLE_ID="com.defyan94.codex94"
EXPECTED_MINIMUM_SYSTEM_VERSION="14.0"

LOCK_DIR=""
LOCK_OWNED=0
STAGING_DIR=""
TEMP_VERSION_DIR=""
VERIFY_TEMP_DIR=""
MOUNT_POINT=""
MOUNT_ACTIVE=0
ENTITLEMENTS_TEMP=""

fail() {
  echo "Codex94 DMG packaging failed: $*" >&2
  exit 1
}

remove_owned_tree() {
  local path="$1"
  local label="$2"

  [[ -n "$path" && "$path" != "/" && "$path" == /* ]] || return 1
  case "${path##*/}" in
    Codex94-package.*|Codex94-verify.*|.Codex94-*.tmp.*)
      /bin/rm -rf "$path"
      ;;
    *)
      echo "Codex94 DMG cleanup warning: refusing unexpected $label path '$path'." >&2
      return 1
      ;;
  esac
}

cleanup() {
  local exit_status=$?
  local remove_verify_temp=1

  trap - EXIT HUP INT TERM
  set +e

  if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    if [[ "$MOUNT_ACTIVE" -eq 1 ]]; then
      /usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1
    fi
    if ! /bin/rmdir "$MOUNT_POINT" >/dev/null 2>&1; then
      remove_verify_temp=0
      echo "Codex94 DMG cleanup warning: mountpoint '$MOUNT_POINT' was not removed." >&2
    fi
  fi

  if [[ "$remove_verify_temp" -eq 1 && -n "$VERIFY_TEMP_DIR" && -d "$VERIFY_TEMP_DIR" ]]; then
    remove_owned_tree "$VERIFY_TEMP_DIR" "verification directory"
  fi
  if [[ -n "$ENTITLEMENTS_TEMP" && -f "$ENTITLEMENTS_TEMP" ]]; then
    /bin/rm -f "$ENTITLEMENTS_TEMP"
  fi
  if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
    remove_owned_tree "$STAGING_DIR" "staging directory"
  fi
  if [[ -n "$TEMP_VERSION_DIR" && -d "$TEMP_VERSION_DIR" ]]; then
    remove_owned_tree "$TEMP_VERSION_DIR" "temporary version directory"
  fi
  if [[ "$LOCK_OWNED" -eq 1 && -n "$LOCK_DIR" && -d "$LOCK_DIR" ]]; then
    /bin/rmdir "$LOCK_DIR" >/dev/null 2>&1 ||
      echo "Codex94 DMG cleanup warning: lock '$LOCK_DIR' was not empty." >&2
  fi

  exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
  printf '%s\n' \
    'Usage:' \
    '  script/package_dmg.sh create APP_PATH OUTPUT_ROOT' \
    '  script/package_dmg.sh verify DMG_PATH CHECKSUM_PATH EXPECTED_VERSION EXPECTED_BUILD' >&2
}

require_tools() {
  local tool
  for tool in \
    /usr/bin/ditto \
    /usr/bin/hdiutil \
    /usr/bin/codesign \
    /usr/bin/find \
    /usr/bin/grep \
    /usr/bin/lipo \
    /usr/bin/nm \
    /usr/bin/shasum \
    /usr/bin/plutil \
    /usr/libexec/PlistBuddy \
    /usr/bin/mktemp \
    /usr/bin/dirname \
    /usr/bin/readlink \
    /usr/bin/stat \
    /usr/bin/wc \
    /bin/ln \
    /bin/mkdir \
    /bin/mv \
    /bin/rm \
    /bin/rmdir; do
    [[ -x "$tool" ]] || fail "required system tool '$tool' is unavailable."
  done
}

is_semantic_version() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

is_positive_integer() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

trim_trailing_slashes() {
  local path="$1"
  while [[ "$path" != "/" && "$path" == */ ]]; do
    path="${path%/}"
  done
  printf '%s\n' "$path"
}

physical_directory() {
  (cd "$1" 2>/dev/null && pwd -P)
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

assert_no_newline() {
  case "$1" in
    *$'\n'*) fail "$2 contains a newline." ;;
  esac
}

validate_output_root() {
  local output_root
  local output_physical
  local root_build="$ROOT_DIR/.build"
  local root_build_physical=""
  local tmp_physical=""
  local allowed=0

  output_root="$(trim_trailing_slashes "$1")"
  assert_no_newline "$output_root" "OUTPUT_ROOT"
  case "$output_root" in
    /*) ;;
    *) fail "OUTPUT_ROOT must be an absolute path." ;;
  esac
  [[ -d "$output_root" ]] || fail "OUTPUT_ROOT must already exist as a directory: $output_root"
  [[ ! -L "$output_root" ]] || fail "OUTPUT_ROOT must not be a symlink: $output_root"
  output_physical="$(physical_directory "$output_root")" ||
    fail "OUTPUT_ROOT could not be resolved physically: $output_root"

  if [[ -d "$root_build" && ! -L "$root_build" ]]; then
    root_build_physical="$(physical_directory "$root_build")" ||
      fail "project .build could not be resolved physically."
    if [[ "$root_build_physical" == "$ROOT_DIR/.build" ]] &&
      is_strict_descendant "$output_physical" "$root_build_physical"; then
      allowed=1
    fi
  fi

  if is_strict_descendant "$output_physical" "/private/tmp"; then
    allowed=1
  fi

  if [[ -n "${TMPDIR:-}" && "${TMPDIR:-}" == /* && -d "${TMPDIR:-}" ]]; then
    tmp_physical="$(physical_directory "${TMPDIR:-}")" || tmp_physical=""
    case "$tmp_physical" in
      /private/var/folders/*/T)
        if is_strict_descendant "$output_physical" "$tmp_physical"; then
          allowed=1
        fi
        ;;
    esac
  fi

  [[ "$allowed" -eq 1 ]] ||
    fail "OUTPUT_ROOT must be inside the real project .build directory or this account's system temporary directory."

  VALIDATED_OUTPUT_ROOT="$output_physical"
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
    fail "main executable is not a readable Mach-O file: $executable"
  for arch in $archs; do
    count=$((count + 1))
    case "$arch" in
      arm64) has_arm64=$((has_arm64 + 1)) ;;
      x86_64) has_x86_64=$((has_x86_64 + 1)) ;;
      *) fail "unexpected architecture '$arch' in $executable" ;;
    esac
  done
  [[ "$count" -eq 2 && "$has_arm64" -eq 1 && "$has_x86_64" -eq 1 ]] ||
    fail "main executable architectures must be exactly arm64 and x86_64 (found: $archs)."
}

validate_entitlements_for_architecture() {
  local app_path="$1"
  local arch="$2"
  local entitlements_json

  ENTITLEMENTS_TEMP="$(/usr/bin/mktemp -t Codex94-entitlements)" ||
    fail "could not create a temporary entitlement file."
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
      fail "$arch contains one or more entitlements; v0.2.0 requires an empty entitlement dictionary."
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

reject_private_build_paths() {
  local app_path="$1"
  local executable="$2"
  local arch
  local literal
  local scan_status
  local symlink_path
  local symbols
  local forbidden_literals=(
    "/Users/"
    "/home/"
    "$ROOT_DIR/"
    "DerivedData"
    "Build/Intermediates.noindex"
    "/private/var/folders/"
    "/var/folders/"
    "/private/tmp/"
    "/tmp/"
  )

  symlink_path="$(/usr/bin/find "$app_path" -type l -print -quit)" ||
    fail "App bundle symlink scan could not read the complete payload."
  [[ -z "$symlink_path" ]] ||
    fail "App bundle must not contain symlinks; refusing an unscannable payload path."

  # Release payloads must not disclose a builder account, checkout, DerivedData,
  # or compiler-intermediate path. Fixed-string scans keep this compatible with
  # the system grep shipped on macOS and cover every file in the App bundle.
  for literal in "${forbidden_literals[@]}"; do
    scan_status=0
    /usr/bin/grep -a -R -F -q -- "$literal" "$app_path" || scan_status=$?
    case "$scan_status" in
      0) fail "App bundle contains a forbidden local build-path marker." ;;
      1) ;;
      *) fail "App bundle privacy scan could not read every payload file." ;;
    esac
  done

  # Inspect each Mach-O slice's symbol table independently as a second check.
  # Public product identifiers such as com.defyan94.codex94 remain allowed;
  # only path markers are rejected.
  for arch in arm64 x86_64; do
    symbols="$(/usr/bin/nm -arch "$arch" -ap "$executable")" ||
      fail "could not inspect the $arch symbol table for private build paths."
    for literal in "${forbidden_literals[@]}"; do
      case "$symbols" in
        *"$literal"*) fail "$arch symbol table contains a forbidden local build-path marker." ;;
      esac
    done
  done
}

validate_app() {
  local app_path
  local expected_version="$2"
  local expected_build="$3"
  local info_plist
  local executable_name
  local executable
  local arch

  app_path="$(trim_trailing_slashes "$1")"
  assert_no_newline "$app_path" "APP_PATH"
  case "$app_path" in
    /*) ;;
    *) fail "APP_PATH must be absolute: $app_path" ;;
  esac
  [[ -d "$app_path" && ! -L "$app_path" ]] ||
    fail "APP_PATH must be an existing, non-symlink app directory: $app_path"
  info_plist="$app_path/Contents/Info.plist"
  [[ -f "$info_plist" && ! -L "$info_plist" ]] ||
    fail "App Info.plist is missing or is a symlink: $info_plist"

  APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")" ||
    fail "App version is missing."
  APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")" ||
    fail "App build is missing."
  APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")" ||
    fail "App bundle identifier is missing."
  APP_MINIMUM_SYSTEM_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")" ||
    fail "App minimum system version is missing."
  executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")" ||
    fail "App executable name is missing."
  assert_no_newline "$executable_name" "App executable name"

  is_semantic_version "$APP_VERSION" || fail "App version is not a three-component semantic version: $APP_VERSION"
  is_positive_integer "$APP_BUILD" || fail "App build must be a positive integer: $APP_BUILD"
  [[ -z "$expected_version" || "$APP_VERSION" == "$expected_version" ]] ||
    fail "App version is $APP_VERSION; expected $expected_version."
  [[ -z "$expected_build" || "$APP_BUILD" == "$expected_build" ]] ||
    fail "App build is $APP_BUILD; expected $expected_build."
  [[ "$APP_BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] ||
    fail "App bundle identifier is $APP_BUNDLE_ID; expected $EXPECTED_BUNDLE_ID."
  [[ "$APP_MINIMUM_SYSTEM_VERSION" == "$EXPECTED_MINIMUM_SYSTEM_VERSION" ]] ||
    fail "App minimum system version is $APP_MINIMUM_SYSTEM_VERSION; expected $EXPECTED_MINIMUM_SYSTEM_VERSION."
  [[ -n "$executable_name" && "$executable_name" == "${executable_name##*/}" && "$executable_name" != "." && "$executable_name" != ".." ]] ||
    fail "App executable name is unsafe: $executable_name"

  executable="$app_path/Contents/MacOS/$executable_name"
  validate_exact_architectures "$executable"
  reject_private_build_paths "$app_path" "$executable"
  /usr/bin/codesign --verify --deep --strict --verbose=2 --all-architectures "$app_path" ||
    fail "App bundle code-signature integrity verification failed."
  for arch in arm64 x86_64; do
    validate_signature_for_architecture "$app_path" "$arch"
  done
}

assert_payload_allowlist() {
  local directory="$1"
  local entries

  entries=("$directory"/*)
  [[ "${#entries[@]}" -eq 2 ]] ||
    fail "payload root must contain exactly Codex94.app and Applications."
  [[ -d "$directory/Codex94.app" && ! -L "$directory/Codex94.app" ]] ||
    fail "payload Codex94.app is missing or is a symlink."
  [[ -L "$directory/Applications" ]] ||
    fail "payload Applications entry must be a symlink."
  [[ "$(/usr/bin/readlink "$directory/Applications")" == "/Applications" ]] ||
    fail "payload Applications symlink must point literally to /Applications."
}

assert_output_allowlist() {
  local directory="$1"
  local version="$2"
  local dmg_name="Codex94-$version-macos-universal-unnotarized.dmg"
  local checksum_name="Codex94-$version-SHA256SUMS.txt"
  local entries

  entries=("$directory"/*)
  [[ "${#entries[@]}" -eq 2 ]] ||
    fail "version output must contain exactly the DMG and checksum."
  [[ -f "$directory/$dmg_name" && ! -L "$directory/$dmg_name" ]] ||
    fail "expected DMG is missing, not regular, or a symlink."
  [[ -f "$directory/$checksum_name" && ! -L "$directory/$checksum_name" ]] ||
    fail "expected checksum is missing, not regular, or a symlink."
}

validate_checksum_file() {
  local checksum_path="$1"
  local dmg_basename="$2"
  local line_count
  local byte_count
  local line
  local digest

  line_count="$(/usr/bin/wc -l <"$checksum_path")"
  [[ "$line_count" -eq 1 ]] || fail "checksum must contain exactly one newline-terminated line."
  IFS= read -r line <"$checksum_path" || fail "checksum line could not be read."
  byte_count="$(/usr/bin/wc -c <"$checksum_path")"
  [[ "$byte_count" -eq $((${#line} + 1)) ]] ||
    fail "checksum must contain only its single newline-terminated line."
  [[ "${#line}" -eq $((66 + ${#dmg_basename})) ]] ||
    fail "checksum line has an invalid length."
  digest="${line:0:64}"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] ||
    fail "checksum digest must be 64 lowercase hexadecimal characters."
  [[ "$line" == "$digest  $dmg_basename" ]] ||
    fail "checksum must use two spaces and the exact DMG basename."
}

verify_checksum() {
  local dmg_path="$1"
  local checksum_path="$2"
  local dmg_directory
  local checksum_directory
  local dmg_basename="${dmg_path##*/}"
  local checksum_basename="${checksum_path##*/}"

  dmg_directory="$(physical_directory "$(/usr/bin/dirname "$dmg_path")")" ||
    fail "DMG directory could not be resolved."
  checksum_directory="$(physical_directory "$(/usr/bin/dirname "$checksum_path")")" ||
    fail "checksum directory could not be resolved."
  [[ "$dmg_directory" == "$checksum_directory" ]] ||
    fail "DMG and checksum must be in the same physical directory."
  validate_checksum_file "$checksum_path" "$dmg_basename"
  (cd "$dmg_directory" && /usr/bin/shasum -a 256 -c "$checksum_basename") ||
    fail "SHA-256 checksum verification failed."
}

verify_dmg() {
  local dmg_path="$1"
  local checksum_path="$2"
  local expected_version="$3"
  local expected_build="$4"
  local expected_dmg_name="Codex94-$expected_version-macos-universal-unnotarized.dmg"
  local expected_checksum_name="Codex94-$expected_version-SHA256SUMS.txt"
  local image_format
  local plist_format
  local encrypted
  local attach_plist
  local image_plist
  local encryption_plist
  local verify_temp_physical
  local entity_index=0
  local matching_mountpoints=0
  local entity_mountpoint

  is_semantic_version "$expected_version" ||
    fail "EXPECTED_VERSION must be a three-component semantic version."
  is_positive_integer "$expected_build" || fail "EXPECTED_BUILD must be a positive integer."
  [[ -f "$dmg_path" && ! -L "$dmg_path" ]] ||
    fail "DMG must be a regular, non-symlink file: $dmg_path"
  [[ -f "$checksum_path" && ! -L "$checksum_path" ]] ||
    fail "checksum must be a regular, non-symlink file: $checksum_path"
  [[ "${dmg_path##*/}" == "$expected_dmg_name" ]] ||
    fail "DMG basename does not match expected version $expected_version."
  [[ "${checksum_path##*/}" == "$expected_checksum_name" ]] ||
    fail "checksum basename does not match expected version $expected_version."

  verify_checksum "$dmg_path" "$checksum_path"
  /usr/bin/hdiutil verify "$dmg_path" || fail "hdiutil verify rejected the DMG."

  VERIFY_TEMP_DIR="$(/usr/bin/mktemp -d -t Codex94-verify)" ||
    fail "could not create a verification directory."
  verify_temp_physical="$(physical_directory "$VERIFY_TEMP_DIR")" ||
    fail "verification directory could not be resolved physically."
  VERIFY_TEMP_DIR="$verify_temp_physical"
  image_plist="$VERIFY_TEMP_DIR/imageinfo.plist"
  encryption_plist="$VERIFY_TEMP_DIR/encryption.plist"
  attach_plist="$VERIFY_TEMP_DIR/attach.plist"

  image_format="$(/usr/bin/hdiutil imageinfo -format "$dmg_path")" ||
    fail "could not read the DMG format."
  [[ "$image_format" == "UDZO" ]] || fail "DMG format must be UDZO (found: $image_format)."
  /usr/bin/hdiutil imageinfo -plist "$dmg_path" >"$image_plist" ||
    fail "could not read structured DMG image information."
  /usr/bin/plutil -lint "$image_plist" >/dev/null || fail "DMG image information is not a valid plist."
  plist_format="$(/usr/libexec/PlistBuddy -c 'Print :Format' "$image_plist")" ||
    fail "DMG image information does not identify its format."
  [[ "$plist_format" == "UDZO" ]] || fail "structured DMG format must be UDZO."

  /usr/bin/hdiutil isencrypted -plist "$dmg_path" >"$encryption_plist" ||
    fail "could not read structured DMG encryption information."
  /usr/bin/plutil -lint "$encryption_plist" >/dev/null ||
    fail "DMG encryption information is not a valid plist."
  encrypted="$(/usr/libexec/PlistBuddy -c 'Print :encrypted' "$encryption_plist")" ||
    fail "DMG encryption state is missing."
  [[ "$encrypted" == "false" ]] || fail "DMG must be unencrypted."

  if /usr/bin/codesign -d "$dmg_path" >/dev/null 2>&1; then
    fail "outer DMG unexpectedly contains a code signature."
  fi

  MOUNT_POINT="$VERIFY_TEMP_DIR/mount"
  /bin/mkdir "$MOUNT_POINT" || fail "could not create the verification mountpoint."
  MOUNT_ACTIVE=1
  /usr/bin/hdiutil attach "$dmg_path" \
    -readonly \
    -nobrowse \
    -noautoopen \
    -mountpoint "$MOUNT_POINT" \
    -plist >"$attach_plist" || fail "read-only DMG attach failed."
  /usr/bin/plutil -lint "$attach_plist" >/dev/null || fail "DMG attach output is not a valid plist."

  while /usr/libexec/PlistBuddy -c "Print :system-entities:$entity_index" "$attach_plist" \
    >/dev/null 2>&1; do
    if entity_mountpoint="$(/usr/libexec/PlistBuddy \
      -c "Print :system-entities:$entity_index:mount-point" "$attach_plist" 2>/dev/null)"; then
      if [[ "$entity_mountpoint" == "$MOUNT_POINT" ]]; then
        matching_mountpoints=$((matching_mountpoints + 1))
      fi
    fi
    entity_index=$((entity_index + 1))
  done
  [[ "$entity_index" -gt 0 ]] || fail "DMG attach plist contains no system entities."
  [[ "$matching_mountpoints" -eq 1 ]] ||
    fail "DMG attach plist must contain exactly one entity for the pre-created mountpoint."

  assert_payload_allowlist "$MOUNT_POINT"
  validate_app "$MOUNT_POINT/Codex94.app" "$expected_version" "$expected_build"

  /usr/bin/hdiutil detach "$MOUNT_POINT" || fail "DMG detach failed for the exact mountpoint."
  MOUNT_ACTIVE=0
  /bin/rmdir "$MOUNT_POINT" || fail "verification mountpoint was not empty after detach."
  MOUNT_POINT=""
  remove_owned_tree "$VERIFY_TEMP_DIR" "verification directory" ||
    fail "verification directory cleanup failed."
  VERIFY_TEMP_DIR=""

  echo "Verified unsigned Universal Codex94 DMG for $expected_version ($expected_build)."
}

create_dmg() {
  local app_path
  local output_root_input="$2"
  local version
  local build
  local final_directory
  local dmg_name
  local checksum_name
  local dmg_path
  local checksum_path
  local volume_name
  local temp_original
  local temp_basename
  local temp_identity
  local final_identity=""
  local owned_identity=""
  local nested_temp
  local move_status=0

  app_path="$(trim_trailing_slashes "$1")"
  validate_output_root "$output_root_input"
  validate_app "$app_path" "" ""
  version="$APP_VERSION"
  build="$APP_BUILD"
  final_directory="$VALIDATED_OUTPUT_ROOT/$version"
  dmg_name="Codex94-$version-macos-universal-unnotarized.dmg"
  checksum_name="Codex94-$version-SHA256SUMS.txt"
  volume_name="Codex94 $version"

  [[ ! -e "$final_directory" && ! -L "$final_directory" ]] ||
    fail "final version directory already exists; refusing to overwrite: $final_directory"

  LOCK_DIR="$VALIDATED_OUTPUT_ROOT/.Codex94-$version.lock"
  if ! /bin/mkdir "$LOCK_DIR"; then
    fail "another create process holds the version lock or a stale lock requires review: $LOCK_DIR"
  fi
  LOCK_OWNED=1
  [[ ! -e "$final_directory" && ! -L "$final_directory" ]] ||
    fail "final version directory appeared after locking; refusing to overwrite."

  STAGING_DIR="$(/usr/bin/mktemp -d -t Codex94-package)" ||
    fail "could not create a controlled staging directory."
  /usr/bin/ditto "$app_path" "$STAGING_DIR/Codex94.app" || fail "ditto failed to stage Codex94.app."
  /bin/ln -s /Applications "$STAGING_DIR/Applications" ||
    fail "could not create the Applications symlink."
  assert_payload_allowlist "$STAGING_DIR"

  TEMP_VERSION_DIR="$(/usr/bin/mktemp -d "$VALIDATED_OUTPUT_ROOT/.Codex94-$version.tmp.XXXXXX")" ||
    fail "could not create an atomic temporary version directory inside OUTPUT_ROOT."
  dmg_path="$TEMP_VERSION_DIR/$dmg_name"
  checksum_path="$TEMP_VERSION_DIR/$checksum_name"

  /usr/bin/hdiutil create \
    -format UDZO \
    -volname "$volume_name" \
    -nospotlight \
    -srcfolder "$STAGING_DIR" \
    "$dmg_path" || fail "hdiutil create failed."
  [[ -f "$dmg_path" && ! -L "$dmg_path" ]] || fail "hdiutil did not create the expected DMG."

  (cd "$TEMP_VERSION_DIR" && /usr/bin/shasum -a 256 "$dmg_name") >"$checksum_path" ||
    fail "could not create the SHA-256 checksum."
  assert_output_allowlist "$TEMP_VERSION_DIR" "$version"
  verify_dmg "$dmg_path" "$checksum_path" "$version" "$build"
  assert_output_allowlist "$TEMP_VERSION_DIR" "$version"

  [[ ! -e "$final_directory" && ! -L "$final_directory" ]] ||
    fail "final version directory appeared before publication; refusing to overwrite."
  temp_original="$TEMP_VERSION_DIR"
  temp_basename="${temp_original##*/}"
  temp_identity="$(/usr/bin/stat -f '%d:%i' "$temp_original")" ||
    fail "could not record the temporary version directory identity before publication."
  # BSD mv -h refuses to follow a directory symlink that appears at the target
  # between the final absence check and publication.
  /bin/mv -h -n "$temp_original" "$final_directory" || move_status=$?
  if [[ -d "$final_directory" && ! -L "$final_directory" ]]; then
    final_identity="$(/usr/bin/stat -f '%d:%i' "$final_directory")" || final_identity=""
  fi
  if [[ "$move_status" -ne 0 || -e "$temp_original" || -L "$temp_original" ||
    "$final_identity" != "$temp_identity" ]]; then
    # On macOS, `mv source existing-directory` can move source *inside* the
    # colliding directory. Locate only this run's inode so cleanup removes the
    # owned hidden temporary tree, never the colliding final directory.
    TEMP_VERSION_DIR=""
    if [[ -d "$temp_original" && ! -L "$temp_original" ]]; then
      owned_identity="$(/usr/bin/stat -f '%d:%i' "$temp_original")" || owned_identity=""
      if [[ "$owned_identity" == "$temp_identity" ]]; then
        TEMP_VERSION_DIR="$temp_original"
      fi
    fi
    nested_temp="$final_directory/$temp_basename"
    if [[ -z "$TEMP_VERSION_DIR" && -d "$final_directory" && ! -L "$final_directory" &&
      -d "$nested_temp" && ! -L "$nested_temp" ]]; then
      owned_identity="$(/usr/bin/stat -f '%d:%i' "$nested_temp")" || owned_identity=""
      if [[ "$owned_identity" == "$temp_identity" ]]; then
        TEMP_VERSION_DIR="$nested_temp"
      fi
    fi
    fail "atomic version directory publication collided or did not preserve the temporary directory identity."
  fi
  TEMP_VERSION_DIR=""

  assert_output_allowlist "$final_directory" "$version"
  verify_checksum "$final_directory/$dmg_name" "$final_directory/$checksum_name"

  remove_owned_tree "$STAGING_DIR" "staging directory" || fail "staging cleanup failed."
  STAGING_DIR=""
  /bin/rmdir "$LOCK_DIR" || fail "version lock was unexpectedly non-empty."
  LOCK_OWNED=0
  LOCK_DIR=""

  echo "Created $final_directory/$dmg_name"
  echo "Created $final_directory/$checksum_name"
}

main() {
  require_tools
  [[ "$#" -ge 1 ]] || {
    usage
    exit 2
  }

  case "$1" in
    create)
      [[ "$#" -eq 3 ]] || {
        usage
        exit 2
      }
      create_dmg "$2" "$3"
      ;;
    verify)
      [[ "$#" -eq 5 ]] || {
        usage
        exit 2
      }
      verify_dmg "$2" "$3" "$4" "$5"
      ;;
    *)
      usage
      fail "unknown mode '$1'."
      ;;
  esac
}

main "$@"
