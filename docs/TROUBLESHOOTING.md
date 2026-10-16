# Troubleshooting and known limits

## vkcube does not open

The reported failures on this machine are:

```text
vkcube:
  vkEnumerateInstanceExtensionProperties failed to find the VK_KHR_surface extension

powervr-run vkcube:
  Selected WSI platform: xcb
  vulkan: No DRI3 support detected - required for presentation
  Assertion `demo->gpu_number >= 0' failed
```

These are two separate failures. The first command does not select this package's private ICD. The wrapper fixes driver selection. The wrapped command then fails at X11 DRI3 presentation, before proving any cube rendering; the assertion is a consequence of failing to find a suitable presenting GPU.

The contemporaneous Xorg log reports `Refusing to try glamor on llvmpipe`, `glamor initialization failed`, `Screen 0 is not DRI2 capable`, and `DRISWRAST`. It logs initialization of the DRI3 extension machinery, which does not establish that DRI3 is usable for this screen. The installed `libxcb-dri3-0` package is already present; reinstalling it is not a fix for server-side screen support.

The likely missing integration is accelerated EGL/GBM/DRI3 for the display/render split. The current package deliberately packages Vulkan userspace only; donor Mesa EGL/GBM/DRI modules are not activated for Xorg. Adding `Option "DRI" "3"` alone does not provide that integration. A complete fix still needs an isolated Xorg EGL/GBM test, then verification of DMA-BUF/PRIME and buffer presentation on the two DRM devices.

The donor kernel source also explicitly lacks `prime_fd_to_handle`. This is a potential subsequent buffer-sharing blocker, not the proven cause of the current DRI3 detection failure. Do not add a PRIME patch and claim vkcube fixed without testing.

Vulkan enumeration checks driver initialization. A rotating cube additionally requires a working window system, presentation queue, surface and swapchain. Enumeration alone does not prove any of these.

The installed package deliberately does not register a global Vulkan ICD. Use:

```bash
powervr-run vulkaninfo --summary
```

The vendor library directly enumerates `VK_KHR_xcb_surface` and `VK_KHR_xlib_surface`; it **does not** enumerate `VK_KHR_wayland_surface` or `VK_KHR_display`. This was checked through `vkEnumerateInstanceExtensionProperties` on the actual installed driver. Native Wayland and direct-display vkcube backends cannot be assumed to work with this blob. The WSI helper contains Wayland-related strings, but strings do not establish advertised support.

Inside an Xorg terminal, or inside Sway with Xwayland running and DISPLAY set:

```bash
powervr-run vkcube --wsi xcb --c 120
```

Do not use sudo for a windowed desktop test. Do not run it from a bare TTY and expect a window. `--wsi xcb` selects the advertised X11 backend, including through Xwayland. It is a diagnostic route, not a verified fix: DMA-BUF/PRIME, buffer formats, synchronization or presentation can still fail.

To capture evidence, run **inside the graphical session**:

```bash
./install.sh diagnose --cube
```

Logs go into ignored `work/diagnostics/`. Review them before sharing; they contain user IDs and display/session paths. A timeout limits the userspace command but cannot recover a kernel deadlock. Keep another TTY/SSH session available during these experiments.

The developer sandbox cannot access the host display or DRM device nodes. The reported immediate vkcube blocker is identified, but successful presentation remains unresolved. Capture `diagnose --cube` from both an Xorg terminal and the working Sway/Xwayland session to distinguish those paths. Preserve the working Sway setup during Xorg experiments.

## Missing WSI helper

The Vulkan library opens `libpvr_mesa_wsi.so` dynamically. If the helper is absent, instance creation can return initialization failure even when ordinary `ldd` reports no missing libraries. The package's wrapper supplies both the helper and the driver's direct dependencies through its private library directory.

## Xorg reports no screens

On this board the Allwinner display controller and PowerVR rendering core are separate DRM devices. Xorg initially chose the render-only PowerVR device as its primary screen and failed with `KMS doesn't support dumb interface`.

The optional configuration matches `sunxi-drm` by driver name, independently of card numbering:

```bash
sudo install -m644 --backup=numbered config/20-sunxi-primary.conf /etc/X11/xorg.conf.d/
```

Exit the current compositor normally before starting Xorg on the same seat. A reboot is not required for this Xorg configuration. It does not enable accelerated Xorg glamor; the observed Xorg session still fell back to llvmpipe/DRISWRAST. This is separate from the reported working Sway session.

To remove the optional configuration:

```bash
sudo rm /etc/X11/xorg.conf.d/20-sunxi-primary.conf
```

## Xorg starts and immediately exits / blank session

The observed Xsession had no X11 session manager or window manager, so it launched `x-terminal-emulator`, which pointed to the Wayland-only `foot`. Foot failed because no Wayland compositor was running. For a minimal X11 session:

```bash
sudo apt install xterm
startx /usr/bin/xterm -- :0
```

Run startx from a local TTY after leaving the other graphical session. Neither missing fonts nor the optional missing fbdev driver explained that session failure.

## Permissions

`/dev/dri/renderD128` is normally owned by group `render`. Add the desktop account and start a fresh login session:

```bash
sudo usermod -aG render "$(id -un)"
```

Do not make all DRM devices world-writable.
