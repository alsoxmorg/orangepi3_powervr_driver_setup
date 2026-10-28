#!/bin/bash
# Run from a terminal inside Sway. Force native SDL3 Wayland, never X11 fallback.
set -euo pipefail
if [ "$#" -lt 1 ]; then echo 'Usage: test-native-sdl.sh /path/to/SDL3-app [ARGS...]' >&2; exit 2; fi
if [ -z "${WAYLAND_DISPLAY-}" ]; then echo 'Run inside a Wayland graphical terminal, without sudo.' >&2; exit 1; fi
base=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)
mkdir -p "$base/work/diagnostics"
name=$(basename -- "$1")
log=$(mktemp "$base/work/diagnostics/native-sdl-${name//[^a-zA-Z0-9_-]/_}-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX.log")
printf 'Native Wayland client log: %s\nClose the app when done; test limit is 30 seconds.\n' "$log"
{
  printf 'Command:'; printf ' %q' "$@"; printf '\n'
  printf 'WAYLAND_DISPLAY=%s; SDL_VIDEO_DRIVER=wayland; DISPLAY unset\n' "$WAYLAND_DISPLAY"
} >> "$log"
# The donor EGL has no native Wayland platform. Use ordinary system client
# libraries here, rather than the private X11/GBM vendor wrappers. A working
# window therefore does not by itself prove GPU acceleration in the client.
set +e
timeout --kill-after=5s 30s env \
  -u DISPLAY -u LD_LIBRARY_PATH -u LD_PRELOAD -u LIBGL_DRIVERS_PATH \
  -u GBM_DRIVERS_PATH -u VK_DRIVER_FILES -u VK_ICD_FILENAMES \
  -u MESA_LOADER_DRIVER_OVERRIDE -u GALLIUM_DRIVER \
  SDL_VIDEO_DRIVER=wayland WAYLAND_DEBUG=1 "$@" >> "$log" 2>&1
result=$?
set -e
printf '\nClient exit: %s (124 means the test duration ended)\n' "$result" >> "$log"
sync -f "$log"
echo '--- Last client messages ---'
tail -n 16 "$log"
printf 'Saved %s\n' "$log"
exit "$result"
