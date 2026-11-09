# Experimental PowerVR driver for Orange Pi Zero 3W / Zero 4

Build and install the Allwinner A733 PowerVR BXM-4-64 vendor driver on **DietPi (Debian 13) on Zero 3W or Orange Pi Debian 13 on Zero 4, with the sun60iw2 6.6 kernel**. This directory is the complete source release: it downloads its pinned donor image, extracts the matching source/firmware/libraries without mounting, builds the module, and produces one local `.deb`.

> **VERY EXPERIMENTAL — for a spare, easily reimaged system.**

## WARNING! -- board fried!
### Orange Pi Zero 4
While compiling raylib/EGL, some testing was performed. Raylib did appear to work. I don't know if that was the cause, but it was the last thing I did before checking the board again. The board was powered off and would no longer turn on. No lights, no signs of life, nothing.

USE AT YOUR OWN PERIL!

If you're experimenting with GPU-related tasks, make sure you're using a reliable power outlet!

YOU HAVE BEEN WARNED.

> This is a community bring-up experiment, not a production graphics driver or a supported OS upgrade. Kernel crashes, display loss and boot failures are possible. Keep a working image backup and another way to reach the board. **PowerVR Vulkan cube presentation works with the optional compatibility userland and copy-presentation wrapper; broad application support remains experimental.** Installing this package does not establish that games, desktop acceleration, GLES, OpenCL or video acceleration work.

## What actually works

| Test | Result on the development board |
|---|---|
| Native module build | Passed on Zero 3W; Zero 4 build validation described in docs/BOARDS.md |
| Hardware probe | PowerVR BXM-4-64 MC1, BVNC `36.56.104.183` |
| Firmware loading | Both matching firmware images loaded |
| Local `.deb` installation | User installed version `24.2.6603887-1` successfully |
| Installed Vulkan enumeration | Passed; device API `1.3.277`, DDK `24.2@6603887` |
| Optional vendor EGL/GLES readback | Passed as root and normal user on render/display nodes; PowerVR GLES 3.2 |
| Display GBM buffer sharing | Display-node allocation/export and PowerVR import/render/readback passed |
| Physical PowerVR Sway | Implicit-layout workaround passed; native Wayland session ran 22 minutes and exited cleanly |
| Xorg device selection | Fixed by the optional `sunxi-drm` primary configuration |
| Xorg accelerated rendering | Unresolved; observed log uses llvmpipe/DRISWRAST |
| Vulkan/XCB cube | **Visible 120-frame test passed** with renderer import compatibility and `sw,linear` copy presentation |
| Native Vulkan Wayland WSI | This donor driver does not advertise `VK_KHR_wayland_surface` |
| Suspend/resume, long workloads, clean-image install | Not verified |

The tested baseline is Orange Pi Zero 3W, ARM64, Debian 13, kernel `6.6.98-vendor-sun60iw2`, kernel and header packages `26.11.0-trunk-dietpi1`, with approximately 6 GB RAM. Orange Pi Zero 4 now has a tested Debian 13 bring-up path (`6.6.98-sun60iw2`, image/header `1.0.0`), with working headless graphics checks and user-confirmed Sway; mainline kernels remain outside this release's scope. Other releases within the vendor 6.6 line are accepted by the script but remain untested.

## Install for your platform

Run **one** of these on the target board, as your normal user with sudo access:

```bash
# Orange Pi Zero 3W / DietPi based on Debian 13
./scripts/install-opz3w-dietpi.sh
```

```bash
# Orange Pi Zero 4 / Orange Pi Debian 13
./scripts/install-opz4-debian.sh
```

Both default to `setup`: dependencies, matching headers, test tools, shared native
ARM64 driver/private EGL builds, installation, video/render access, and headless
verification. They do not start a desktop or reboot. **Log out of the local TTY
completely and back in after setup**, then check `id -nG` includes `video` and
`render` before running `powervr-sway`. Restarting Codex alone does not refresh
login groups.

The Zero 3W path keeps the DietPi `vendor-sun60iw2` package names; the Zero 4 path
uses `current-sun60iw2` and can install exact headers shipped in `/opt` when they
are missing from apt. There is no Zero 4 DietPi installer in this release.
Historical `orangepi-zero3w-powervr` package names remain on both boards.

See [complete platform installation instructions](docs/INSTALL.md), including
individual commands, local header packages, minimal headless setup and testing.
Pass `help` to either platform script to inspect commands before making changes.

```bash
./install.sh boards
./install.sh board                     # auto-detect, or BOARD_ENV=opz3w / opz4
./scripts/install-opz4-debian.sh help
JOBS=1 ARCH=arm64 ./scripts/install-opz4-debian.sh setup
```

