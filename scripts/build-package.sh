#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$(readlink -f -- "$0")")/.."
requested_image_version=
if [ "$#" = 2 ] && [ "$1" = --kernel-package ]; then
  requested_image_version=$2
elif [ "$#" != 0 ]; then
  echo 'Usage: build-package.sh [--kernel-package VERSION]' >&2; exit 2
fi
test "$(id -u)" != 0 || { echo 'Build as a normal user.' >&2; exit 1; }
test "$(uname -m)" = aarch64 || { echo 'Native ARM64 build required.' >&2; exit 1; }
source scripts/board-env.sh
source scripts/install-support.sh
board_env_init check
require_native_host
image_version=$(installed_version "$KERNEL_IMAGE_PACKAGE")
header_version=$(installed_version "$KERNEL_HEADERS_PACKAGE") || {
  echo "Missing $KERNEL_HEADERS_PACKAGE. Install exact headers for $KERNEL_IMAGE_PACKAGE=$image_version before building." >&2
  exit 1
}
kernel=$(uname -r)
headers="/lib/modules/$kernel/build"
if [ -n "$requested_image_version" ]; then
  test "$requested_image_version" = "$header_version" || {
    echo 'Install headers matching the requested kernel package version first.' >&2; exit 1;
  }
  release_file=$(dpkg-query -L "$KERNEL_HEADERS_PACKAGE" | grep '/include/config/kernel.release$')
  test -f "$release_file" || { echo 'Cannot identify the installed header tree.' >&2; exit 1; }
  headers=${release_file%/include/config/kernel.release}
  kernel=$(cat "$release_file")
  image_version=$requested_image_version
else
  test "$image_version" = "$header_version" || {
    echo 'Kernel/header package versions differ. To prepare an upgrade, explicitly use --kernel-package VERSION with matching installed headers.' >&2; exit 1;
  }
fi
case "$kernel" in
  6.6.*-vendor-sun60iw2|6.6.*-sun60iw2) ;;
  *) echo 'Only the vendor/current sun60iw2 6.6 kernel line is supported by this experiment.' >&2; exit 1 ;;
