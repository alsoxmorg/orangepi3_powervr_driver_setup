#!/bin/bash
set -uo pipefail
cd -- "$(dirname -- "$(readlink -f -- "$0")")/.."
runtime=${POWERVR_USERLAND_ROOT:-"$PWD/work/userland-runtime"}
if [ ! -r "$runtime/lib/libEGL.so.1" ]; then
  echo 'Stage the userland first, or set POWERVR_USERLAND_ROOT to the installed runtime.' >&2
  exit 1
fi
mkdir -p work/diagnostics work/bin
mode=scoped
runner=(scripts/powervr-egl-run)
if [ "${1-}" = --compositor-loader ]; then
  mode=compositor-loader
  runner=(scripts/powervr-compositor-run)
  export POWERVR_DRI_PATH_SHIM="$PWD/work/bin/libpowervr-dri-path.so"
  bash scripts/build-path-shim.sh "$POWERVR_DRI_PATH_SHIM" || exit 1
  shift
fi
# Compile to a new file so a previous sudo run cannot leave an unwritable
# executable, and an in-flight probe keeps its original mapped binary.
temporary=$(mktemp "$PWD/work/bin/egl-gbm-probe.XXXXXX") || exit 1
trap 'rm -f -- "$temporary"' EXIT
gcc -std=c11 -O2 -Wall -Wextra -Werror tests/egl-gbm-probe.c \
  -o "$temporary" -lEGL -lGLESv2 -lgbm || exit 1
chmod 755 "$temporary"
mv -f -- "$temporary" work/bin/egl-gbm-probe || exit 1
log="work/diagnostics/userland-$mode-$(date -u +%Y%m%dT%H%M%SZ).log"
devices=("$@")
if [ "${#devices[@]}" -eq 0 ]; then
  for entry in /sys/class/drm/renderD* /sys/class/drm/card[0-9]*; do
    [ -f "$entry/dev" ] || continue
    driver=$(basename -- "$(readlink -f -- "$entry/device/driver")")
    name=$(basename -- "$entry")
    case "$driver:$name" in
      pvrsrvkm:renderD*|sunxi-drm:card*) devices+=("/dev/dri/$name") ;;
    esac
  done
fi
if [ "${#devices[@]}" -eq 0 ]; then echo 'No PowerVR/render or Allwinner/display device found.' >&2; exit 1; fi
{
  echo "Runtime: $runtime"
  echo "Loading mode: $mode"
  uname -r
  id
  export POWERVR_USERLAND_ROOT="$runtime"
  echo '=== EGL shared-library resolution ==='
  scripts/powervr-egl-run ldd "$runtime/lib/libEGL.so.1"
  status=0
  for device in "${devices[@]}"; do
    printf '\n=== EGL/GBM pixel readback on %s ===\n' "$device"
    timeout --kill-after=5s 30s "${runner[@]}" "$PWD/work/bin/egl-gbm-probe" "$device"
    result=$?
    echo "Probe exit: $result"
    if [ "$result" -ne 0 ]; then status=1; fi
  done
  exit "$status"
} 2>&1 | tee "$log"
result=${PIPESTATUS[0]}
echo "Saved $log"
exit "$result"
