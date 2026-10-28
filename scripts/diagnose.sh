#!/bin/bash
# Run inside the desktop session, as its normal user; no sudo needed.
set -uo pipefail
cd -- "$(dirname -- "$(readlink -f -- "$0")")/.."
if [ "$(id -u)" = 0 ]; then
  echo 'Run diagnostics as the logged-in desktop user, without sudo.' >&2
  exit 1
fi
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != --cube ]; }; then
  echo 'Usage: ./install.sh diagnose [--cube]' >&2; exit 2
fi
mkdir -p work/diagnostics
log="work/diagnostics/session-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  printf 'Kernel: '; uname -r
  id
  printf 'DISPLAY=%s\nWAYLAND_DISPLAY=%s\nXDG_RUNTIME_DIR=%s\nXDG_SESSION_TYPE=%s\n' \
    "${DISPLAY-}" "${WAYLAND_DISPLAY-}" "${XDG_RUNTIME_DIR-}" "${XDG_SESSION_TYPE-}"
  ls -l /dev/dri 2>&1
  dpkg-query -W -f='${Package} ${Version}\n' orangepi-zero3w-powervr vulkan-tools 2>&1
  if [ -n "${DISPLAY-}" ]; then
    printf '\n=== X server extensions and providers ===\n'
    if command -v xdpyinfo >/dev/null; then
      timeout 10s xdpyinfo -queryExtensions 2>&1 | sed -n '1,/^screen #0:/p'
    fi
    if command -v xrandr >/dev/null; then timeout 10s xrandr --listproviders 2>&1; fi
    if command -v glxinfo >/dev/null; then timeout 10s glxinfo -B 2>&1; fi
  fi
  printf '\n=== System-loader baseline (no private driver selection) ===\n'
  timeout 30s vulkaninfo --summary 2>&1
  echo "Baseline exit: $?"
  printf '\n=== Installed PowerVR stack ===\n'
  timeout 30s powervr-run vulkaninfo --summary 2>&1
  echo "PowerVR exit: $?"
  if [ "${1-}" = --cube ]; then
    if [ -z "${DISPLAY-}" ]; then
      echo 'No DISPLAY: an X11 window cannot open from this session.'
      echo 'Run this command in a terminal inside Xorg or Sway with Xwayland.'
    else
      printf '\n=== Explicit XCB presentation, bounded to 120 frames / 30 seconds ===\n'
      timeout --kill-after=5s 30s powervr-run vkcube --wsi xcb --c 120 2>&1
      echo "Cube exit: $? (124/137 indicates timeout; check for a hung process)"
    fi
  fi
  printf '\n=== GPU messages available to this account ===\n'
  journalctl -b -k --no-pager --grep='PVR|pvrsrvkm|rgx|1800000.gpu' -n 80 2>&1
  printf '\n=== Latest Xorg display/acceleration evidence ===\n'
  grep -E 'PrimaryGPU|using drv|glamor|llvmpipe|DRI[23]|DRISWRAST|\(EE\)' \
    "$HOME/.local/share/xorg/Xorg.0.log" 2>&1
} | tee "$log"
printf 'Saved %s\n' "$log"