esac
test -f "$headers/Module.symvers" || { echo "Missing exact headers for $kernel" >&2; exit 1; }
test "$(cat "$headers/include/config/kernel.release")" = "$kernel"
test "$image_version" = "$header_version" || { echo 'Kernel and header package versions differ.' >&2; exit 1; }
kernel_tag=${image_version//:/+}
package_version="24.2.6603887-5+$BOARD_ENV.kernel$kernel_tag"
package_name="orangepi-zero3w-powervr_${package_version}_arm64.deb"
printf 'Building for kernel %s, kernel/header package %s\n' "$kernel" "$image_version"
python3 scripts/prepare.py --verify
mkdir -p work dist
build_dir=$(mktemp -d "$PWD/work/build-$BOARD_ENV.XXXXXX")
source_dir="$build_dir/img-bxm-dkms-0.1.0-1"
cp -a work/source/img-bxm-dkms-0.1.0-1 "$source_dir"
for fix in patches/*.patch; do patch -d "$source_dir" -p1 < "$fix"; done
make -j"${JOBS:-4}" ARCH="$ARCH" BUILD=release KERNEL_CC=gcc KERNEL_LD=ld KERNEL_NM=nm \
  KERNEL_OBJCOPY=objcopy KERNELDIR="$headers" \
  -C "$source_dir/img-bxm/linux/rogue_km/build/linux/sunxi_linux" 2>&1 | tee "work/build-$BOARD_ENV.log"
module="$source_dir/img-bxm/linux/rogue_km/binary_sunxi_linux_nulldrmws_release/target_aarch64/kbuild/pvrsrvkm.ko"
test "$(/sbin/modinfo -F vermagic "$module" | cut -d' ' -f1)" = "$kernel"
stage=$(mktemp -d "$PWD/work/package-$BOARD_ENV.XXXXXX")
mkdir -p "$stage/DEBIAN" "$stage/opt/orangepi-powervr/lib" \
  "$stage/lib/modules/$kernel/updates/orangepi-powervr" "$stage/lib/firmware/updates" \
  "$stage/usr/bin" "$stage/usr/share/doc/orangepi-zero3w-powervr" \
  "$stage/usr/src/orangepi-powervr-24.2.6603887" "$stage/etc/modules-load.d"
install -m644 "$module" "$stage/lib/modules/$kernel/updates/orangepi-powervr/pvrsrvkm.ko"
# Include the full corresponding patched module source, without build products.
cp -a work/source/img-bxm-dkms-0.1.0-1/. "$stage/usr/src/orangepi-powervr-24.2.6603887/"
for fix in patches/*.patch; do
  patch -d "$stage/usr/src/orangepi-powervr-24.2.6603887" -p1 < "$fix"
done
cp patches/*.patch "$stage/usr/share/doc/orangepi-zero3w-powervr/"
cp README.md LICENSE "$stage/usr/share/doc/orangepi-zero3w-powervr/"
cp -a docs "$stage/usr/share/doc/orangepi-zero3w-powervr/"
cp metadata/boards.json "$stage/usr/share/doc/orangepi-zero3w-powervr/"
install -m755 scripts/powervr-run "$stage/usr/bin/powervr-run"
printf 'pvrsrvkm\n' > "$stage/etc/modules-load.d/orangepi-powervr.conf"
python3 - "$stage" <<'PY'
from pathlib import Path
import json,shutil,sys
stage=Path(sys.argv[1]); lib=stage/'opt/orangepi-powervr/lib'
for path in json.loads(Path('metadata/runtime.json').read_text()):
    src=Path('work/runtime')/path
    if path.startswith('lib/firmware/'):
        shutil.copy2(src,stage/'lib/firmware/updates'/src.name)
    else:
        shutil.copy2(src,lib/src.name)
        if '.so.' in src.name:
            short=src.name.split('.so.')[0]+'.so'
            (lib/short).symlink_to(src.name)
            if short == 'libVK_IMG.so':
                (lib/'libVK_IMG.so.1').symlink_to(src.name)
icd={'file_format_version':'1.0.0','ICD':{'library_path':'/opt/orangepi-powervr/lib/libVK_IMG.so.24.2.6603887','api_version':'1.3.0'}}
(stage/'opt/orangepi-powervr/powervr_icd.json').write_text(json.dumps(icd,indent=2)+'\n')
PY
# Runtime dependencies cover the Vulkan driver and its dynamically loaded WSI helper.
cat > "$stage/DEBIAN/control" <<EOF
Package: orangepi-zero3w-powervr
Version: $package_version
Architecture: arm64
Maintainer: Orange Pi A733 PowerVR experiment <noreply@example.invalid>
Depends: $KERNEL_IMAGE_PACKAGE (= $image_version), kmod, libc6, libstdc++6, libgcc-s1, libdrm2, libx11-6, libx11-xcb1, libxcb1, libxcb-dri3-0, libxcb-present0, libxcb-xfixes0, libxcb-sync1, libxcb-randr0, libxcb-shm0, libxshmfence1, libexpat1, libudev1, zlib1g
Recommends: vulkan-tools
Section: non-free/kernel
Priority: optional
Description: Experimental PowerVR BXM Vulkan stack for $BOARD_NAME
 Built for $kernel from donor DDK 24.2.6603887.
 Board profile $BOARD_ENV, validation status $BOARD_STATUS.
 Private userspace libraries selected with powervr-run.
EOF
cat > "$stage/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
if [ "\$1" = configure ]; then
    depmod -a '$kernel'
    echo 'Installed for $kernel. Existing loaded modules are not replaced.'
    echo 'Use powervr-run vulkaninfo --summary after loading pvrsrvkm.'
    echo 'Run sudo ./install.sh access USER from the source tree to configure video/render access.'
    echo 'Log out of the local TTY completely and log back in before powervr-sway.'
fi
EOF
cat > "$stage/DEBIAN/postrm" <<EOF
#!/bin/sh
set -e
if [ "\$1" = remove ] || [ "\$1" = purge ]; then
    if [ -d '/lib/modules/$kernel' ]; then depmod -a '$kernel'; fi
fi
EOF
python3 scripts/boards.py --board "$BOARD_ENV" --preinst > "$stage/DEBIAN/preinst"
cat >> "$stage/DEBIAN/preinst" <<'EOF'
if [ "$1" = install ]; then
  if [ -e /opt/orangepi-powervr ] || [ -e /etc/modules-load.d/orangepi-powervr.conf ]; then
    echo 'Existing unmanaged PowerVR install detected; move it aside first.' >&2
    exit 1
  fi
  for file in /lib/firmware/updates/rgx.fw.36.56.104.183 /lib/firmware/updates/rgx.sh.36.56.104.183; do
    if [ -e "$file" ]; then
      echo "Existing firmware at $file; move it aside first." >&2
      exit 1
    fi
  done
fi
EOF
chmod 755 "$stage/DEBIAN/"{preinst,postinst,postrm}
printf '/etc/modules-load.d/orangepi-powervr.conf\n' > "$stage/DEBIAN/conffiles"
printf 'Kernel: %s\nKernel package: %s\nHeaders package: %s\n' "$kernel" "$image_version" "$header_version" > "$stage/usr/share/doc/orangepi-zero3w-powervr/build-info.txt"
printf 'Board profile: %s\nBoard name: %s\nBoard validation: %s\n' "$BOARD_ENV" "$BOARD_NAME" "$BOARD_STATUS" >> "$stage/usr/share/doc/orangepi-zero3w-powervr/build-info.txt"
printf 'Target platform: %s\nArchitecture: %s\n' "$BOARD_PLATFORM" "$ARCH" >> "$stage/usr/share/doc/orangepi-zero3w-powervr/build-info.txt"
gcc --version | head -1 >> "$stage/usr/share/doc/orangepi-zero3w-powervr/build-info.txt"
package_tmp=$(mktemp "$PWD/dist/.core-$BOARD_ENV.XXXXXX.deb")
trap 'rm -f -- "$package_tmp"' EXIT
dpkg-deb --root-owner-group --build "$stage" "$package_tmp"
chmod 644 "$package_tmp"
mv -f -- "$package_tmp" "dist/$package_name"
trap - EXIT
printf '%s\n' "$package_name" > "dist/core-package-$BOARD_ENV.path"
sha256sum dist/*.deb > dist/SHA256SUMS
echo 'Package built. Inspect with dpkg-deb --info and dpkg-deb --contents before installation.'
