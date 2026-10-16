# Experimental PowerVR driver for Orange Pi Zero 3W

Build and install the Allwinner A733 PowerVR BXM-4-64 vendor driver on **Debian 13 / DietPi with the vendor 6.6 sun60iw2 kernel**. This directory is the complete source release: it downloads its pinned donor image, extracts the matching source/firmware/libraries without mounting, builds the module, and produces one local `.deb`.

> **VERY EXPERIMENTAL — for a spare, easily reimaged system.**
> This is a community bring-up experiment, not a production graphics driver or a supported OS upgrade. Kernel crashes, display loss and boot failures are possible. Keep a working image backup and another way to reach the board. **Vulkan enumeration works; vkcube presentation currently fails.** Installing this package does not establish that games, desktop acceleration, GLES, OpenCL or video acceleration work.

## What actually works

| Test | Result on the development board |
|---|---|
| Native module build | Passed with one Make 4.4 compatibility patch |
| Hardware probe | PowerVR BXM-4-64 MC1, BVNC `36.56.104.183` |
| Firmware loading | Both matching firmware images loaded |
| Local `.deb` installation | User installed version `24.2.6603887-1` successfully |
| Installed Vulkan enumeration | Passed; device API `1.3.277`, DDK `24.2@6603887` |
| Sway/Wayland | User reports it works; compositor renderer has not been independently captured |
| Xorg device selection | Fixed by the optional `sunxi-drm` primary configuration |
| Xorg accelerated rendering | Unresolved; observed log uses llvmpipe/DRISWRAST |
| `powervr-run vkcube` | **Fails: X11 reports no DRI3 presentation support** |
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

## Why vkcube still fails

Plain `vkcube` does not select this privately installed ICD. `powervr-run vkcube` does, but the current X11 screen then reports:

```text
vulkan: No DRI3 support detected - required for presentation
```

The current package does not configure Xorg's accelerated EGL/GBM path. Xorg's software GL fallback and the rendering/display split still need integration. An Xorg `DRI 3` setting alone is not a demonstrated fix. The driver also lacks advertised native Wayland surface support, so Wayland presentation should be tested through **Xwayland/XCB**, not assumed to work natively.

Inside a graphical terminal, collect a reproducible report:

```bash
./install.sh diagnose --cube
```

This runs an explicit XCB test, collects display context, extensions, providers, driver enumeration and accessible kernel/Xorg logs, and saves them under `work/diagnostics/`. Compare Xorg and Sway/Xwayland sessions. Do not run the windowed test with sudo or from a bare TTY. See [troubleshooting](docs/TROUBLESHOOTING.md) for the current diagnosis and optional Xorg fix.

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
docs/            troubleshooting, validation and changelog
```

Everything needed to orchestrate the build is here. Dependencies and the pinned vendor inputs are obtained from their original sources; this is not an offline binary distribution. There are no hardcoded paths into the developer's home directory. `work/`, `dist/`, images, binaries and diagnostic logs are ignored by Git.

To publish this reviewed source directory into an existing GitHub repository from a normal network-connected shell:

```bash
./scripts/publish.sh https://github.com/OWNER/REPOSITORY.git
```

It clones the remote, copies only the source-release files, commits with your configured Git identity, and performs a normal push. It never force-pushes. GitHub credentials and write access must already be configured. If a commit/push fails, inspect the checkout under `work/github-publish/`; do not blindly delete and retry. Publish the source directory's contents at the repository root so the included workflow runs as written.

## Licensing and credits

Project-authored scripts and documentation use the [MIT license](LICENSE). Extracted driver source retains its original MIT/GPL notices. Vendor userspace and firmware retain their own terms. This repository does not bundle them; build them into a package locally. Do not upload generated `.deb` files or donor archives as public release assets without separately establishing redistribution permission for their contents.

Thanks to [Radxa's image build project](https://github.com/radxa-build/radxa-cubie-a7z), the [Zero 3W GPU/VPU builder](https://github.com/Incipiens/OrangePiZero3W-GPU-VPU), and [A733 PowerVR experiments](https://github.com/ayiejosh/a733-powervr-fex/tree/trixie). Their boards, donor versions and display configurations differ; upstream reports are evidence to investigate, not promises about this setup.

Related A733 experiments report GPU-compositor kernel hangs. Our user reports a working Sway session; preserve that setup while investigating. No claim is made that every compositor fails or that the current configuration is stable.
