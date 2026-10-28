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
- Earlier ordinary Sway works by user report. The first opt-in physical session initialized the PowerVR GLES renderer, then failed output-format negotiation and disabled HDMI.

## Source-release checks

See `CHECKS.md` for checks completed while preparing this candidate. Builds are performed against previously verified extracted inputs when the original donor is unavailable locally. Automatic download needs a normal network-connected shell; the developer sandbox cannot resolve GitHub or access the host display/DRM device nodes.

## Not proven

- Fresh download, extraction, build, install and reboot on a clean image as one uninterrupted workflow.
- vkcube rendering or presentation.
- Accelerated Xorg glamor / DRI3, native Wayland Vulkan, game compatibility.
- Suspend/resume, long-term stability, every future vendor-kernel update.
- Uninstall/reinstall recovery on a clean image.

Successful enumeration is a milestone, not a complete GPU acceptance test.

## Optional userland preparation, 2026-10-21

- Reviewed the saved nested Sway log: Wayland backend, no DRM FD, pixman renderer. This is not a physical DRM-session renderer test.
- Found missing `libxcb-dri2-0`; user installed it.
- Donor EGL/GLES/GBM and host wlroots now load together; GBM and surfaceless client extensions are advertised.
- New userland files match the original donor package MD5s and the recorded SHA256 manifest.
- EGL/GBM probe compiles with `-Wall -Wextra -Werror`.
- Staging is idempotent and rejects corrupt input before writing output.
- Process-private loader test selects donor EGL while an exec'ed child resolves system EGL with Wayland support.
- Optional userland package builds; no global Mesa/GLVND or display-server configuration is installed.
- Host root test `userland-20261021T133212Z.log` passed PowerVR GLES 3.2 pixel readback on renderD128 and card0, and display SCANOUT|RENDERING allocation/dma-buf export.
- Normal-user compositor-loader test `userland-compositor-loader-20261021T134117Z.log` passed PowerVR GLES 3.2 readback on both nodes and display SCANOUT|RENDERING allocation/dma-buf export after the EGL DRI-path fix.
- Physical PowerVR renderer initialization is observed in `sway-20261021T134531Z.log`; HDMI setup failed, so physical presentation, DRI3 and vkcube acceptance remain pending.

## HDMI failure candidate, userland revision -3

- Saved session explicitly disabled HDMI after rejecting XR24/RG16 render formats. A second log contains only NUL bytes; it cannot establish the reason for that attempt's failure.
- Added actual wlroots XRGB8888 format-table inspection and a candidate implicit-layout mode, using `WLR_EGL_NO_MODIFIERS=1` and `WLR_DRM_NO_MODIFIERS=1`.
- Extended the GLES probe with implicit DMA-BUF import, renderbuffer/FBO binding, GPU finish and all-pixel readback, including allocation on the display node and import on the render node.
- Added display-preserving `probe-presentation --compare`, mandatory launcher preflight, an isolated 60-second session, durable logging and output-failure process shutdown.
- Candidate package builds locally. Supervisor behavior is tested without DRM. **New format/import gates and the modifier workaround still require host hardware validation.** No display was taken over and no candidate package was installed from the sandbox.
- See [failure analysis](HDMI-FAILURE-2026-10-21.md) for evidence and limits.

### Host preflight passed, 2026-10-21 14:21 UTC

`presentation-20261021T142150Z-4920.log` confirms the original wlroots table rejects implicit and linear XRGB8888, while the implicit-layout workaround accepts both. Normal-user PowerVR rendering into a display-node DMA-BUF imported on the render node passed all 4096 pixels. Display-node EGL allocation/import/render/readback also passed. This validates the format workaround and tested buffer-sharing path; physical KMS presentation, visible output, Xwayland DRI3 and vkcube remain pending.

### Physical startup followed by Xwayland crash, 14:27–14:30 UTC

Both `sway-20261021T142727Z-5524.log` and `sway-20261021T142929Z-991.log` initialize the hardware session and later terminate the Sway process with signal 11 (SIGSEGV) after lazy Xwayland startup. Xwayland reports a depth-30 glamor read-format/type mismatch with software fallback. A client buffer then fails compositor DMA-BUF import with `Invalid argument`; Xwayland disconnects/restarts and Sway crashes. This identifies the observed sequence, not the precise crashing function. Kernel journal access is denied in the sandbox, and no existing core dump was found in the checked working/home directories.

