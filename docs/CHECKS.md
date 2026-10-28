# Release candidate checks

- Bash syntax: installer, build script and diagnostic script passed.
- POSIX shell syntax: installed runtime wrapper passed.
- Python sources parsed successfully; JSON metadata parsed successfully.
- Source and runtime contents verified against the pinned manifests using the existing extracted inputs.
- Direct enumeration from the installed vendor library confirms XCB/XLIB/headless support and no advertised native Wayland surface support.
- Fresh build through this release's installer completed successfully, including MODPOST and module link.
- Built package version `24.2.6603887-2`; ARM64 module vermagic matches `6.6.98-vendor-sun60iw2`.
- Package metadata pins kernel package `26.11.0-trunk-dietpi1`.
- Package maintainer-script syntax and non-mutating board preflight passed.
- All packaged runtime hashes, symlinks and isolated library paths verified. No global Mesa/loader replacement is staged.
- Downloader checksum validation accepts matching data and rejects changed or missing inputs.

The donor download could not be exercised from the restricted developer sandbox (GitHub DNS is unavailable). The automatic download/extraction path therefore remains a clean-machine acceptance item. The donor URL and published SHA512 were obtained from the official Radxa release page.

No new package was installed during source-release preparation. Host display testing must run from the logged-in desktop user's session. Local build artifacts are kept outside the clean source release directory after validation.

The GitHub workflow checks source syntax and excludes generated artifacts from tracked files. It does not claim to build or test this ARM64 board's graphics driver on an x86 runner.

## Optional userland revision -3

- Both C probes compile with `-Wall -Wextra -Werror`, and the process-only DRI-path helper builds.
- Shell/Python syntax and metadata parsing pass. The installed wlroots library exports every public API used by the dynamic format probe.
- Five session-supervisor tests pass: normal merged output, physical-output failure, a failure message split across reads, quiet-session timeout, and early failure status.
- Invalid-device checks fail cleanly; the EGL probe rejects llvmpipe instead of reporting it as a hardware pass.
- The small test configuration uses syntax documented by the installed Sway manual. Full `sway --validate` cannot complete here because the sandbox prohibits Wayland socket creation, even with an isolated headless/pixman backend.
- The ARM64 candidate package builds. The new hardware format/import tests and real presentation remain unverified because host DRM nodes are unavailable in the sandbox.

## Optional userland revision -4

- Built ARM64 package with renderer import helper and normal Sway/Vulkan launchers.
- Six supervisor tests and the import-check lifecycle/acceptance/rejection fixture pass.
- Source syntax and donor metadata parsing pass. Compilers treat warnings as errors.
- Compositor loader test selects private EGL and both process-only helpers; an exec'ed child loads system EGL without the import helper.
- Vulkan wrapper selects the PowerVR ICD and scoped `sw,linear` presentation mode.
- Extracted package scripts/docs match their sources; donor hashes, symlinks, checksum and private installation layout pass. No global configuration or maintainer scripts are added.
- The user verified the equivalent debugger-launched hardware path; packaged normal-launcher acceptance remains pending. The sandbox did not install the package or take over the display.
