#!/bin/bash
# Explicit physical-session crash capture; run manually from a fresh local TTY.
set -euo pipefail
base=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)
egl_import_check=0
if [ "${1-}" = --egl-import-check ]; then egl_import_check=1; shift; fi
if [ "$(id -u)" = 0 ]; then echo 'Run as the normal desktop user, without sudo.' >&2; exit 1; fi
if [ -n "${DISPLAY-}${WAYLAND_DISPLAY-}${SWAYSOCK-}" ]; then
  echo 'Exit the desktop normally and run from a fresh local TTY.' >&2; exit 1
fi
case "$(tty)" in /dev/tty[0-9]*) ;; *) echo 'A local virtual terminal is required.' >&2; exit 1 ;; esac
command -v gdb >/dev/null || { echo 'Install the debugger first: sudo apt install gdb' >&2; exit 1; }
render= display=
for entry in /sys/class/drm/renderD* /sys/class/drm/card[0-9]*; do
  [ -f "$entry/dev" ] || continue
  driver=$(basename -- "$(readlink -f -- "$entry/device/driver")")
  name=$(basename -- "$entry")
  case "$driver:$name" in
    pvrsrvkm:renderD*) render="/dev/dri/$name" ;;
    sunxi-drm:card*) display="/dev/dri/$name" ;;
  esac
done
if [ -z "$render" ] || [ -z "$display" ]; then echo 'Required DRM devices not found.' >&2; exit 1; fi
mkdir -p "$base/work/diagnostics"
log=$(mktemp "$base/work/diagnostics/sway-backtrace-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX.log")
export WLR_BACKENDS=drm,libinput WLR_RENDERER=gles2
export WLR_DRM_DEVICES="$display" WLR_RENDER_DRM_DEVICE="$render"
export WLR_EGL_NO_MODIFIERS=1 WLR_DRM_NO_MODIFIERS=1
export WLR_XWAYLAND=/usr/bin/powervr-xwayland
unset WLR_RENDERER_ALLOW_SOFTWARE XWAYLAND_NO_GLAMOR
printf 'Debugger log: %s\n' "$log"
if ! /usr/bin/powervr-presentation-probe >> "$log" 2>&1; then
  sync -f "$log"
  echo 'Preflight failed; desktop was not started.' >&2; exit 1
fi
sync -f "$log"
# Match the installed compositor wrapper while debugging the ELF directly.
runtime=/opt/orangepi-powervr/userland
preload="$runtime/lib/libpowervr-dri-path.so"
if [ "$egl_import_check" = 1 ]; then
  version=$(dpkg-query -W -f='${Version}' libwlroots-0.18 2>/dev/null || true)
  case "$version" in 0.18.*) ;; *) echo 'Import-check experiment requires installed wlroots 0.18.' >&2; exit 1 ;; esac
  mkdir -p "$base/work/bin"
  temporary=$(mktemp "$base/work/bin/egl-import-check.XXXXXX")
  trap 'rm -f -- "$temporary"' EXIT
  gcc -std=c11 -O2 -Wall -Wextra -Werror -fPIC -shared \
    "$base/scripts/wlroots-egl-import-check.c" -ldl -o "$temporary"
  chmod 644 "$temporary"
  mv -f -- "$temporary" "$base/work/bin/libpowervr-egl-import-check.so"
  preload="$preload:$base/work/bin/libpowervr-egl-import-check.so"
  echo 'Opt-in experiment: replace PRIME precheck with actual renderer texture import.' | tee -a "$log"
fi
export GBM_DRIVERS_PATH="$runtime/lib/dri" POWERVR_PRIVATE_DRI_PATH="$runtime/lib/dri"
echo 'Starting Sway under gdb. Reproduce ONE failing X11 client, then let the debugger finish.'
echo 'The debugger will stop at a crash and record all thread stacks. No core image is generated.'
set +e
gdb --batch \
  -ex 'set pagination off' -ex 'set confirm off' \
  -ex 'handle SIGPIPE nostop noprint pass' \
  -ex run -ex "source $base/scripts/gdb-sway-stop.py" \
  --args /lib/ld-linux-aarch64.so.1 \
  --library-path "$runtime/lib:/opt/orangepi-powervr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  --preload "$preload" /usr/bin/sway -d "$@" >> "$log" 2>&1
result=$?
set -e
printf '\nDebugger exit: %s\n' "$result" >> "$log"
sync -f "$log"
echo "Saved crash/session evidence: $log"
exit "$result"
