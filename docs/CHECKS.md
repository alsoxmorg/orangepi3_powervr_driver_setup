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