`ARCH=aarch64` is also accepted; other architectures and cross-compilation are
not supported by the pinned ARM64 runtime. Native builds scale jobs to available
RAM. Board selection never bypasses hardware checks. The observed Zero 4 image
uses the shared `xunlong,orangepi-4-pro` compatible; see [board identity and
validation](docs/BOARDS.md) before using a different image.

The build downloads this exact [Radxa donor release](https://github.com/radxa-build/radxa-cubie-a7z/releases/tag/rsdk-t7),
verifies the pinned SHA256 and published SHA512, and extracts only required inputs.
It needs about 1.1 GiB download and 16 GiB free space during extraction.
**Do not flash the Radxa image onto the Orange Pi.** An existing exact donor can
be selected with `./scripts/install-opz4-debian.sh setup /absolute/path/to/donor.img.xz`.
Existing verified inputs are reused; core rebuilds use fresh staging directories.

Output includes:

```text
dist/orangepi-zero3w-powervr_24.2.6603887-5+opz4.kernel<KERNEL_PACKAGE_VERSION>_arm64.deb
dist/orangepi-zero3w-powervr-userland_24.2.6603887-6_arm64.deb
dist/core-package-opz4.path
dist/SHA256SUMS
```

Zero 3W core filenames/pointers contain `opz3w` instead. Inspect packages with
`dpkg-deb --info` and `dpkg-deb --contents`. Run builds serially in one checkout.

## First test

Installation does not replace a currently loaded module or reboot the board. If the module is not loaded, load it manually:

```bash
sudo modprobe pvrsrvkm
sudo powervr-run vulkaninfo --summary
```

Expected: `PowerVR B-Series BXM-4-64 MC1`, `24.2@6603887`, and successful exit. Missing DISPLAY/surface information is expected during a headless root enumeration.

Log out and back in for render-group membership, then run without sudo:

```bash
powervr-run vulkaninfo --summary
```

After this succeeds, a reboot is an experimental persistence test. Installation enables module loading on subsequent boots. After reboot verify both `lsmod | grep pvrsrvkm` and Vulkan enumeration again. Do not treat successful enumeration as successful rendering.

## Optional EGL/GLES/GBM userland

The optional revision -6 package includes the tested renderer import compatibility
path and copy-presentation wrapper. It keeps system Mesa and default sessions intact.
Follow the [userland instructions](docs/USERLAND.md):

```bash
./install.sh userland
./install.sh probe-presentation --compare
sudo ./install.sh install-userland
```

After exiting the desktop, run `powervr-sway` from a fresh local TTY without sudo.
Inside it, test `powervr-vulkan-run vkcube --wsi xcb --c 120`.

The original Zero 3W hardware run used the equivalent debugger setup; the user
has now confirmed the packaged normal Sway launcher on Zero 4. Visible Vulkan
presentation on Zero 4 still needs its own acceptance run. PowerVR renders Vulkan, while
the workaround uses CPU/copy presentation. Desktop OpenGL clients such as glxgears
still use llvmpipe. The donor does not advertise native Wayland Vulkan WSI.

Stock `powervr-run vkcube` alone is insufficient: the compositor needs the renderer
import check and Vulkan needs the copy-presentation mode. Neither missing kernel
PRIME support nor the observed crash during Xwayland failure/restart is fully fixed.
See [validation](docs/VALIDATION.md) for exact tests and remaining limitations.

## What installation changes

- Module under `/lib/modules/<kernel>/updates/orangepi-powervr/`.
- Matching firmware under `/lib/firmware/updates/`.
- Private vendor Vulkan runtime and ICD under `/opt/orangepi-powervr/`.
- `/usr/bin/powervr-run`, selecting those libraries and ICD for one command.
- `/etc/modules-load.d/orangepi-powervr.conf` for boot-time loading.
- Corresponding patched kernel-module source under `/usr/src/orangepi-powervr-24.2.6603887/`.

It does not replace system Mesa, change the global loader path, register a system-wide Vulkan ICD, install donor Xorg binaries, configure a desktop, overclock the GPU, or install VPU support. The optional Xorg configuration is supplied separately and is not installed automatically.

The module follows the board's existing GPU clock/voltage device-tree settings. No overclock overlay is included.

## Kernel updates and removal

This is an **exact-kernel package, not DKMS**. Its dependency pins the kernel package version used to build it. Rebuild for kernel updates; review apt's proposed changes if an upgrade removes or holds back this package. Keep a copy of your working `.deb` locally.

If the kernel upgrade is blocked by the installed GPU package, keep the userland
installed and prepare a replacement core package before upgrading the image:

1. Choose the new kernel package version and install its matching
   `linux-headers-vendor-sun60iw2` package first.
2. With verified `work/source/` and `work/runtime/` inputs present, run
   `bash scripts/build-package.sh --kernel-package VERSION` as your normal user.
   It targets the installed matching headers, even while the old kernel is running.
3. Install the resulting local GPU `.deb` and
   `linux-image-vendor-sun60iw2=VERSION` together in one `sudo apt install` command.
   Include `linux-headers-vendor-sun60iw2=VERSION` to keep the pair aligned.
4. After apt completes, reboot and verify the module and the opt-in graphics session.

The output filename includes the target kernel package version, and
`dist/core-package.path` records it. The build still checks header/package matching
and module vermagic. Package-version matching matters even when a vendor update
keeps the same `uname -r`. Do not remove the dependency pin or purge working
userland merely to make apt proceed. A loaded old module is not replaced in memory
by installation; a reboot is required to test the new kernel/module pairing.

To rebuild from retained verified inputs, run build again. Each core build uses fresh board-specific build/staging directories; keep `work/source/` and `work/runtime/`. Old build directories remain available for inspection.

To uninstall:

```bash
sudo apt purge orangepi-zero3w-powervr
```

Uninstalling does not unload a module currently in use, remove render-group membership, remove the separately installed optional Xorg configuration, or delete firmware installed manually before this package. Reboot after removal when appropriate. If the board cannot boot, use your backup/reimage path; a running-system uninstall command cannot recover an inaccessible system.

## Repository contents

```text
install.sh       dependency setup, download/build/install, diagnostics
scripts/         image verification/extraction, packaging, runtime wrapper
patches/         Make 4.4 and missing BSP header compatibility fixes
metadata/        donor URL, hashes and input manifests
config/          optional Xorg primary-display configuration
tests/           EGL/GBM hardware pixel-readback probe
docs/            troubleshooting, validation and changelog
```

Everything needed to orchestrate the build is here. Dependencies and the pinned vendor inputs are obtained from their original sources; this is not an offline binary distribution. There are no hardcoded paths into the developer's home directory. `work/`, `dist/`, images, binaries and diagnostic logs are ignored by Git.

## Push this release to GitHub

Run from the **release source directory**, not the outer GPU collection folder:

```bash
cd ~/projects/gpu/release
./scripts/publish.sh git@github.com:alsoxmorg/orangepi3_powervr_driver_setup.git
```

Use a normal network-connected shell. SSH uses your configured key; a repository
deploy key must have **write access**. HTTPS uses separate GitHub authentication
and will not use a deploy key just because one exists. Git author name/email must
already be configured.

The script clones once into `work/github-publish/`, then reuses that checkout on
later runs. It checks the origin URL and refuses uncommitted files or divergent
remote history. It fetches and fast-forwards the current branch, copies the current
source release to the repository root, commits changes and pushes normally. It
never force-pushes. A rerun also retries an already committed update after a failed
push. Only the source whitelist is copied: README, license, installer, scripts,
metadata, patches, configs, docs, tests and workflow. Generated packages, donor
images, diagnostic logs, work trees and the source archive stay local.

If it refuses an existing checkout, inspect it first:

```bash
git -C work/github-publish status
git -C work/github-publish log --oneline -5
```

Review uncommitted changes or resolve divergence deliberately; do not delete the
checkout or force-push to bypass the check. Updating GitHub publishes build and
installation sources, not generated vendor-containing `.deb` assets. The kernel
driver is still built locally for the target machine's kernel. See the licensing
section before distributing vendor binaries.

## Licensing and credits

Project-authored scripts and documentation use the [MIT license](LICENSE). Extracted driver source retains its original MIT/GPL notices. Vendor userspace and firmware retain their own terms. This repository does not bundle them; build them into a package locally. Do not upload generated `.deb` files or donor archives as public release assets without separately establishing redistribution permission for their contents.

Thanks to [Radxa's image build project](https://github.com/radxa-build/radxa-cubie-a7z), the [Zero 3W GPU/VPU builder](https://github.com/Incipiens/OrangePiZero3W-GPU-VPU), and [A733 PowerVR experiments](https://github.com/ayiejosh/a733-powervr-fex/tree/trixie). Their boards, donor versions and display configurations differ; upstream reports are evidence to investigate, not promises about this setup.

Related A733 experiments report GPU-compositor kernel hangs. Our user reports a working Sway session; preserve that setup while investigating. No claim is made that every compositor fails or that the current configuration is stable.