These logs load the user's regular Sway configuration, not the isolated test configuration. The old supervisor's `reason=normal exit` text for negative exit codes was a labeling bug; `compositor exit -11` records SIGSEGV. Source logging now identifies signal exits explicitly. No additional desktop takeover or system installation was attempted while examining this failure.

### Additional sessions and native SDL controls, 14:42–14:46 UTC

`sway-20261021T144233Z-2561.log` ends with the user's exit shortcut and compositor status 0. `sway-20261021T144512Z-2950.log` reproduces Xwayland DMA-BUF import failure followed by Sway SIGSEGV. These compositor logs do not establish the backend or renderer selected by terminal-launched SDL programs; their terminal stderr was not captured here.

Local `desucked_tools/wmd3dx` uses SDL3 and desktop OpenGL 2.1 compatibility (including fixed-function drawing), not GLES. `wmdpaint` uses SDL3's renderer API, with the inspected configuration preferring OpenGL and Vulkan mode disabled. A generic `scripts/test-native-sdl.sh` now forces SDL3's Wayland backend, unsets DISPLAY, uses system client libraries and records client protocol/error output. This provides a native Wayland presentation control; successful client rendering is not PowerVR acceleration proof without a hardware renderer identity. No application source outside this GPU workspace was modified, and no graphical test was run from the sandbox.

### Native Wayland cube interaction passed, 15:01 UTC

`native-sdl-wmd3dx-20261021T150106Z.9sotEe.log` confirms SDL3 connected directly to Wayland, created the `wmd3dx` xdg_toplevel, and rendered the default cube. The client identifies its OpenGL renderer as **llvmpipe**, not PowerVR. Window-title updates show zoom changing from 3.00 to 3.08 and back; the user confirms manipulating the cube. The client ended with status 124 because the scripted 30-second test limit expired, with Wayland object teardown in the log. This is not a recorded client crash.

The matching compositor log `sway-20261021T145933Z-4300.log` identifies **PowerVR B-Series BXM-4-64** as Sway's GLES renderer. At inspection it contains no Xwayland startup, matching import-failure sequence or compositor-exit record. This validates a short interactive native Wayland session with CPU rendering in the client and PowerVR compositing; it does not establish native PowerVR OpenGL/Vulkan client acceleration or long-term stability.

### Resume audit, 2026-10-28

The completed `sway-20261021T145933Z-4300.log` ends at 22 minutes 8 seconds with the user's exit command and compositor status 0. No Xwayland startup or matching DMA-BUF import failure appears in that session. Installed versions remain core `24.2.6603887-1` and userland `24.2.6603887-3`, kernel `6.6.98-vendor-sun60iw2`. This is a 22-minute native desktop observation, not 22 minutes of continuous 3D workload. No newer diagnostic sessions were present.

Next investigation: capture a Sway crash backtrace on the known Xwayland reproduction. `scripts/debug-hardware-sway.sh` prepares the same private libraries and modifier workaround, runs the presentation preflight, then launches the physical session under gdb and records all thread stacks/registers/loaded libraries after a stop. Gdb must first be installed in the user's normal shell. The sandbox has not launched this physical test.

### First GDB capture, 2026-10-28 04:26 UTC

`sway-backtrace-20261028T042552Z.EcnwnQ.log` reproduces DMA-BUF import failure, Xwayland restart and SIGSEGV on the main compositor thread. The driver worker thread is waiting in `PVRSRVThreadCondWaitTimeout`; that stack does not establish a driver fault. The main thread stops at `PC=0xaaaaaabe1700`, with `x2` equal to PC and `LR=0xfffff776bd4c`. Relocating the installed Wayland server library from its recorded `.text` range places LR at offset `0xbd4c`, immediately after `blr x2` in `wl_event_loop_dispatch`. That indirect call loads the event-source interface and its dispatch function. A bad/stale event-source callback during restart is therefore a lead, not a proven root cause.

