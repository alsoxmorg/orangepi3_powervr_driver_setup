#!/bin/bash
# Client-only diagnostic inside the current --egl-import-check Sway session.
set -euo pipefail
trace=()
if [ "${1-}" = --trace-wsi ]; then
  trace=(-ex "source $(dirname -- "$(readlink -f -- "$0")")/gdb-wsi-trace.py")
  shift
fi
if [ "$#" -ne 0 ]; then echo 'Usage: debug-vulkan-swapchain.sh [--trace-wsi]' >&2; exit 2; fi
if [ -z "${DISPLAY-}" ]; then echo 'Run inside the current Sway session, without sudo.' >&2; exit 1; fi
base=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)
# Breakpoints refer to this exact installed ARM64 binary. Never reuse them on
# another build merely because it reports the same source line/version.
build_id=$(readelf -n /usr/bin/vkcube | sed -n 's/.*Build ID: //p')
if [ "$build_id" != 975bafe048ec5ae2509748b9ad3e7c31a070f439 ]; then
  echo "vkcube build changed ($build_id); recalibrate breakpoints before running." >&2; exit 1
fi
if [ "${#trace[@]}" -gt 0 ]; then
  wsi_digest=$(sha256sum /opt/orangepi-powervr/lib/libpvr_mesa_wsi.so)
  if [ "${wsi_digest%% *}" != 4a2ca601e1856440e9fca9f2c1b5a8e7ce8a1d21cf65c2e8311f9eb18fd33b93 ]; then
    echo 'Vendor WSI library changed; recalibrate image-stage breakpoints first.' >&2; exit 1
  fi
fi
mkdir -p "$base/work/diagnostics"
log=$(mktemp "$base/work/diagnostics/vulkan-swapchain-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX.log")
echo "Client swapchain diagnostic: $log"
printf 'MESA_VK_WSI_DEBUG=%s\n' "${MESA_VK_WSI_DEBUG-}" > "$log"
set +e
timeout --kill-after=5s 60s gdb --batch \
  -ex 'set pagination off' -ex 'set confirm off' \
  -ex 'set environment LD_LIBRARY_PATH /opt/orangepi-powervr/lib' \
  -ex 'set environment VK_DRIVER_FILES /opt/orangepi-powervr/powervr_icd.json' \
  -ex 'set environment VK_ICD_FILENAMES /opt/orangepi-powervr/powervr_icd.json' \
  -ex starti -ex "source $base/scripts/gdb-vkcube-swapchain.py" \
  "${trace[@]}" -ex continue -ex bt -ex 'info sharedlibrary' \
  --args /usr/bin/vkcube --wsi xcb --c 120 >> "$log" 2>&1
result=$?
set -e
printf '\nDebugger exit: %s\n' "$result" >> "$log"
sync -f "$log"
sed -n '/=== vkCreateSwapchainKHR/,+4p' "$log"
if [ "${#trace[@]}" -gt 0 ]; then sed -n '/WSI TRACE/p' "$log"; fi
echo "Saved $log"
exit "$result"
