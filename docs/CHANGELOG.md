# Changelog

## 24.2.6603887-2 — source release candidate

- Standalone source directory, with automatic pinned Radxa donor download.
- Validate both local SHA256 pin and published Radxa SHA512.
- Simplified dependency/build/install commands.
- Capture X11/Wayland context, DRI3-related evidence and bounded vkcube runs.
- Document known DRI3 presentation failure and unsupported native Wayland WSI.
- Include optional Xorg primary-display configuration without applying it globally.
- Restrict builds to the vendor sun60iw2 6.6 kernel line.

The driver source, Make compatibility patch and private Vulkan runtime selection remain the same as the manually tested `-1` package. This revision does not fix DRI3 presentation.
