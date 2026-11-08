#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$(readlink -f -- "$0")")"
source scripts/board-env.sh
source scripts/install-support.sh

as_root() {
  sudo env BOARD_ENV="$BOARD_ENV" ARCH="$ARCH" \
    KERNEL_IMAGE_PACKAGE="$KERNEL_IMAGE_PACKAGE" KERNEL_HEADERS_PACKAGE="$KERNEL_HEADERS_PACKAGE" \
    bash "$PWD/install.sh" "$@"
}
require_user() {
  test "$(id -u)" != 0 || { echo 'Run as your normal user; privileged steps invoke sudo.' >&2; exit 1; }
}
ensure_python() {
  if ! command -v python3 >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install python3
  fi
}
require_root() {
  test "$(id -u)" = 0 || { echo "Use sudo ./install.sh ${1:-install}." >&2; exit 1; }
}

case "${1:-help}" in
  boards) exec python3 scripts/boards.py --list ;;
  board) exec python3 scripts/boards.py ;;
  setup)
    test "$#" -le 2 || { echo 'Usage: ./install.sh setup [DONOR.img.xz]' >&2; exit 2; }
    require_user
    require_native_host
    ensure_python
    board_env_init check
    account=$(id -un)
    bash "$PWD/install.sh" deps
    bash "$PWD/install.sh" test-tools
    bash "$PWD/install.sh" build "${@:2}"
    bash "$PWD/install.sh" userland
    as_root install-all
    as_root access "$account"
    as_root verify
    echo 'Setup complete. Log out of the local TTY completely and log back in.'
    echo 'Check id -nG includes video and render, then run powervr-sway from the local TTY.'
    ;;
  deps)
    require_user
    require_native_host
    ensure_python
    board_env_init check
    version=$(installed_version "$KERNEL_IMAGE_PACKAGE") || {
      echo "Missing installed image package $KERNEL_IMAGE_PACKAGE; verify the selected image/profile." >&2; exit 1;
    }
    target=$(headers_install_target "$version")
    headers=()
    if [ -n "$target" ]; then headers+=("$target"); fi
    sudo apt-get update
    sudo apt-get install build-essential python3 curl e2fsprogs patch kmod dpkg-dev \
      bison flex libssl-dev vulkan-tools libxcb-dri2-0 \
      libegl-dev libgles-dev libgbm-dev libdrm-dev "${headers[@]}" || {
        echo "Exact headers required: $KERNEL_HEADERS_PACKAGE=$version." >&2
        echo 'For a trusted local package, set KERNEL_HEADERS_DEB=/absolute/path/to/headers.deb and retry deps.' >&2
        exit 1
      }
    test "$(installed_version "$KERNEL_HEADERS_PACKAGE")" = "$version"
    test -f "/lib/modules/$(uname -r)/build/Module.symvers" || {
      echo 'Running kernel has no configured headers/Module.symvers. Boot the kernel matching the installed image and headers before building.' >&2; exit 1;
    }
    ;;
  test-tools)
    require_user
    board_env_init check
    require_native_host
    sudo apt-get install vulkan-tools libvulkan-dev vulkan-validationlayers \
      mesa-utils mesa-vulkan-drivers libegl-mesa0 libgl1-mesa-dri \
      glmark2-es2-x11 glmark2-es2-wayland glmark2-es2-drm kmscube wayland-utils \
      sway xwayland libwlroots-0.18 foot seatd
    ;;
  download) exec python3 scripts/download.py ;;
  prepare) shift; exec python3 scripts/prepare.py "$@" ;;
  build)
    test "$#" -le 2 || { echo 'Usage: ./install.sh build [DONOR.img.xz]' >&2; exit 2; }
    require_user
    board_env_init check
    require_native_host
    if { [ -e work/source ] && [ ! -d work/runtime ]; } ||
       { [ -e work/runtime ] && [ ! -d work/source ]; }; then
      echo 'Incomplete prepared inputs: inspect work/source and work/runtime and move the partial extraction aside before retrying.' >&2
      exit 1
    fi
    if [ ! -d work/source ] || [ ! -d work/runtime ]; then
      if [ "$#" = 2 ]; then
        python3 scripts/prepare.py "$2"
      else
        image=$(python3 scripts/download.py)
        python3 scripts/prepare.py "$image"
      fi
    fi
    exec bash scripts/build-package.sh
    ;;
  install|install-all)
    require_root "$1"
    board_env_init check
    require_native_host
    package=$(core_package_path)
    control=$(mktemp -d)
    trap 'rm -rf -- "$control"' EXIT
    dpkg-deb -e "$package" "$control"
    sh "$control/preinst" upgrade
    rm -rf -- "$control"
    trap - EXIT
    packages=("./$package")
    if [ "$1" = install-all ]; then
      userland=dist/orangepi-zero3w-powervr-userland_24.2.6603887-6_arm64.deb
      test -f "$userland" || { echo 'Build the userland package first.' >&2; exit 1; }
      packages+=("./$userland")
    fi
    exec apt-get install "${packages[@]}"
    ;;
  access)
    require_root access
    board_env_init check
    configure_access "${2:-}"
    ;;
  verify)
    require_root verify
    board_env_init check
    require_native_host
    modprobe pvrsrvkm
    timeout --kill-after=5s 30s powervr-run vulkaninfo --summary
    timeout --kill-after=5s 30s powervr-presentation-probe
    echo 'PASS: driver loading, Vulkan enumeration and headless EGL/display-buffer checks.'
    echo 'Physical presentation and reboot persistence need separate acceptance checks.'
    ;;
  diagnose) shift; exec bash scripts/diagnose.sh "$@" ;;
  userland) shift; exec bash scripts/build-userland.sh "$@" ;;
  probe-userland) shift; exec bash scripts/test-userland.sh "$@" ;;
  probe-presentation) shift; exec bash scripts/test-presentation.sh "$@" ;;
  install-userland)
    require_root install-userland
    board_env_init check
    package=dist/orangepi-zero3w-powervr-userland_24.2.6603887-6_arm64.deb
    test -f "$package" || { echo 'Build the userland package first.' >&2; exit 1; }
    exec apt-get install "./$package"
    ;;
  help|-h|--help)
    cat <<'HELP'
