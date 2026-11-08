#!/bin/bash
# Shared installer helpers. Source after board-env.sh.
require_native_host() {
  test "$(uname -m)" = aarch64 && test "$(dpkg --print-architecture)" = arm64 || {
    echo 'Run on the target ARM64 board; these installers do not cross-compile.' >&2
    return 1
  }
  # Both supported images are Debian 13 derivatives.
  local ID= VERSION_ID=
  source "${1:-/etc/os-release}"
  if [ "$ID" != debian ] || [ "${VERSION_ID%%.*}" != 13 ]; then
    echo 'Supported target: Debian 13 (DietPi for opz3w, Orange Pi Debian for opz4).' >&2
    return 1
  fi
}

installed_version() {
  local info
  info=$(dpkg-query -W -f='${Status}\t${Version}' "$1" 2>/dev/null) || return 1
  [[ "$info" = $'install ok installed\t'* ]] || return 1
  printf '%s\n' "${info#*$'\t'}"
}

headers_install_target() {
  local version=$1 candidate=${KERNEL_HEADERS_DEB:-} existing local_dir=${2:-/opt}
  if [ -z "$candidate" ]; then
    existing=$(installed_version "$KERNEL_HEADERS_PACKAGE") || existing=
    if [ "$existing" = "$version" ]; then return 0; fi
    # Orange Pi images may ship exact headers locally, outside apt repositories.
    if [ "$BOARD_ENV" = opz4 ] && [ -f "$local_dir/${KERNEL_HEADERS_PACKAGE}_${version}_arm64.deb" ]; then
      candidate="$local_dir/${KERNEL_HEADERS_PACKAGE}_${version}_arm64.deb"
    fi
  fi
  if [ -n "$candidate" ]; then
    candidate=$(realpath -e -- "$candidate") || return 1
    if [ "$(dpkg-deb -f "$candidate" Package)" != "$KERNEL_HEADERS_PACKAGE" ] ||
       [ "$(dpkg-deb -f "$candidate" Version)" != "$version" ] ||
       [ "$(dpkg-deb -f "$candidate" Architecture)" != arm64 ]; then
      echo 'Local headers must match the selected package name, image version and arm64 architecture.' >&2
      return 1
    fi
    printf '%s\n' "$candidate"
  else
    printf '%s=%s\n' "$KERNEL_HEADERS_PACKAGE" "$version"
  fi
}

core_package_path() {
  local record="dist/core-package-$BOARD_ENV.path" name
  if [ "$BOARD_ENV" = opz3w ] && [ ! -f "$record" ]; then record=dist/core-package.path; fi
  test -f "$record" || { echo "Build the $BOARD_ENV core package first." >&2; return 1; }
  name=$(cat "$record")
  case "$name" in orangepi-zero3w-powervr_*_arm64.deb) ;; *) echo 'Invalid recorded package name.' >&2; return 1 ;; esac
  case "$name" in */*|*$'\n'*) echo 'Invalid package path.' >&2; return 1 ;; esac
  test -f "dist/$name" || { echo 'Recorded package is missing; build first.' >&2; return 1; }
  # Board-tagged records must not silently select a different target's package.
  if [ "$record" != dist/core-package.path ]; then
    case "$name" in *+"$BOARD_ENV".kernel*) ;; *) echo 'Recorded package targets another board.' >&2; return 1 ;; esac
  fi
  printf 'dist/%s\n' "$name"
}

configure_access() {
  local account=${1:-${SUDO_USER:-}} account_uid group
  if [ -z "$account" ] || [ "$account" = root ]; then
    echo 'Specify the normal login account: sudo ./install.sh access USER' >&2
    return 1
  fi
  account_uid=$(id -u -- "$account") || return 1
  test "$account_uid" != 0 || { echo 'Choose a non-root login account.' >&2; return 1; }
  for group in video render; do
    getent group "$group" >/dev/null || groupadd --system "$group"
  done
  usermod -aG video,render -- "$account"
  printf 'Added %s to video and render. Log out of the TTY completely and log back in.\n' "$account"
  echo 'Restarting Codex or a terminal application does not refresh the parent login groups.'
}
