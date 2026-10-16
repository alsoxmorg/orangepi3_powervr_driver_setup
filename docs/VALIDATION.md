# Validation and remaining work

## Directly observed on the development machine

- Orange Pi Zero 3W / A733, vendor kernel `6.6.98-vendor-sun60iw2`.
- Matching kernel/header package `26.11.0-trunk-dietpi1`.
- Module compiles with GCC 14.2 (kernel built with GCC 13.3); MODPOST succeeds.
- Module loaded, detected hardware BVNC `36.56.104.183`, and loaded both firmware images.
- User installed the original `24.2.6603887-1` local package.
- Installed wrapper enumerated the physical GPU as Vulkan 1.3.277, DDK 24.2@6603887.
- Direct vendor extension enumeration advertises XCB/XLIB/headless surfaces, not native Wayland surfaces.
- Optional Xorg primary-display configuration changes the selected display to sunxi-drm.
- Xorg logs show software GL fallback; user reports wrapped vkcube fails because no DRI3 presentation is available.
- User reports Sway works; its actual renderer remains to be captured.

## Source-release checks

See `CHECKS.md` for checks completed while preparing this candidate. Builds are performed against previously verified extracted inputs when the original donor is unavailable locally. Automatic download needs a normal network-connected shell; the developer sandbox cannot resolve GitHub or access the host display/DRM device nodes.

## Not proven

- Fresh download, extraction, build, install and reboot on a clean image as one uninterrupted workflow.
- vkcube rendering or presentation.
- Accelerated Xorg glamor / DRI3, native Wayland Vulkan, game compatibility.
- Suspend/resume, long-term stability, every future vendor-kernel update.
- Uninstall/reinstall recovery on a clean image.

Successful enumeration is a milestone, not a complete GPU acceptance test.
