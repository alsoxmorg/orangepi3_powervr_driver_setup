# Opt-in renderer import validation experiment

The host PRIME probe confirms that the vendor `pvrsrvkm` render node rejects
`DRM_IOCTL_PRIME_FD_TO_HANDLE` with EINVAL. The same display-node allocation can
be imported and rendered through the vendor EGL/services path. The installed
wlroots 0.18 default linux-dmabuf precheck uses the unsupported kernel operation.

wlroots exposes a public custom import-check callback. This experiment replaces
that check with `wlr_texture_from_dmabuf` followed by texture destruction. It
accepts only a buffer that the compositor's renderer actually imports. Normal
wlroots protocol, buffer-attribute and advertised-format validation remains in
place. This is not unconditional acceptance, a kernel PRIME implementation,
proof of correct sampling, or a fix for the separately observed event-source
corruption on client rejection/restart.

The helper interposes public creation/destruction functions without accessing
private wlroots structure layouts. It rejects imports after renderer destruction
and releases its context after display teardown. It is loaded with ld.so's
process-only `--preload`, never exported through LD_PRELOAD into applications.
The existing DRI-path helper and private vendor libraries are selected as before.
It is intended only for this installed Sway/wlroots 0.18 test combination.

## Local verification

`bash scripts/test-import-check.sh` verifies acceptance of importable buffers,
rejection on renderer-import failure, release of temporary textures, multiple
manager isolation and rejection after renderer destruction, using a fake public
API provider. It does not test real EGL, textures, Wayland clients or presentation.
The helper compiles with warnings treated as errors. Hardware acceptance remains
pending. No installed package or default configuration has been changed.

## Packaged route and host experiment

The user subsequently verified visible software GLX gears and a hardware PowerVR
Vulkan cube using this callback. Userland revision -4 includes the helper and
enables it through the normal opt-in `powervr-sway` launcher; GDB is no longer
required for ordinary use. `powervr-vulkan-run` supplies the independently needed
`sw,linear` WSI workaround. The normal packaged launcher still needs a host
acceptance run. See [current instructions](USERLAND.md) and [validation](VALIDATION.md).

From a fresh local TTY, without sudo:

```bash
bash scripts/debug-hardware-sway.sh --egl-import-check
```

The launcher builds the helper in `work/bin/`, performs the usual rendering
preflight and starts the opt-in physical session under GDB. Run one known failing
client. Logs must show that the callback was installed and report renderer
acceptance/rejection; retain the backtrace if the session fails. If successful,
first distinguish CPU client rendering from hardware client rendering and then
test the Vulkan/XCB path separately. No new default session or package is installed.

References: [wlroots custom-check API](https://wlroots-baa023.pages.freedesktop.org/wlr/types/wlr_linux_dmabuf_v1.h.html),
[renderer texture-import API](https://wlroots-baa023.pages.freedesktop.org/wlr/render/wlr_texture.h.html).
