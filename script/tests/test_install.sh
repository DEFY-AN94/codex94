#!/usr/bin/env bash
set -euo pipefail

INSTALLER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/install.sh"
TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/Codex94InstallTests.XXXXXX")"
trap '/bin/rm -rf "$TEST_ROOT"' EXIT

run_case() (
  local scenario="$1" directory="$TEST_ROOT/$1" saved_transaction status
  source "$INSTALLER"
  mkdir "$directory"
  install_verify_app() { [[ -d "$1/new-marker" ]]; }
  if [[ "$scenario" != first ]]; then
    mkdir -p "$directory/Codex94.app/old-marker"
  fi
  install_begin "$directory"
  saved_transaction="$INSTALL_TRANSACTION"
  mkdir -p "$INSTALL_TRANSACTION/staged.app/new-marker"
  case "$scenario" in
    first|replace)
      install_replace
      install_cleanup 0
      [[ -d "$directory/Codex94.app/new-marker" && ! -e "$saved_transaction" ]]
      ;;
    before_replace)
      # A failed copy/sign/validation cannot touch the old App.
      install_verify_app() { return 1; }
      if install_replace; then exit 1; fi
      install_cleanup 1 || status=$?
      [[ "$status" == 1 && -d "$directory/Codex94.app/old-marker" && ! -e "$saved_transaction" ]]
      ;;
    move_failed|rollback_failed|unknown_conflict|backup_collision)
      install_move() {
        if [[ "$scenario" == backup_collision && "$2" == "$INSTALL_TRANSACTION/backup.app" ]]; then
          mkdir -p "$2/unknown-marker"
          /bin/mv "$1" "$2"
          return 1
        fi
        if [[ "$1" == "$INSTALL_TRANSACTION/staged.app" ]]; then
          if [[ "$scenario" == unknown_conflict ]]; then
            mkdir -p "$INSTALL_TARGET/unknown-marker"
          fi
          return 1
        fi
        if [[ "$scenario" == rollback_failed && "$1" == "$INSTALL_TRANSACTION/backup.app" ]]; then
          return 1
        fi
        [[ ! -e "$2" && ! -L "$2" ]] || return 1
        /bin/mv "$1" "$2"
      }
      if install_replace; then exit 1; fi
      install_cleanup 1 || status=$?
      [[ "$status" == 1 ]]
      if [[ "$scenario" == move_failed ]]; then
        [[ -d "$directory/Codex94.app/old-marker" && ! -e "$saved_transaction" ]]
      else
        if [[ "$scenario" == backup_collision ]]; then
          [[ -d "$saved_transaction/backup.app/Codex94.app/old-marker" &&
            -d "$saved_transaction/backup.app/unknown-marker" && ! -e "$directory/Codex94.app" ]]
        else
          [[ -d "$saved_transaction/backup.app/old-marker" ]]
        fi
        if [[ "$scenario" == unknown_conflict ]]; then
          [[ -d "$directory/Codex94.app/unknown-marker" ]]
        fi
      fi
      ;;
    final_validation_failed)
      install_verify_app() { [[ "$1" == "$INSTALL_TRANSACTION/staged.app" ]]; }
      if install_replace; then exit 1; fi
      install_cleanup 1 || status=$?
      [[ "$status" == 1 && -d "$directory/Codex94.app/old-marker" && ! -e "$saved_transaction" ]]
      ;;
    lock)
      (
        source "$INSTALLER"
        if install_begin "$directory"; then exit 1; fi
        install_cleanup 0
        [[ -d "$directory/.Codex94.install.lock" ]]
      )
      install_cleanup 0
      [[ ! -e "$directory/.Codex94.install.lock" ]]
      ;;
  esac
  echo "PASS install $scenario"
)

for scenario in first replace before_replace move_failed rollback_failed unknown_conflict backup_collision final_validation_failed lock; do
  run_case "$scenario"
done

(
  source "$INSTALLER"
  directory="$TEST_ROOT/symlink"
  mkdir -p "$directory/other.app/marker"
  ln -s other.app "$directory/Codex94.app"
  if install_begin "$directory"; then exit 1; fi
  install_cleanup 0
  [[ -d "$directory/other.app/marker" && -L "$directory/Codex94.app" ]]
  echo 'PASS install symlink'
)

(
  source "$INSTALLER"
  directory="$TEST_ROOT/residual"
  mkdir -p "$directory/.Codex94.install.previous/backup.app"
  if install_begin "$directory"; then exit 1; fi
  install_cleanup 0
  [[ -d "$directory/.Codex94.install.previous/backup.app" && ! -e "$directory/.Codex94.install.lock" ]]
  echo 'PASS install residual'
)

mkdir -p "$TEST_ROOT/signal/Codex94.app/old-marker"
signal_status=0
/bin/bash -c '
  set -euo pipefail
  source "$1"
  trap install_on_exit EXIT
  trap "exit 143" TERM
  install_begin "$2"
  mkdir -p "$INSTALL_TRANSACTION/staged.app/new-marker"
  install_verify_app() { return 0; }
  install_move() {
    /bin/mv "$1" "$2"
    if [[ "$2" == "$INSTALL_TRANSACTION/backup.app" ]]; then
      kill -TERM $$
    fi
  }
  install_replace
' _ "$INSTALLER" "$TEST_ROOT/signal" || signal_status=$?
[[ "$signal_status" == 143 && -d "$TEST_ROOT/signal/Codex94.app/old-marker" &&
  ! -e "$TEST_ROOT/signal/.Codex94.install.lock" ]]
echo 'PASS install signal rollback'
echo 'Installer transaction tests passed (synthetic directories only).'
