#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$(readlink -f -- "$0")")/.."
mkdir -p work/bin work/diagnostics
export POWERVR_USERLAND_ROOT=${POWERVR_USERLAND_ROOT:-"$PWD/work/userland-runtime"}
export POWERVR_DRI_PATH_SHIM="$PWD/work/bin/libpowervr-dri-path.so"
bash scripts/build-path-shim.sh "$POWERVR_DRI_PATH_SHIM"
for probe in egl-gbm-probe wlroots-format-probe; do
  temporary=$(mktemp "$PWD/work/bin/$probe.XXXXXX")
  trap 'rm -f -- "$temporary"' EXIT
  libraries=(-ldl)
  if [ "$probe" = egl-gbm-probe ]; then libraries=(-lEGL -lGLESv2 -lgbm); fi
  gcc -std=c11 -O2 -Wall -Wextra -Werror "tests/$probe.c" -o "$temporary" "${libraries[@]}"
  chmod 755 "$temporary"
  mv -f -- "$temporary" "work/bin/$probe"
done
export POWERVR_COMPOSITOR_RUN="$PWD/scripts/powervr-compositor-run"
export POWERVR_EGL_PROBE="$PWD/work/bin/egl-gbm-probe"
export POWERVR_FORMAT_PROBE="$PWD/work/bin/wlroots-format-probe"
log="$PWD/work/diagnostics/presentation-$(date -u +%Y%m%dT%H%M%SZ)-$$.log"
printf 'Read-only display preflight log: %s\n' "$log"
set +e
bash scripts/powervr-presentation-probe "$@" 2>&1 | tee "$log"
result=${PIPESTATUS[0]}
sync -f "$log"
exit "$result"
