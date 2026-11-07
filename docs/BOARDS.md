# Board selection: BOARD_ENV

| Alias | Board | Validation |
|---|---|---|
| `opz3w` | Orange Pi Zero 3W | Tested development board |
| `opz4` | Orange Pi Zero 4 | Experimental profile; not hardware-validated |

The boards are intended to share the A733/PowerVR runtime. Sharing ARM64 or a
SoC name alone does not verify the GPU BVNC, firmware, kernel ABI, device-tree
power/clock setup or display path. No Zero 4 hardware acceptance has been run.

## Select a board

```bash
cd ~/projects/gpu/release
./install.sh boards
BOARD_ENV="" ./install.sh board       # auto-detect from device-tree compatible
BOARD_ENV=opz3w ./install.sh board    # explicit existing board
BOARD_ENV=opz4 ./install.sh board     # show experimental Zero 4 profile
```

Set `export BOARD_ENV=opz4` in your normal shell to retain a selection for build
commands, or prefix each command. An empty/unset value auto-detects. Unknown
aliases and ambiguous/unrecognized hardware are rejected. Explicit selection
does not override a different device-tree identity in dependency setup, core
builds or installation. `board` can display a target profile without asserting
that the current host matches it; actual operations perform that check.

On the target machine, once the compatible identifier is confirmed:

```bash
BOARD_ENV=opz4 ./install.sh deps
BOARD_ENV=opz4 ./install.sh build
BOARD_ENV=opz4 ./install.sh userland
sudo BOARD_ENV=opz4 ./install.sh install
sudo BOARD_ENV=opz4 ./install.sh install-userland
```

Put the assignment **after sudo**, as above, because sudo may discard exported
environment variables. Auto-detection also works when sudo drops BOARD_ENV.

## Confirm the Zero 4 before installing

`xunlong,orangepi-zero4` in `metadata/boards.json` is a **provisional expected
identifier**, not an observed hardware value or an upstream-confirmed identifier.
On the new board collect:

```bash
tr '\0' '\n' < /proc/device-tree/compatible
tr -d '\0' < /proc/device-tree/model; echo
uname -a
dpkg-query -W 'linux-image*' 'linux-headers*'
ls -l /dev/dri
```

If the identifier differs, review this evidence and correct the profile before
building/installing. Do not just add a broad SoC-only match, change the detected
model or disable the guard. A Zero 3W image/DT reused on a Zero 4 may still identify
as the Zero 3W; BOARD_ENV cannot establish the physical identity in that situation.

Both profiles currently target the existing Debian/DietPi vendor sun60iw2 6.6
kernel arrangement. A Zero 4 image with a different kernel/package layout is not
automatically supported. `KERNEL_IMAGE_PACKAGE` and `KERNEL_HEADERS_PACKAGE` can
select alternative installed package names, but the exact image/header version,
ARM64, supported kernel release and module vermagic checks still apply. A different
kernel line needs a separate port, not merely a board alias.

## Packages and memory

The existing Debian names `orangepi-zero3w-powervr` and
`orangepi-zero3w-powervr-userland` are retained for upgrade/dependency compatibility;
the name is historical, not the board detector. The core package's description,
build-info and standalone preinst guard encode the selected board. Its filename
includes the board alias and kernel package version. It validates that same board
again during installation; no Python is required by the generated preinst guard.
The shared userland contains both profiles and the same hash-verified vendor files.

Board-specific build/package directories and `dist/core-package-ALIAS.path` records
keep targets separate. Existing `dist/core-package.path` is accepted only for the
legacy Zero 3W path. Kernel upgrades still require a rebuilt core package with the
exact new image/header version; see the README.

Default build parallelism is calculated from available RAM and CPU count, capped
at four jobs and budgeted at about 768 MiB per job. A small-RAM board therefore
uses fewer workers without changing driver memory settings. `JOBS=1` (or another
positive integer) explicitly overrides it. RAM size is not hardcoded by board.

The dwl fork discovers `pvrsrvkm`/`sunxi-drm` nodes dynamically and uses shared
runtime paths; there is no Zero 3W-only C branch to remove. This does not prove dwl
works on the Zero 4. Verify the board, kernel/module, EGL/readback, DMA-BUF sharing,
physical compositor and visible Vulkan cube on that board before marking it tested.

The editable default is `config/board.env` (`BOARD_ENV=""` for detection). An already-set environment variable takes precedence, including an explicitly empty value.