The main-thread unwind is incomplete. The original debugger script targeted ld.so and did not load Sway's relocated executable symbols. The revised capture adds those symbols using the target mappings and records the stack, event-source memory, dispatch instruction and library maps. Debugger status 0 in the first log means GDB completed its commands; the inferior still crashed. No system package or graphics configuration was changed while analyzing the capture.

### Second GDB capture, 04:33 UTC; glxgears reproducer

`sway-backtrace-20261028T043321Z.BLiUJy.log` stops at `wl_event_loop_dispatch+444` (`0xbd44`), reading the dispatch pointer through an invalid interface address. The event-source address in x0 is `0xaaaaaacb01a0`; its first word, `0xaaa0006df380`, is unmapped. This is consistent with a freed/reused or otherwise corrupted event source after the Xwayland import-error/restart sequence; ownership and the damaging operation are not yet identified. It is stronger evidence of an event-source lifetime/corruption problem than a direct crash inside the proprietary renderer.

The user identifies the reproducer as **powervr-run glxgears** and reports unwrapped glxgears does not show a window. Static loader checks resolve the same initial system GL/GLX libraries in both cases. The wrapper changes both LD_LIBRARY_PATH and Vulkan ICD selection; a dynamically selected Mesa/Vulkan fallback is a hypothesis, not an observed renderer identity. `scripts/test-x11-client.sh` isolates baseline, Vulkan-only and library-only changes with client-side Mesa logging and `glxgears -info`, one invocation at a time. These host comparisons have not yet been run. The installed wrapper was not modified.

### Controlled wrapper comparison and kernel PRIME lead, 04:44–04:56 UTC

Baseline, Vulkan-only and libraries-only runs timed out with DRI3 screen creation failure. The combined wrapped run printed **GL_RENDERER=llvmpipe**, GL 4.5 Mesa, then exited 1 as Xwayland disconnected. Matching debugger log `sway-backtrace-20261028T044246Z.dW9prj.log` reproduces the import rejection and invalid event-source interface access. Hardware Zink was not the observed renderer in this test.

The installed wlroots binary's error at `types/wlr_linux_dmabuf_v1.c:218` follows a failed `drmPrimeFDToHandle` call (disassembled call at `0x99058`, error string `0xdef60`). The vendor kernel source's `pvr_drm_generic_driver` explicitly states `prime_fd_to_handle is not supported`. Earlier EGL DMA-BUF import success therefore does not establish this separate standard DRM/GEM import capability. The optional probe flag `--check-prime` directly tests that ioctl on an exported display-node buffer without a KMS commit; its hardware result is pending. This import incompatibility and the subsequent event-source corruption must be investigated separately.

### PRIME confirmed; opt-in renderer validation candidate

The user's host `--check-prime` result confirms EINVAL (errno 22) importing an exported display buffer through the render node's standard kernel PRIME operation, after successful PowerVR texture readback. A process-only helper now uses wlroots' public custom import-check API to attempt real renderer texture import instead. It does not accept failed imports or modify kernel/protocol validation. Local fixture tests pass for accepted/rejected imports, temporary texture destruction, manager isolation and renderer/display teardown. The helper compiles cleanly and is available only through `debug-hardware-sway.sh --egl-import-check`; no package or installed launcher was changed. Real client import, visible rendering, Vulkan/XCB and stability remain untested for this candidate. See [candidate details](PRIME-COMPAT.md).

### Compatibility callback: Xwayland gears presentation passed, 05:08 UTC

`sway-backtrace-20261028T050855Z.VyYeWE.log` records installation of actual renderer texture-import validation and four initial accepted DMA-BUFs after Xwayland starts. At inspection there is no import failure or SIGSEGV in that capture. The user reports visible running `powervr-run glxgears -info`, with repeated five-second frame reports around 145–149 FPS. The GL renderer is explicitly **llvmpipe**, Mesa 25.0.7, so this verifies software GLX client presentation through the PowerVR compositor, not hardware desktop OpenGL. Vulkan/XCB presentation, teardown and longer stability remain pending.

### Vulkan advances to swapchain creation, same compatibility session

