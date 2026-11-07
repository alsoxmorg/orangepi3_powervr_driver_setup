#!/bin/bash
# Source from Bash build/install scripts. Empty BOARD_ENV means auto-detect.
board_env_config_base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [ -z "${BOARD_ENV+x}" ] && [ -r "$board_env_config_base/config/board.env" ]; then
  source "$board_env_config_base/config/board.env"
fi
export BOARD_ENV=${BOARD_ENV-}
board_env_init() {
  local board_base settings key value
  local -a arguments=()
  board_base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
  if [ "${1-}" = check ]; then arguments+=(--check-host); fi
  settings=$(python3 "$board_base/scripts/boards.py" --env-lines "${arguments[@]}") || return 1
  while IFS=$'\t' read -r key value; do
    case "$key" in
      BOARD_ENV) BOARD_ENV=$value ;;
      BOARD_NAME) BOARD_NAME=$value ;;
      BOARD_STATUS) BOARD_STATUS=$value ;;
      KERNEL_IMAGE_PACKAGE) KERNEL_IMAGE_PACKAGE=$value ;;
      KERNEL_HEADERS_PACKAGE) KERNEL_HEADERS_PACKAGE=$value ;;
      JOBS) JOBS=$value ;;
    esac
  done <<< "$settings"
  export BOARD_ENV BOARD_NAME BOARD_STATUS KERNEL_IMAGE_PACKAGE KERNEL_HEADERS_PACKAGE JOBS
  printf 'Board: %s (%s), status=%s, build jobs=%s\n' "$BOARD_NAME" "$BOARD_ENV" "$BOARD_STATUS" "$JOBS"
  if [ "$BOARD_STATUS" != tested ]; then
    echo 'Experimental board profile: device-tree ID, kernel and GPU behavior still require target hardware acceptance.' >&2
  fi
}