Experimental Orange Pi A733 PowerVR installer (native ARM64 / Debian 13)

Platform entry points (run as your normal user):
  ./scripts/install-opz3w-dietpi.sh [COMMAND]  Zero 3W / DietPi vendor kernel
  ./scripts/install-opz4-debian.sh [COMMAND]  Zero 4 / Orange Pi Debian current kernel
  With no COMMAND, each platform entry point runs setup. Pass help to inspect.

  ./install.sh boards               List board profiles
  ./install.sh board                Show profile (BOARD_ENV="" auto-detects)
  ./install.sh setup [DONOR.img.xz]  Deps, test tools, both builds/install, groups, headless verification
  ./install.sh deps                 Build tools and exact installed-image headers
  ./install.sh test-tools           Mesa/Vulkan diagnostics, GLES benchmarks, Sway/Xwayland
  ./install.sh build [DONOR.img.xz]  Download/extract/verify, compile and package core
  ./install.sh userland             Build private EGL/GLES/GBM and launchers
  sudo ./install.sh install         Install core package only
  sudo ./install.sh install-all     Install both freshly built packages together
  sudo ./install.sh install-userland  Install private userland only
  sudo ./install.sh access USER     Add login account to video and render
  sudo ./install.sh verify          Load driver; Vulkan + headless display-sharing tests
  ./install.sh probe-presentation --compare  Normal-user display-sharing preflight
  ./install.sh probe-userland       EGL/GLES pixel readback
  ./install.sh diagnose [--cube]    Capture diagnostics; optionally try X11 cube

Overrides: BOARD_ENV=opz3w|opz4 ARCH=arm64 JOBS=1
           KERNEL_HEADERS_DEB=/trusted/exact/headers.deb
           KERNEL_IMAGE_PACKAGE / KERNEL_HEADERS_PACKAGE
Zero 4 also finds matching headers in /opt automatically when not installed.
After setup, log out of the TTY completely and back in before powervr-sway.
Read README.md for experimental-driver limitations. Setup does not launch a desktop.
HELP
    ;;
  *) echo "Unknown command: $1. Use ./install.sh help." >&2; exit 2 ;;
esac
