# Changelog

## Platform installers — core revision 5 / userland revision 6

- Add complete Zero 3W/DietPi and Zero 4/Orange Pi Debian 13 entry points backed
  by shared setup, dependency, build, installation and headless verification steps.
- Validate exact local headers by package/version/architecture; find Zero 4
  headers shipped in `/opt` before falling back to exact-version apt headers.
- Preserve Zero 3W vendor kernel defaults; accept the observed Zero 4 current
  kernel layout and SID header omission without substituting an efuse stub.
- Build in fresh directories for repeat runs, install both packages together and
  validate board-specific output records. Retain historical Debian package names.
- Configure video/render access for the invoking normal account; explain login
  refresh requirements and surface permission errors from the Sway preflight.
- Package the shared graphics workarounds unchanged; record the user's working
  Zero 4 Sway session and headless rendering/display-sharing checks.
- Add mock installer flow, failure-stop, header mismatch, architecture, package
  selection and permission setup tests; no root/network needed by those tests.

## Board profiles — core revision 4 / userland revision 5

- Add `BOARD_ENV=""` detection and `opz3w` / `opz4` profiles, retaining existing Debian package names.
- Mark Zero 4 unverified, with a provisional compatible identifier pending target capture.
- Bind core packages to the selected board and isolate build directories/output records.
- Select kernel package names by profile and scale build jobs to available memory.
- Include board documentation and metadata in packages; runtime graphics workarounds are unchanged.

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
