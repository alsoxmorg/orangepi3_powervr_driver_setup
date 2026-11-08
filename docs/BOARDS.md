# Boards and validation

| Alias | Board / target image | Validation |
|---|---|---|
| `opz3w` | Orange Pi Zero 3W / DietPi (Debian 13) | Original tested development platform |
| `opz4` | Orange Pi Zero 4 / Orange Pi Debian 13 | Native build, installed driver, headless graphics checks and user-confirmed Sway session |

Both boards use A733/PowerVR BXM-4-64. The shared runtime does not remove kernel,
firmware, clock, device-tree or display acceptance requirements. `tested` in the
manifest records bring-up results, not production stability or broad app support.
Zero 4 uses Debian here because a DietPi image is not part of this supported setup.
See [platform installers](INSTALL.md) for complete commands.

## Selection and identity

`config/board.env` defaults to `BOARD_ENV=""` for device-tree auto-detection.
An existing environment value takes precedence. The platform installers explicitly
select their own profile; an unsupported or mismatched host is rejected.

```bash
./install.sh boards
./install.sh board
BOARD_ENV=opz3w ./install.sh board
BOARD_ENV=opz4 ARCH=arm64 ./install.sh board
```

`board` can display a profile on a different host. Actual builds/installations
check hardware. `ARCH=aarch64` normalizes to `arm64`; other architectures are
rejected, and a target board is required. Unknown and ambiguous identities fail.

Zero 3W reports `xunlong,orangepi-zero3w`. This Zero 4 image reports
`xunlong,orangepi-4-pro` and generic model `sun60iw2`; `/etc/orangepi-release`
reports `BOARD=orangepizero4`, `BOARD_NAME="Orange Pi Zero 4"`. The user confirmed
the physical board. That observed compatible is accepted for the Zero 4 profile.
It cannot distinguish a physical 4 Pro reusing the same identifier: inspect the
physical board and image before installation. `xunlong,orangepi-zero4` remains an
additional provisional expected identifier. Neither profile matches a SoC-only ID.

Collect new-image evidence before changing a profile:

```bash
tr '\0' '\n' < /proc/device-tree/compatible
tr -d '\0' < /proc/device-tree/model; echo
cat /etc/orangepi-release /etc/os-release
uname -a
dpkg-query -W 'linux-image*' 'linux-headers*'
ls -l /dev/dri
```

## Kernel/platform differences

Zero 3W retains `linux-image-vendor-sun60iw2` and
`linux-headers-vendor-sun60iw2`. Zero 4 uses `linux-image-current-sun60iw2` and
`linux-headers-current-sun60iw2`. Supported release shapes are
`6.6.*-vendor-sun60iw2` and `6.6.*-sun60iw2`. Mainline/different kernel lines
need a separate port. The same firmware and runtime files are hash-verified.

The Zero 4 image ships exact headers in `/opt`; the installer checks installed
headers first, then the matching local file, then exact-version apt headers.
Local package name/version/architecture are validated. It never substitutes
unrelated headers. Package-name overrides remain available for other matching
sun60iw2 arrangements; see INSTALL.md.

Patch 0001 addresses Make 4.4 intermediate-target policy. The stock Zero 4 header
package omits `sunxi-sid.h`; patch 0002 supplies only the exported
`sunxi_get_module_param_from_sid(u32 *, u32, u32)` declaration when the header is
missing, matching the [Orange Pi BSP declaration](https://github.com/orangepi-xunlong/linux-orangepi/blob/orange-pi-6.6-sun60iw2/bsp/include/sunxi-sid.h).
No SID stub, fixed bin or voltage override is added. The donor defaults disable
`SUPPORT_LINUX_DVFS`; if enabled, MODPOST must resolve the real kernel symbol.
Both patches are included in corresponding packaged sources on both platforms.

## Verified Zero 4 bring-up (2026-11-08)

- ARM64 Debian 13, about 4 GB RAM, kernel `6.6.98-sun60iw2`, image/header packages
  `1.0.0`; native build, MODPOST and link passed. Module vermagic matches the host.
- Hardware BVNC `36.56.104.183`, one core; both matching firmware images loaded.
- Vulkan enumeration: PowerVR B-Series BXM-4-64 MC1, API `1.3.277`, DDK `24.2@6603887`.
- GLES 3.2 clear/readback: all 256 pixels match. Implicit DMA-BUF import/render/
  readback: all 4096 pixels match. Root and a fresh normal-user process passed.
- Display-node SCANOUT|RENDERING allocation/export to PowerVR import/render passed,
  as did display-node EGL rendering and wlroots implicit XRGB8888 negotiation.
  Baseline format negotiation fails; the wrappers enable the working implicit mode.
- The user confirmed `powervr-sway` works after fixing video-group access and
  refreshing the login session. No additional Zero 4 visible Vulkan benchmark
  or long workload result was captured by the agent.

The DTS omits the default GPU clock property; the driver logged its 600 MHz
fallback at 800 mV. No clock/voltage override was applied. Reboot persistence,
suspend/resume, long workloads and broader applications remain unverified.
See USERLAND.md for the inherited PRIME/WSI workarounds and limitations.

## Packaging and memory

Historical Debian names `orangepi-zero3w-powervr` and
`orangepi-zero3w-powervr-userland` remain for upgrade compatibility on both boards.
Core revision -5 packages encode board/platform/architecture/kernel details and
pin the exact kernel image package version. Their standalone preinst guards
check board and ARM64 without Python. Userland revision -6 is shared and includes
permission diagnostics; it keeps the existing graphics compatibility path.

Each core build uses fresh `work/build-ALIAS.*` and `work/package-ALIAS.*`
directories and writes `dist/core-package-ALIAS.path` only after success.
The legacy untagged pointer is accepted only for Zero 3W. Default build jobs are
bounded by CPU count, available memory (about 768 MiB/job) and a cap of four;
`JOBS` explicitly overrides it. Shared donor/userland areas require serial builds
or separate checkouts. Kernel upgrades require rebuilding the exact-kernel core;
this is not DKMS.