The host `powervr-run vkcube --wsi xcb --c 120` selects the PowerVR physical GPU, then aborts at `demo_prepare_buffers`, line 1486. Installed ARM64 vkcube build ID `975bafe048ec5ae2509748b9ad3e7c31a070f439` disassembly identifies this assertion as the nonzero return from `vkCreateSwapchainKHR` (call at `0xc7e0`, return check at `0xc7e4`). The compositor log continues without the earlier import rejection/SIGSEGV. The precise VkResult is not printed by vkcube; the client-only, build-ID-pinned `scripts/debug-vulkan-swapchain.sh` captures it and the requested swapchain settings inside the current graphical session. This is a new Vulkan swapchain blocker, not successful presentation.

### Swapchain result captured, 05:15 UTC

`vulkan-swapchain-20261028T051508Z.y8cKzX.log` records `vkCreateSwapchainKHR=-13`, **VK_ERROR_UNKNOWN**. Requested settings are 3 images, format 44 (B8G8R8A8_UNORM), colorSpace 0, extent 636x1029, usage COLOR_ATTACHMENT, opaque composite alpha, identity transform and FIFO presentation. No specific allocation/format/X11 cause is established by that generic result. The loaded vendor `libpvr_mesa_wsi.so` retains internal function symbols; a client-only `--trace-wsi` GDB option now records nested VkResult-returning WSI helpers and synchronous XCB request errors. That deeper host trace is pending.

### WSI failure narrowed to image creation, 05:17 UTC

`vulkan-swapchain-20261028T051744Z.k2qmmn.log` shows `wsi_swapchain_init=VK_SUCCESS`, then `wsi_create_image=VK_ERROR_UNKNOWN`, propagated through X11 swapchain creation. No native/PRIME allocation helper entry or synchronous XCB request error was logged in that trace. This narrows the failure but does not alone identify which indirect image-stage callback failed. The updated trace adds SHA256-pinned call/return sites for image creation, memory allocation, binding and finish, and records the actual Vulkan image creation flags/tiling/usage and pNext chain. No driver behavior or image flags are changed by this diagnostic.

### Exact image creation stage, 05:19 UTC

`vulkan-swapchain-20261028T051957Z.3O522l.log` records `VkImageCreateInfo` sType 14, flags 0x400, 2D BGRA8_UNORM format 44, extent 636x1029x1, DRM-format-modifier tiling 1000158000, COLOR_ATTACHMENT usage and pNext types 1000072001, 1000001002, 1000001007 and 1000158003. The driver's CreateImage call returns VK_ERROR_UNKNOWN before memory allocation, binding or X11 pixmap presentation. This does not prove which flag/extension/layout is incompatible.

The donor WSI's own debug-control table contains `buffer`, `sw`, `noshm`, `linear`, `dxgi`. Next diagnostic selects its built-in `MESA_VK_WSI_DEBUG=sw,linear` path and records the changed image parameters/result. This is an opt-in CPU/copy-presentation experiment while retaining the PowerVR Vulkan ICD, not a forced successful return or a binary/driver flag patch. Its hardware result is pending; successful swapchain creation alone would still require visible cube rendering.

### PowerVR Vulkan/XCB cube presentation passed, 2026-10-28

`vulkan-swapchain-20261028T052216Z.YDwYcY.log` confirms that `MESA_VK_WSI_DEBUG=sw,linear` changes the requested images to linear tiling (1) and removes the previous external-memory/modifier structures from the captured pNext chain. All three images create, allocate and bind successfully; swapchain creation returns VK_SUCCESS.

The user then reports a visibly working cube and normal return from:

```bash
MESA_VK_WSI_DEBUG=sw,linear timeout --kill-after=5s 30s powervr-run vkcube --wsi xcb --c 120
```

The client selects `PowerVR B-Series BXM-4-64 MC1`. This verifies one bounded Vulkan rendering/presentation workload through Xwayland in the session started with `debug-hardware-sway.sh --egl-import-check`. The `sw` setting selects a CPU/copy presentation path; it does not select the lavapipe software Vulkan ICD. It is not zero-copy presentation, desktop OpenGL acceleration, long-term stability or a generic application compatibility claim. The compatibility helper remains source-only/opt-in and has not yet been integrated into an installed release package.
