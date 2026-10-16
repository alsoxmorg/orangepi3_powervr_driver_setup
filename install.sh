#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$(readlink -f -- "$0")")"
case "${1:-help}" in
  deps)
    if [ "$(id -u)" = 0 ]; then
      echo 'Run ./install.sh deps as your normal user; it invokes sudo.' >&2; exit 1
    fi
    version=$(dpkg-query -W -f='${Version}' linux-image-vendor-sun60iw2)
    sudo apt-get update
    sudo apt-get install build-essential python3 curl e2fsprogs patch kmod dpkg-dev \
      vulkan-tools "linux-headers-vendor-sun60iw2=$version"
    ;;
  download) exec python3 scripts/download.py ;;
  prepare) shift; exec python3 scripts/prepare.py "$@" ;;
  build)
    test "$(id -u)" != 0 || { echo 'Build as your normal user.' >&2; exit 1; }
    if [ ! -d work/source ] && [ ! -d work/runtime ]; then
      if [ "$#" -gt 1 ]; then
        python3 scripts/prepare.py "$2"
      else
        image=$(python3 scripts/download.py)
        python3 scripts/prepare.py "$image"
      fi
    fi
    exec bash scripts/build-package.sh
    ;;
  install)
    test "$(id -u)" = 0 || { echo 'Use sudo ./install.sh install.' >&2; exit 1; }
    package=dist/orangepi-zero3w-powervr_24.2.6603887-2_arm64.deb
    test -f "$package" || { echo 'Build first.' >&2; exit 1; }
    exec apt-get install "./$package"
    ;;
  diagnose) shift; exec bash scripts/diagnose.sh "$@" ;;
  *)
    cat <<'EOF'
Experimental Orange Pi Zero 3W PowerVR driver

  ./install.sh deps                 Install matching headers and tools via sudo
  ./install.sh build                Download donor, extract, compile and package
  ./install.sh build /path/img.xz   Use a local copy of the exact donor instead
  sudo ./install.sh install         Install the locally built .deb
  ./install.sh diagnose             Record Vulkan/session diagnostics
  ./install.sh diagnose --cube      Also try 120 frames through X11/Xwayland

Read README.md before installation. Rendering and reboot behavior are experimental.
EOF
    ;;
esac
