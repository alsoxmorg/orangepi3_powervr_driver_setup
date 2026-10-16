#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$(readlink -f -- "$0")")/.."
test "$(id -u)" != 0 || { echo 'Build as a normal user.' >&2; exit 1; }
test "$(uname -m)" = aarch64 || { echo 'Native ARM64 build required.' >&2; exit 1; }
tr '\0' '\n' < /proc/device-tree/compatible | grep -qx 'xunlong,orangepi-zero3w' || {
  echo 'This package currently targets the Orange Pi Zero 3W only.' >&2; exit 1;
}
kernel=$(uname -r)
case "$kernel" in
  6.6.*-vendor-sun60iw2) ;;
  *) echo 'Only the vendor sun60iw2 6.6 kernel line is supported by this experiment.' >&2; exit 1 ;;
esac
headers="/lib/modules/$kernel/build"
test -f "$headers/Module.symvers" || { echo "Missing exact headers for $kernel" >&2; exit 1; }
test "$(cat "$headers/include/config/kernel.release")" = "$kernel"
image_version=$(dpkg-query -W -f='${Version}' linux-image-vendor-sun60iw2)
header_version=$(dpkg-query -W -f='${Version}' linux-headers-vendor-sun60iw2)
test "$image_version" = "$header_version" || { echo 'Kernel and header package versions differ.' >&2; exit 1; }
python3 scripts/prepare.py --verify
mkdir -p work/build dist
source_dir=work/build/img-bxm-dkms-0.1.0-1
test ! -e "$source_dir" || { echo 'Move work/build/ aside before rebuilding.' >&2; exit 1; }
cp -a work/source/img-bxm-dkms-0.1.0-1 "$source_dir"
patch -d "$source_dir" -p1 < patches/0001-use-kernel-make-intermediate-policy.patch
make -j"${JOBS:-4}" BUILD=release KERNEL_CC=gcc KERNEL_LD=ld KERNEL_NM=nm \
  KERNEL_OBJCOPY=objcopy KERNELDIR="$headers" \
  -C "$source_dir/img-bxm/linux/rogue_km/build/linux/sunxi_linux" 2>&1 | tee work/build.log
module="$source_dir/img-bxm/linux/rogue_km/binary_sunxi_linux_nulldrmws_release/target_aarch64/kbuild/pvrsrvkm.ko"
test "$(/sbin/modinfo -F vermagic "$module" | cut -d' ' -f1)" = "$kernel"
stage=work/package
test ! -e "$stage" || { echo 'Move work/package/ aside before packaging.' >&2; exit 1; }
mkdir -p "$stage/DEBIAN" "$stage/opt/orangepi-powervr/lib" \
  "$stage/lib/modules/$kernel/updates/orangepi-powervr" "$stage/lib/firmware/updates" \
  "$stage/usr/bin" "$stage/usr/share/doc/orangepi-zero3w-powervr" \
  "$stage/usr/src/orangepi-powervr-24.2.6603887" "$stage/etc/modules-load.d"
install -m644 "$module" "$stage/lib/modules/$kernel/updates/orangepi-powervr/pvrsrvkm.ko"
# Include the full corresponding patched module source, without build products.
cp -a work/source/img-bxm-dkms-0.1.0-1/. "$stage/usr/src/orangepi-powervr-24.2.6603887/"
patch -d "$stage/usr/src/orangepi-powervr-24.2.6603887" -p1 < patches/0001-use-kernel-make-intermediate-policy.patch
cp patches/*.patch "$stage/usr/share/doc/orangepi-zero3w-powervr/"
cp README.md LICENSE "$stage/usr/share/doc/orangepi-zero3w-powervr/"
cp -a docs "$stage/usr/share/doc/orangepi-zero3w-powervr/"
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
Version: 24.2.6603887-2
Architecture: arm64
Maintainer: Orange Pi Zero 3W PowerVR experiment <noreply@example.invalid>
Depends: linux-image-vendor-sun60iw2 (= $image_version), kmod, libc6, libstdc++6, libgcc-s1, libdrm2, libx11-6, libx11-xcb1, libxcb1, libxcb-dri3-0, libxcb-present0, libxcb-xfixes0, libxcb-sync1, libxcb-randr0, libxcb-shm0, libxshmfence1, libexpat1, libudev1, zlib1g
Recommends: vulkan-tools
Section: non-free/kernel
Priority: optional
Description: Experimental PowerVR BXM Vulkan stack for Orange Pi Zero 3W
 Built for $kernel from donor DDK 24.2.6603887.
 Private userspace libraries selected with powervr-run.
EOF
cat > "$stage/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
if [ "\$1" = configure ]; then
    depmod -a '$kernel'
    echo 'Installed for $kernel. Existing loaded modules are not replaced.'
    echo 'Use powervr-run vulkaninfo --summary after loading pvrsrvkm.'
    echo 'Add your login account to render, then log out and back in.'
fi
EOF
cat > "$stage/DEBIAN/postrm" <<EOF
#!/bin/sh
set -e
if [ "\$1" = remove ] || [ "\$1" = purge ]; then
    if [ -d '/lib/modules/$kernel' ]; then depmod -a '$kernel'; fi
fi
EOF
cat > "$stage/DEBIAN/preinst" <<'EOF'
#!/bin/sh
set -e
if ! tr '\000' '\n' < /proc/device-tree/compatible | grep -qx 'xunlong,orangepi-zero3w'; then
  echo 'This package targets the Orange Pi Zero 3W only.' >&2
  exit 1
fi
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
gcc --version | head -1 >> "$stage/usr/share/doc/orangepi-zero3w-powervr/build-info.txt"
dpkg-deb --root-owner-group --build "$stage" dist/orangepi-zero3w-powervr_24.2.6603887-2_arm64.deb
sha256sum dist/*.deb > dist/SHA256SUMS
echo 'Package built. Inspect with dpkg-deb --info and dpkg-deb --contents before installation.'
