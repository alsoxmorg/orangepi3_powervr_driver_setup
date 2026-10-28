# Changelog

## Optional userland add-on 24.2.6603887-4 — verified compatibility path

- Include the renderer-based linux-dmabuf import-check helper in the private runtime and enable it in opt-in `powervr-sway` sessions on wlroots 0.18.
- Add `powervr-vulkan-run`, selecting PowerVR Vulkan plus the tested `sw,linear` CPU/copy presentation workaround without changing the original core wrapper.
- Package the tested configuration without requiring GDB; preserve process-only library selection, preflight, logging, and ordinary desktop startup.
- Record visible PowerVR Vulkan cube rendering and software GLX gears presentation in the debugger-based session. Packaged normal-launcher hardware acceptance remains pending.
- Keep missing kernel PRIME import, desktop GL acceleration, Xwayland failure/restart corruption and broader stability documented as unresolved.

## Optional userland add-on 24.2.6603887-3 — HDMI negotiation candidate

- Diagnose real PowerVR Sway startup followed by output-format rejection and HDMI disablement.
- Select implicit layouts using wlroots' EGL and DRM modifier switches; hardware validation remains pending.
- Gate startup on the actual wlroots XRGB8888 format table and display-node DMA-BUF import/render/readback.
- Add display-preserving comparison diagnostics, an isolated 60-second session, fsynced logs and shutdown on output configuration failure.
- Keep the installed revision untouched while preparing the candidate; no system Mesa/default-session changes.

## Optional userland add-on 24.2.6603887-2 — private EGL search-path fix

- Correct the separate EGL DRI-driver lookup required by the compositor loading method.
- Add a process-only preload helper without exporting a vendor LIBGL driver path to native Wayland child applications.
- Verify private lookup, unchanged ordinary environment variables, and child system-EGL isolation locally.
- Record successful root GLES readback on both DRM nodes and scanout-buffer allocation/export.
- Normal-user compositor-loader hardware readback and allocation/export subsequently passed on both nodes.

## Optional userland add-on 24.2.6603887-1 — integration candidate

- Add a separate private EGL/GLES/GBM/DRI package; keep system Mesa and default sessions intact.
- Add the previously missing `libxcb-dri2-0` runtime dependency.
- Add a strict GLES FBO pixel-readback and display-buffer allocation/export probe.
- Add opt-in DRM Sway and Xwayland GLES-glamor launchers, with nested-session rejection.
- Select compositor libraries through the dynamic loader so native Wayland children retain system EGL.
- Verify new donor inputs and include them in fresh image extraction.
- Preserve original Vulkan-only package compatibility and require the matching DDK core version.

ABI-load, staging, compiler and package-layout checks pass. Earlier basic hardware readback passed; presentation and the enhanced import tests remain unverified.

## 24.2.6603887-2 — source release candidate

- Standalone source directory, with automatic pinned Radxa donor download.
- Validate both local SHA256 pin and published Radxa SHA512.
- Simplified dependency/build/install commands.
- Capture X11/Wayland context, DRI3-related evidence and bounded vkcube runs.
- Document known DRI3 presentation failure and unsupported native Wayland WSI.
- Include optional Xorg primary-display configuration without applying it globally.
- Restrict builds to the vendor sun60iw2 6.6 kernel line.

The driver source, Make compatibility patch and private Vulkan runtime selection remain the same as the manually tested `-1` package. This revision does not fix DRI3 presentation.
