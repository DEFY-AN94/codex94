#!/usr/bin/env bash
set -euo pipefail

# Sourcing defines helpers only; tests never invoke the production entry point.
INSTALL_LOCK=""
INSTALL_LOCK_ID=""
INSTALL_TRANSACTION=""
INSTALL_TRANSACTION_ID=""
INSTALL_TARGET=""
INSTALL_NEW_ID=""
INSTALL_OLD_ID=""
INSTALL_COMMITTED=0

install_fail() {
  echo "Codex94 installation failed: $*" >&2
  return 1
}

install_identity() { /usr/bin/stat -f '%d:%i' "$1"; }

install_require_quit() {
  local status=0
  /usr/bin/pgrep -x Codex94 >/dev/null 2>&1 || status=$?
  case "$status" in
    1) return 0 ;;
    0) install_fail "quit every running Codex94 copy, then run the installer again." ;;
    *) install_fail "could not check running Codex94 processes." ;;
  esac
}

install_move() {
  local source="$1" destination="$2" identity
  [[ ! -e "$destination" && ! -L "$destination" ]] ||
    { install_fail "destination already exists: $destination"; return 1; }
  identity="$(install_identity "$source")" || return 1
  /bin/mv -h -n "$source" "$destination" || return 1
  [[ ! -e "$source" && ! -L "$source" && -d "$destination" && ! -L "$destination" &&
    "$(install_identity "$destination")" == "$identity" ]] ||
    install_fail "move collided; preserve the transaction for inspection: $destination"
}

install_validate_target() {
  [[ ! -L "$INSTALL_TARGET" ]] || { install_fail "App destination must not be a symlink."; return 1; }
  [[ ! -e "$INSTALL_TARGET" || -d "$INSTALL_TARGET" ]] ||
    install_fail "App destination must be a directory."
}

