#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$(readlink -f -- "$0")")/.."
if [ "$(id -u)" = 0 ]; then echo 'Build as a normal user.' >&2; exit 1; fi
test "$(uname -m)" = aarch64 || { echo 'Native ARM64 build required.' >&2; exit 1; }
python3 scripts/stage-userland.py "$@"
bash scripts/build-path-shim.sh "$PWD/work/userland-runtime/lib/libpowervr-dri-path.so"
temporary=$(mktemp "$PWD/work/userland-runtime/lib/import-check.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT
gcc -std=c11 -O2 -Wall -Wextra -Werror -fPIC -shared scripts/wlroots-egl-import-check.c \
  -ldl -o "$temporary"
chmod 644 "$temporary"
mv -f -- "$temporary" work/userland-runtime/lib/libpowervr-egl-import-check.so
mkdir -p work/bin dist
temporary=$(mktemp "$PWD/work/bin/egl-gbm-probe.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT
gcc -std=c11 -O2 -Wall -Wextra -Werror tests/egl-gbm-probe.c \
  -o "$temporary" -lEGL -lGLESv2 -lgbm
chmod 755 "$temporary"
mv -f -- "$temporary" work/bin/egl-gbm-probe
temporary=$(mktemp "$PWD/work/bin/wlroots-format-probe.XXXXXX")
gcc -std=c11 -O2 -Wall -Wextra -Werror tests/wlroots-format-probe.c -o "$temporary" -ldl
chmod 755 "$temporary"
mv -f -- "$temporary" work/bin/wlroots-format-probe
stage=$(mktemp -d "$PWD/work/userland-package.XXXXXX")
trap 'rm -f -- "$temporary"; rm -rf -- "$stage"' EXIT
mkdir -p "$stage/DEBIAN" "$stage/opt/orangepi-powervr/userland" \
  "$stage/usr/bin" "$stage/usr/share/doc/orangepi-zero3w-powervr-userland" \
  "$stage/usr/libexec/orangepi-powervr" "$stage/usr/share/orangepi-powervr"
cp -a work/userland-runtime/. "$stage/opt/orangepi-powervr/userland/"
for script in powervr-egl-run powervr-compositor-run powervr-xwayland powervr-sway powervr-presentation-probe powervr-vulkan-run; do
  install -m755 "scripts/$script" "$stage/usr/bin/$script"
done
install -m755 work/bin/egl-gbm-probe "$stage/usr/bin/powervr-egl-probe"
install -m755 work/bin/wlroots-format-probe "$stage/usr/bin/powervr-wlroots-format-probe"
install -m644 scripts/run-hardware-session.py "$stage/usr/libexec/orangepi-powervr/"
install -m644 config/sway-hardware-test.conf "$stage/usr/share/orangepi-powervr/"
cp tests/egl-gbm-probe.c tests/wlroots-format-probe.c scripts/egl-dri-path.c \
  scripts/wlroots-egl-import-check.c LICENSE \
  docs/USERLAND.md docs/HDMI-FAILURE-2026-10-21.md docs/PRIME-COMPAT.md docs/VALIDATION.md \
  "$stage/usr/share/doc/orangepi-zero3w-powervr-userland/"
cat > "$stage/DEBIAN/control" <<'EOF'
Package: orangepi-zero3w-powervr-userland
Version: 24.2.6603887-4
Architecture: arm64
Maintainer: Orange Pi Zero 3W PowerVR experiment <noreply@example.invalid>
Depends: orangepi-zero3w-powervr (>= 24.2.6603887-1), orangepi-zero3w-powervr (<< 24.3), libc6, libstdc++6, libgcc-s1, libdrm2, libxcb-dri2-0, libxcb-dri3-0, libxcb-present0, libxcb-randr0, libxcb-xfixes0, libxcb-sync1, libxcb-shm0, libx11-xcb1, libxcb1, libxshmfence1, libexpat1, zlib1g, coreutils, python3
Recommends: libwlroots-0.18 (>= 0.18), libwlroots-0.18 (<< 0.19)
Suggests: sway, xwayland
Section: non-free/libs
Priority: optional
Description: Experimental private PowerVR EGL GLES GBM and DRI runtime
 Opt-in legacy Mesa userland for the matching vendor DDK 24.2 core stack.
 Does not replace system Mesa or configure a default display session.
EOF
find "$stage" -type d -exec chmod 755 {} +
find "$stage/opt" "$stage/usr/share" -type f -exec chmod 644 {} +
dpkg-deb --root-owner-group --build "$stage" dist/orangepi-zero3w-powervr-userland_24.2.6603887-4_arm64.deb
(cd dist && sha256sum orangepi-zero3w-powervr-userland_24.2.6603887-4_arm64.deb > userland.SHA256SUMS)
echo 'Built optional private runtime. Installation does not start or change any desktop session.'
