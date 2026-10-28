# Experimental PowerVR driver for Orange Pi Zero 3W

Build and install the Allwinner A733 PowerVR BXM-4-64 vendor driver on **Debian 13 / DietPi with the vendor 6.6 sun60iw2 kernel**. This directory is the complete source release: it downloads its pinned donor image, extracts the matching source/firmware/libraries without mounting, builds the module, and produces one local `.deb`.

> **VERY EXPERIMENTAL — for a spare, easily reimaged system.**
> This is a community bring-up experiment, not a production graphics driver or a supported OS upgrade. Kernel crashes, display loss and boot failures are possible. Keep a working image backup and another way to reach the board. **PowerVR Vulkan cube presentation works with the optional compatibility userland and copy-presentation wrapper; broad application support remains experimental.** Installing this package does not establish that games, desktop acceleration, GLES, OpenCL or video acceleration work.

## What actually works

| Test | Result on the development board |
|---|---|
| Native module build | Passed with one Make 4.4 compatibility patch |
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

The tested baseline is Orange Pi Zero 3W, ARM64, Debian 13, kernel `6.6.98-vendor-sun60iw2`, kernel and header packages `26.11.0-trunk-dietpi1`, with approximately 6 GB RAM. Other boards and mainline kernels are outside this release's scope. Other releases within the vendor 6.6 line are accepted by the script but remain untested.

## Quick start

Download this repository as an archive and extract it, or clone it. In the directory containing this README, run these commands **as your normal user**:

```bash
./install.sh deps
./install.sh build
sudo ./install.sh install
sudo usermod -aG render "$(id -un)"
```

The first step installs tools and headers matching the installed kernel package. It requires working Debian/DietPi apt repositories. The build runs without root; it downloads about **1.1 GiB** and needs approximately **16 GiB free disk space** during extraction. It may take several minutes on SD storage. If the installed kernel package is newer than the running kernel, boot the intended kernel before building.

The build automatically downloads this exact [Radxa donor release](https://github.com/radxa-build/radxa-cubie-a7z/releases/tag/rsdk-t7), verifies both the pinned SHA256 and Radxa's published SHA512, and extracts only the required inputs. The donor is a Radxa **test build**, used as an input only: **do not flash the Radxa image onto the Orange Pi**.

If the image is already available locally:

```bash
./install.sh build /absolute/path/to/radxa-cubie-a7z_bullseye_kde_t7.output_512.img.xz
```

Output:

```text
dist/orangepi-zero3w-powervr_24.2.6603887-2_arm64.deb
dist/SHA256SUMS
```

To inspect the package before installing:

```bash
dpkg-deb --info dist/*.deb
dpkg-deb --contents dist/*.deb
```

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

The optional revision -4 package includes the tested renderer import compatibility
path and copy-presentation wrapper. It keeps system Mesa and default sessions intact.
Follow the [userland instructions](docs/USERLAND.md):

```bash
./install.sh userland
./install.sh probe-presentation --compare
sudo ./install.sh install-userland
```

After exiting the desktop, run `powervr-sway` from a fresh local TTY without sudo.
Inside it, test `powervr-vulkan-run vkcube --wsi xcb --c 120`.

The successful hardware run used the equivalent debugger-based setup; the packaged
normal launcher still needs a host acceptance run. PowerVR renders Vulkan, while
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

To rebuild from the retained verified inputs, first move the generated build and package staging directories aside, then run build again. Keep `work/source/` and `work/runtime/`.

To uninstall:

```bash
sudo apt purge orangepi-zero3w-powervr
```

Uninstalling does not unload a module currently in use, remove render-group membership, remove the separately installed optional Xorg configuration, or delete firmware installed manually before this package. Reboot after removal when appropriate. If the board cannot boot, use your backup/reimage path; a running-system uninstall command cannot recover an inaccessible system.

## Repository contents

```text
install.sh       dependency setup, download/build/install, diagnostics
scripts/         image verification/extraction, packaging, runtime wrapper
patches/         Make 4.4 compatibility fix
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
