# Physical Sway output failure, 2026-10-21

## What the captured session establishes

Development board: Orange Pi Zero 3W, vendor kernel `6.6.98-vendor-sun60iw2`,
Sway `1.10.1-2`, wlroots `0.18.2-3`, vendor DDK `24.2@6603887`.
Evidence: local `work/diagnostics/sway-20261021T134531Z.log`.

The DRM backend opened the Allwinner display node, initialized the PowerVR
GLES renderer, and created a GBM allocator. It then rejected XRGB8888 (`XR24`)
and RGB565 (`RG16`) while preparing the output swapchain, before creating a
working display buffer. After trying modes and fallback formats, Sway
explicitly disabled HDMI-A-1 and continued running. This explains the no-signal
screen in that session. It does not establish a kernel panic or a permanent
driver/device failure. The second session log, `sway-20261021T134654Z.log`,
contains only zero bytes and cannot explain that attempt.

## Format negotiation problem

Vendor EGL advertises multiple DMA-BUF formats. For XRGB8888, **all explicit
modifiers, including LINEAR, are marked external-only** (texture sampling, not
render targets). The log prints the implicit/INVALID modifier as renderable.
That printed implicit line is insufficient evidence: the installed wlroots
binary's format-building path can omit implicit rendering when every explicit
modifier is external-only, despite the debug line. The subsequent actual
renderer-format lookup rejected XRGB8888.

The candidate workaround selects the installed wlroots options
`WLR_EGL_NO_MODIFIERS=1` and `WLR_DRM_NO_MODIFIERS=1`, using legacy implicit
layouts for EGL negotiation and DRM allocation. This is a **candidate**, not a
verified hardware fix. It does not change the EGL driver's extension flags or
falsely clear external-only declarations. Disabling modifier queries alone
does not establish that any allocated buffer is importable, renderable, linear,
or scanout-compatible.

## New acceptance gates

Run as the desktop user, without sudo or leaving the current desktop:

```bash
./install.sh probe-presentation --compare
```

1. Compare the actual public wlroots renderer-format table before and after
   selecting implicit layouts, rather than relying on the EGL debug listing.
2. Allocate an XRGB8888 `SCANOUT|RENDERING` GBM buffer on the Allwinner node,
   export its DMA-BUF, import it into EGL on the PowerVR render node, bind it
   to a GL renderbuffer/FBO, clear it, finish rendering and check all 4096 pixels.
3. Repeat allocation/import/render/readback on the display-node EGL path.

These tests acquire no DRM master and perform no KMS commits. They do exercise
the experimental kernel graphics driver. A pass still does **not** prove a KMS
commit, synchronization during presentation, visible desktop, or Xwayland DRI3.
If any gate fails, the updated launcher refuses to start a DRM session.

Add-on revision `-3` also provides an isolated `powervr-sway --test-session`
configuration, a 60-second test limit, and a supervisor that stops its own
compositor when Sway reports output-configuration failure. The supervisor
flushes log chunks with `fsync` and records the process exit. It does not kill
unrelated sessions. A driver/kernel hang can still prevent orderly exit or
recovery; the timeout is not a guarantee against kernel failures.

## Current validation boundary

Compiler, shell/Python syntax, package layout, process-only library loading and
session-supervisor behavior are checked locally. The sandbox does not expose
`/dev/dri`, so neither the new import tests nor the candidate physical session
has been run on hardware yet. Add-on `-2` remains the installed version until
the user installs the candidate. No global Mesa or default-session change is
needed, and no display takeover was attempted during this investigation.

### Subsequent host result

The user ran the normal-user preflight at 14:21 UTC. Log
`presentation-20261021T142150Z-4920.log` reproduces the baseline format rejection
and confirms that the workaround accepts implicit/linear XRGB8888. Both the
display-to-render-node DMA-BUF import/render/readback and display-node EGL test
passed every pixel. This supersedes the untested status of those preflight
gates above. Physical presentation and Xwayland acceptance remain untested.
