#!/bin/bash
# One explicit test per invocation; never runs a matrix across repeated crashes.
set -euo pipefail
if [ "$#" -lt 2 ]; then
  echo 'Usage: test-x11-client.sh baseline|wrapped|vulkan-only|libraries-only COMMAND [ARGS...]' >&2; exit 2
fi
mode=$1; shift
case "$mode" in baseline|wrapped|vulkan-only|libraries-only) ;; *) echo 'Unknown mode.' >&2; exit 2 ;; esac
if [ -z "${DISPLAY-}" ]; then echo 'Run inside the test graphical session, without sudo.' >&2; exit 1; fi
base=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)
mkdir -p "$base/work/diagnostics"
log=$(mktemp "$base/work/diagnostics/x11-$mode-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX.log")
echo "Client evidence: $log"
trap 'sync -f "$log"' EXIT
(
  # Start each comparison from the system client libraries and system ICD set.
  unset LD_LIBRARY_PATH LD_PRELOAD VK_DRIVER_FILES VK_ICD_FILENAMES
  unset LIBGL_DRIVERS_PATH GBM_DRIVERS_PATH MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER
  export LIBGL_DEBUG=verbose MESA_DEBUG=1
  case "$mode" in
    wrapped)
      export LD_LIBRARY_PATH=/opt/orangepi-powervr/lib
      export VK_DRIVER_FILES=/opt/orangepi-powervr/powervr_icd.json
      export VK_ICD_FILENAMES="$VK_DRIVER_FILES" ;;
    vulkan-only)
      export VK_DRIVER_FILES=/opt/orangepi-powervr/powervr_icd.json
      export VK_ICD_FILENAMES="$VK_DRIVER_FILES" ;;
    libraries-only) export LD_LIBRARY_PATH=/opt/orangepi-powervr/lib ;;
  esac
  printf 'Mode: %s\nDISPLAY=%s\nLD_LIBRARY_PATH=%s\nVK_DRIVER_FILES=%s\n' \
    "$mode" "$DISPLAY" "${LD_LIBRARY_PATH-}" "${VK_DRIVER_FILES-}"
  printf 'Command:'; printf ' %q' "$@"; printf '\n'
  timeout --kill-after=5s 15s "$@"
) >> "$log" 2>&1 &
client=$!
set +e
wait "$client"
result=$?
set -e
printf '\nClient test exit: %s (124 means the 15-second limit ended)\n' "$result" >> "$log"
tail -n 20 "$log"
exit "$result"