install_begin() {
  local directory="$1" entry
  [[ "$directory" == /* && -d "$directory" ]] ||
    { install_fail "installation directory must be an existing absolute directory."; return 1; }
  directory="$(cd "$directory" && pwd -P)" || return 1
  INSTALL_TARGET="$directory/Codex94.app"
  install_validate_target || return 1
  INSTALL_LOCK="$directory/.Codex94.install.lock"
  if ! /bin/mkdir "$INSTALL_LOCK" 2>/dev/null; then
    INSTALL_LOCK=""
    install_fail "an install lock exists; inspect $directory/.Codex94.install.lock before retrying."
    return 1
  fi
  INSTALL_LOCK_ID="$(install_identity "$INSTALL_LOCK")"
  for entry in "$directory"/.Codex94.install.* "$directory/.Codex94.installing.app"; do
    [[ "$entry" == "$INSTALL_LOCK" ]] && continue
    if [[ -e "$entry" || -L "$entry" ]]; then
      install_fail "an earlier transaction exists; preserve and inspect it before retrying: $entry"
      return 1
    fi
  done
  INSTALL_TRANSACTION="$(/usr/bin/mktemp -d "$directory/.Codex94.install.XXXXXX")" || return 1
  INSTALL_TRANSACTION_ID="$(install_identity "$INSTALL_TRANSACTION")"
}

install_verify_app() {
  local app="$1" identifier
  [[ -d "$app" && ! -L "$app" && -f "$app/Contents/Info.plist" &&
    ! -L "$app/Contents/Info.plist" ]] || return 1
  identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" || return 1
  [[ "$identifier" == com.defyan94.codex94 ]] || return 1
  /usr/bin/codesign --verify --deep --strict --all-architectures "$app"
}

install_stage() {
  local app="$1"
  [[ -n "$INSTALL_TRANSACTION" && -d "$app" && ! -L "$app" ]] || return 1
  /usr/bin/ditto "$app" "$INSTALL_TRANSACTION/staged.app" || return 1
  /usr/bin/codesign --force --deep --options runtime --sign - "$INSTALL_TRANSACTION/staged.app" || return 1
  install_verify_app "$INSTALL_TRANSACTION/staged.app"
}

install_replace() {
  local staged="$INSTALL_TRANSACTION/staged.app"
  install_validate_target || return 1
  install_verify_app "$staged" || return 1
  INSTALL_NEW_ID="$(install_identity "$staged")" || return 1
  if [[ -d "$INSTALL_TARGET" ]]; then
    INSTALL_OLD_ID="$(install_identity "$INSTALL_TARGET")" || return 1
    install_move "$INSTALL_TARGET" "$INSTALL_TRANSACTION/backup.app" || return 1
  fi
  install_move "$staged" "$INSTALL_TARGET" || return 1
  install_verify_app "$INSTALL_TARGET" || return 1
  INSTALL_COMMITTED=1
}

install_cleanup() {
  local status="$1" preserve=0 backup
  # Two renames are rollback-capable, not crash-atomic. Never discard a backup
  # when rollback fails or an unknown App has occupied the destination.
  if [[ -n "$INSTALL_TRANSACTION" ]]; then
    if [[ ! -d "$INSTALL_TRANSACTION" || -L "$INSTALL_TRANSACTION" ||
      "$(install_identity "$INSTALL_TRANSACTION")" != "$INSTALL_TRANSACTION_ID" ]]; then
      install_fail "transaction identity changed; manual recovery is required." || true
      preserve=1
    elif [[ "$INSTALL_COMMITTED" -eq 0 ]]; then
      backup="$INSTALL_TRANSACTION/backup.app"
      if [[ -e "$backup" || -L "$backup" ]]; then
        if [[ -z "$INSTALL_OLD_ID" || ! -d "$backup" || -L "$backup" ||
          "$(install_identity "$backup")" != "$INSTALL_OLD_ID" ]]; then
          preserve=1
        fi
      fi
      if [[ -e "$INSTALL_TARGET" || -L "$INSTALL_TARGET" ]]; then
        if [[ -n "$INSTALL_NEW_ID" && ! -L "$INSTALL_TARGET" &&
          "$(install_identity "$INSTALL_TARGET")" == "$INSTALL_NEW_ID" ]]; then
          install_move "$INSTALL_TARGET" "$INSTALL_TRANSACTION/rejected.app" || preserve=1
        elif [[ -e "$backup" || -L "$backup" ]]; then
          preserve=1
        fi
      fi
      if [[ "$preserve" -eq 0 && -d "$backup" ]]; then
        install_move "$backup" "$INSTALL_TARGET" || preserve=1
      fi
    fi
    if [[ "$preserve" -eq 0 ]]; then
      /bin/rm -rf "$INSTALL_TRANSACTION" || preserve=1
    fi
    if [[ "$preserve" -ne 0 ]]; then
      echo "Keep the recovery files at $INSTALL_TRANSACTION; inspect backup.app before retrying." >&2
      status=1
    fi
  fi
  if [[ -n "$INSTALL_LOCK_ID" ]]; then
    if [[ -d "$INSTALL_LOCK" && ! -L "$INSTALL_LOCK" &&
      "$(install_identity "$INSTALL_LOCK")" == "$INSTALL_LOCK_ID" ]]; then
      /bin/rmdir "$INSTALL_LOCK" || status=1
    else
      echo "Install lock changed; it was not removed: $INSTALL_LOCK" >&2
      status=1
    fi
  fi
  return "$status"
}

install_on_exit() {
  local status=$?
  trap - EXIT HUP INT TERM
  install_cleanup "$status" || status=$?
  exit "$status"
}

main() {
  [[ "$#" -eq 0 || ( "$#" -eq 1 && "$1" == --no-launch ) ]] ||
    { echo "usage: $0 [--no-launch]" >&2; return 2; }
  local root project derived app directory
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
  project="$root/Codex94.xcodeproj"
  derived="$root/.build/DerivedData-Release"
  app="$derived/Build/Products/Release/Codex94.app"
  directory="$HOME/Applications"
  install_require_quit || return 1
  /bin/mkdir -p "$directory"
  trap install_on_exit EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  install_begin "$directory"
  "$root/script/security_check.sh"
  /bin/mkdir -p "$root/.build/ModuleCache"
  export CLANG_MODULE_CACHE_PATH="$root/.build/ModuleCache"
  export SWIFT_MODULE_CACHE_PATH="$root/.build/ModuleCache"
  /usr/bin/xcodebuild -project "$project" -scheme Codex94 -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$derived" build
  install_stage "$app"
  install_require_quit
  install_replace
  echo "Installed $INSTALL_TARGET"
  if [[ "${1:-}" != --no-launch ]]; then
    /usr/bin/open -n "$INSTALL_TARGET" ||
      { install_fail "App was installed successfully but could not be opened."; return 1; }
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
