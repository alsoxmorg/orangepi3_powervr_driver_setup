# Experimental PowerVR userland, revision -4

The optional userland package installs private vendor EGL/GLES/GBM libraries,
process-only compatibility helpers and opt-in launchers. It does not replace
system Mesa, change the default desktop or restart a session during installation.

## Verified route

On 2026-10-28 the development board displayed a working PowerVR Vulkan cube
through Xwayland using renderer-based DMA-BUF validation and the vendor WSI's
`sw,linear` presentation mode. PowerVR performs Vulkan rendering; presentation
uses a CPU/copy path. The regular desktop GL gears test uses **llvmpipe**, not
hardware OpenGL. Native Vulkan Wayland WSI is not advertised by this donor.
Long-term stability, general games and arbitrary applications remain unverified.

Revision -4 packages that tested configuration so GDB is no longer required:

```bash
./install.sh userland
./install.sh probe-presentation --compare
sudo ./install.sh install-userland
```

In this development workspace, retained complete donor inputs can be selected
with `./install.sh userland --from /absolute/path/to/image-inspection/staged-root`.
Fresh checkouts should follow the README dependency and donor preparation steps.
All donor input hashes are checked before staging. Builds run without root.

Exit the current desktop normally. From a fresh **local TTY**, without sudo:

```bash
powervr-sway
```

Inside that session, from a terminal:

```bash
powervr-vulkan-run vkcube --wsi xcb --c 120
```

`powervr-vulkan-run` selects the installed core Vulkan ICD through `powervr-run`
and sets `MESA_VK_WSI_DEBUG=sw,linear` for that command and its children. The
original `powervr-run` retains its existing behavior. The new wrapper does not
supply hardware desktop OpenGL, native Wayland Vulkan or VPU/video decoding.
A different or ordinary compositor session has not been validated with this route.

For an isolated initial session, use `powervr-sway --test-session`. It runs for
60 seconds without user autostarts. Mod4+Return opens foot and Mod4+Shift+e exits.
Plain `powervr-sway` uses the user's existing configuration without a duration limit.

## What the compositor launcher selects

- The DRM/libinput backend, PowerVR GLES renderer and discovered Allwinner display
  and PowerVR render nodes; nested/root launches are rejected.
- Implicit layouts through `WLR_EGL_NO_MODIFIERS=1` and `WLR_DRM_NO_MODIFIERS=1`.
- Process-only donor library and DRI search paths, rather than exporting a private
  EGL loader into every native Wayland client.
- Renderer-based DMA-BUF validation through wlroots 0.18's public callback API.
  Each candidate buffer must actually import as a renderer texture. Ordinary
  protocol/attribute/format checks remain. Imports fail after renderer destruction.
- The scoped Xwayland GLES-glamor wrapper, presentation preflight and durable
  supervisor logging. The import helper is loaded only in the compositor process,
  not preloaded into exec'ed client applications.

The installed wlroots 0.18 ABI is required for this compatibility mode; other
versions are rejected. `powervr-compositor-run` enables the extra helper only when
`POWERVR_RENDERER_IMPORT_CHECK=1`, which `powervr-sway` explicitly sets. Merely
installing the package does not activate it in existing sessions.

## Evidence and limitations

The kernel driver does not support the standard DRM PRIME FD-to-handle import
used by wlroots' default precheck. The vendor EGL/services import path works.
The helper uses that real renderer path instead of pretending PRIME succeeded.
It does not implement missing kernel PRIME support or fix the separate
use-after-free/corruption lead seen when Xwayland rejects buffers and restarts.
The tested successful path avoids that rejection; other failures may still crash.

The unmodified vendor WSI requests modifier-tiled external-memory images that
`vkCreateImage` rejects with `VK_ERROR_UNKNOWN` on this setup. `sw,linear` changes
the image/presentation path and passed image creation, allocation, binding and
visible Vulkan cube rendering. This remains a workaround, not zero-copy support.

Preflight checks inspect the actual wlroots render-format table and test GPU
readback plus display-to-render-node DMA-BUF import/render/readback without KMS
commits. They do not guarantee presentation or protection from kernel hangs.
Keep a reachable recovery TTY/SSH connection when experimenting.

Session logs are written under `${XDG_STATE_HOME:-$HOME/.local/state}/orangepi-powervr/`
or `POWERVR_LOG_DIR`. A process supervisor flushes log chunks, identifies signal
exits, and stops its own compositor on output-configuration failure. A driver
hang can still defeat orderly shutdown or the bounded-session timeout.

See [validation](VALIDATION.md), [PRIME compatibility](PRIME-COMPAT.md), and
[initial HDMI investigation](HDMI-FAILURE-2026-10-21.md) for the development record.
The verified hardware run used the debugger launcher; acceptance of the packaged
non-debugger launcher remains the next host check.

## Undo

Exit the opt-in session and use your ordinary desktop startup. To remove the
optional package:

```bash
sudo apt purge orangepi-zero3w-powervr-userland
```

No global loader/session configuration needs restoring. The original Vulkan core
package can remain installed. Vendor binaries retain their original terms; review
redistribution rights before uploading generated packages publicly.
