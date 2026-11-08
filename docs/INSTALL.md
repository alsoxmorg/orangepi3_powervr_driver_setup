# Platform installers

Run the installer **on the target board as a normal user with sudo access**.
These are native ARM64 builds for Debian 13 derivatives with the Allwinner
sun60iw2 6.6 kernel. `ARCH=arm64` is the default; `aarch64` is accepted as an
alias. Setting ARCH does not enable cross-compilation or other GPU runtimes.

| Installer | Physical board / image | Default kernel packages |
|---|---|---|
| `scripts/install-opz3w-dietpi.sh` | Orange Pi Zero 3W / DietPi based on Debian 13 | `linux-image-vendor-sun60iw2`, `linux-headers-vendor-sun60iw2` |
| `scripts/install-opz4-debian.sh` | Orange Pi Zero 4 / Orange Pi Debian 13 | `linux-image-current-sun60iw2`, `linux-headers-current-sun60iw2` |

Here Zero 4 means **Orange Pi Zero 4**, not a generic Orange Pi 4/RK3399 board.
The Zero 4 installer targets the Debian image used in this bring-up; there is
no supported Zero 4 DietPi path in this release. Both profiles share the pinned
A733 PowerVR BXM runtime and driver, including Make/BSP-header compatibility
patches. Hardware detection remains mandatory even with explicit selection.

## Full setup

From an extracted/cloned source checkout, choose **one**:

```bash
./scripts/install-opz3w-dietpi.sh
```

```bash
./scripts/install-opz4-debian.sh
```

With no arguments, either script runs `setup`. To inspect commands without
making changes, pass `help`. Alternatively use board auto-detection:

```bash
./install.sh setup
```

Setup installs build dependencies and exact headers, then test/desktop tools;
verifies/downloads the pinned donor inputs; builds core and private userland as
your normal user; installs both packages together; adds the invoking login account
to **video and render**; loads `pvrsrvkm`; and runs Vulkan enumeration and
headless EGL/display-buffer tests as root. A failure stops subsequent steps.
Apt shows its normal installation prompts. The installer does not reboot or
launch Sway. It keeps system Mesa available and uses opt-in PowerVR wrappers.

The full tool set includes Sway/wlroots 0.18, Xwayland, seatd, foot, Mesa utilities,
Mesa Vulkan, Vulkan validation layers/development headers, GLES glmark2 for
X11/Wayland/DRM, kmscube and Wayland diagnostics. Package installation may start
normal dependency services such as seatd; it does not set a default graphics session.

A fresh donor download is about 1.1 GiB; allow about 16 GiB free during extraction.
An existing copy of the exact donor can be used:

```bash
./scripts/install-opz4-debian.sh setup /absolute/path/to/pinned-donor.img.xz
```

Verified `work/source` and `work/runtime` inputs are reused. Each core rebuild
creates fresh board-specific build/staging directories, leaving previous artifacts
available for inspection. Output records select the latest successfully built core
package per board. Do not run concurrent builds in one checkout: the donor and
userland staging areas are shared. Build serially or use separate checkouts.

## Headers on Orange Pi Debian

If exact headers are already installed, setup keeps them. Otherwise the Zero 4
path first checks `/opt/linux-headers-current-sun60iw2_VERSION_arm64.deb`.
This image shipped `/opt/linux-headers-current-sun60iw2_1.0.0_arm64.deb` even though
its apt repositories did not provide the headers.

Supply another trusted local header package with:

```bash
KERNEL_HEADERS_DEB=/absolute/path/to/headers.deb ./scripts/install-opz4-debian.sh deps
```

The local package must match the selected header package name, installed image
package version and `arm64` architecture. Without a local package, apt is asked
for `linux-headers-...=EXACT_IMAGE_VERSION`. A missing package stops setup; the
installer does not substitute generic Debian, donor, or another kernel's headers.
Boot the kernel matching the installed image/headers before the ordinary build.
Kernel upgrades can be staged explicitly with `scripts/build-package.sh
--kernel-package VERSION`, as described in the README.

`KERNEL_IMAGE_PACKAGE` and `KERNEL_HEADERS_PACKAGE` can override installed package
names. `JOBS=1` lowers build parallelism; the default scales to available RAM.
The script still requires the sun60iw2 6.6 kernel line, exact header release,
Module.symvers, image/header versions and matching module vermagic.

## Individual steps

Every platform wrapper accepts the same commands as `install.sh`:

```bash
./scripts/install-opz4-debian.sh deps
./scripts/install-opz4-debian.sh test-tools
./scripts/install-opz4-debian.sh build
./scripts/install-opz4-debian.sh userland
sudo ./scripts/install-opz4-debian.sh install-all
sudo ./scripts/install-opz4-debian.sh access YOUR_LOGIN_USER
sudo ./scripts/install-opz4-debian.sh verify
```

Substitute `install-opz3w-dietpi.sh` for the Zero 3W. For a minimal headless build,
omit `test-tools`; `deps`, `build`, `userland`, `install-all` install the graphics
stack and wrappers without explicitly requesting a desktop/tool suite. The core
package alone can be installed with `install` after `build`.

## First normal-user session

**Log out of the local TTY completely and log back in after setup.** Restarting
Codex or an application does not refresh the parent shell's groups. Verify:

```bash
id -nG
powervr-run vulkaninfo --summary
powervr-presentation-probe --compare
```

Groups should include `video` and `render`. Render access alone does not grant
access to `/dev/dri/card0` or a video-owned seatd socket. If needed, run
`sudo ./install.sh access YOUR_LOGIN_USER`, then log out and back in.
The launcher's preflight now prints effective groups and a permission-specific
explanation before attempting GPU tests, and displays its log tail on failure.

Exit any desktop and start from a fresh local TTY, without sudo:

```bash
powervr-sway --test-session
```

This session lasts 60 seconds. Mod4+Return opens foot; Mod4+Shift+e exits.
For an unbounded session using your normal Sway configuration, use `powervr-sway`.
Inside the session, try:

```bash
powervr-vulkan-run vkcube --wsi xcb --c 120
powervr-egl-run glmark2-es2-wayland
```

Read the reported renderer. System Mesa/ordinary GLX tools may still report
llvmpipe; installing Mesa tools does not make desktop OpenGL hardware accelerated.
The Vulkan workaround uses copy presentation; native Vulkan Wayland WSI is absent.
Session logs are under `~/.local/state/orangepi-powervr/` by default.
See [board evidence](BOARDS.md) and [userland limitations](USERLAND.md).
