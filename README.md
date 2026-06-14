# r36s-baremetal

Bare-metal (no OS) AArch64 programs for the **R36S** handheld, booted from the
SD card without opening or soldering the device.

## The device

| | |
|---|---|
| SoC | Rockchip **RK3326** |
| CPU | 4× ARM Cortex-A35, **ARMv8-A / AArch64** (64-bit) |
| Display | MIPI-DSI panel, **Sitronix ST7703**, **640×480**, 4 lanes (VOP `@ff460000` → DSI `@ff450000` → DPHY) |
| Buttons | GPIO matrix (banks at `0xff2xxxxx`) + SARADC volume keys |
| Boot | `BootROM → TPL (DDR) → SPL/U-Boot+ATF → extlinux` |

## Approach

We do **not** replace the bootloader. The stock U-Boot does all the hard low-level
bring-up (DDR, clocks, power, and it even turns the panel on for the boot logo).
We simply replace the **kernel** that `extlinux.conf` loads (`LINUX /Image`) with
our own freestanding ARM64 image. U-Boot's `booti` accepts it (it carries a valid
ARM64 image header) and jumps in with the DTB pointer in `x0`.

This is **non-destructive and fully reversible** — it only swaps a file on the
boot partition. See [`PLAN.md`](PLAN.md) for the roadmap and current status.

## Investigation & reasoning

How we got to the approach above, and why.

### What we found on the device

Everything was learned from the stock SD card (no device opening), captured in
`r36s-og-boot/`:

- **SoC / CPU.** The R36S SoC is the Rockchip **RK3326** → 4× Cortex-A35, which
  is **ARMv8-A / AArch64**. So "assembly" here is 64-bit ARM, not the 32-bit ARM
  most handheld tutorials use.
- **Boot mechanism.** The boot partition holds `Image`, `uInitrd`, two `.dtb`
  files, and `extlinux/extlinux.conf`. That `extlinux.conf` is the smoking gun:
  the device boots via **U-Boot's distro/extlinux flow**, which loads a kernel
  `Image`, an `FDT`, and an `INITRD`, then `booti`-jumps into the kernel. That is
  exactly the seam we hook into ([source](https://theroboverse.com/rockchip-rk3326-linux-sdk-boot-flow-overview-2/)).
- **The two DTBs are the same file.** Decompiling both to `.dts` and diffing
  shows **zero differences**. `rk3326-evb-lp3-v12-linux` is the Rockchip
  reference-board name the vendor derived from (`model = "Rockchip rk3326 evb
  lpddr3 v12 board"`); `rf3536k3ka` is the working alias actually referenced by
  `extlinux.conf`. Only `rf3536k3ka.dtb` matters.
- **Display.** The DTB describes a **Sitronix ST7703 MIPI-DSI panel, 640×480, 4
  lanes** (`dsi@ff450000` → `panel@0` with a long `panel-init-sequence`;
  `display-timings` give `hactive 0x280 = 640`, `vactive 0x1e0 = 480`), driven by
  the VOP at `@ff460000`. Crucially, U-Boot draws a boot logo
  (`logo,uboot = "logo.bmp"`), so the panel + a framebuffer are **already live**
  at handoff — there is a `reserved-memory/drm-logo@0` region holding it.
- **Buttons.** Two mechanisms: `adc-keys` on the SARADC (volume keys, decoded by
  voltage thresholds) and a custom **GPIO matrix** (`key-gpios = <...>` across the
  GPIO banks at `@0xff2xxxxx`) for the dpad/face/shoulder buttons. Both are just
  register reads.
- **No easy console.** The kernel cmdline uses `console=ttyFIQ0`, a UART that
  needs a soldered test pad — out of scope. So the **screen is our only output**.

### Why these choices

- **Replace the kernel, not the bootloader.** True bare metal from the BootROM
  would require DDR init (the TPL stage), which Rockchip ships as **closed binary
  blobs** — impractical to hand-write. Letting U-Boot run first gives us a sane
  machine state (RAM, clocks, power) for free, and the extlinux seam makes the
  swap a one-file change.
- **Reuse U-Boot's framebuffer instead of programming the display.** Bringing the
  MIPI-DSI path up from scratch (DPHY timing, the panel init sequence over DSI,
  VOP raster + clock tree) is the hard part of this SoC. Since U-Boot already lit
  the panel for its logo, the cheapest path to "use the display" is to **write
  pixels into the buffer it already set up**.
- **Screen first.** With no serial, a solid-color fill is the earliest result we
  can actually observe — hence milestone 2 before anything fancier.

## How the code is structured to run on the device

Three requirements make a flat program acceptable to U-Boot and able to run with
no OS underneath. See `hello/hello.S` for the concrete implementation.

1. **ARM64 Linux image header (first 64 bytes).** `booti` only checks the magic
   `ARM\x64` at offset `0x38` and jumps to offset `0x00`. So byte 0 is a branch
   over the header to the real entry, and the header advertises `image_size` and
   a `flags` bit that lets U-Boot place the image at any 2 MiB-aligned address:

   ```
   0x00  b entry        ; code0 — branch past the header
   0x08  text_offset=0
   0x10  image_size     ; from the linker (_end - _start)
   0x18  flags=8        ; bit3: relocatable to any 2MB-aligned base
   0x38  "ARM\x64"      ; magic booti looks for
   ```

2. **Honor the entry contract.** On entry: `x0` = physical DTB pointer (we save
   it for later milestones), MMU and D-cache **off**, and only the primary core
   running. We set up a small stack and otherwise run straight-line — no libc, no
   runtime, no relocations to apply ourselves.

3. **Be position-independent.** Because U-Boot may relocate the image, the code
   uses **PC-relative** addressing (`b`, `adrp` for the stack) and literal-pool
   loads for the absolute hardware constants (`FB_BASE`, `COLOR`). Nothing depends
   on the link address, so the build's link base is cosmetic.

**Build pipeline** (`Makefile`): assemble `hello.S` and compile the freestanding
helper `fdt.c` with the cross-gcc, link both with `linker.ld` (which lays out
`.head`/`.text`, reserves a 16 KiB stack, and computes `_image_size`), then
`objcopy -O binary` to strip the ELF down to the **raw image** U-Boot expects.

**Deploy** (`flash.sh`): copy `hello.bin` to the boot partition and point
`extlinux.conf`'s `LINUX` at it. We keep `FDT` (so `x0` is a valid DTB the program
parses for the framebuffer address) and drop `INITRD` (unused). The original
config is backed up for one-command restore.

## Sources of truth & how the framebuffer address was deduced

The conclusions above are not guesses — they come from reading the exact ArkOS
sources this device boots. Line numbers are from the repos' `HEAD` as fetched
**2026-06** and may drift as upstream changes.

### Repos consulted

| Repo | What it is | Authority |
|------|------------|-----------|
| [`christianhaitian/chi-u-boot`](https://github.com/christianhaitian/chi-u-boot) | The ArkOS bootloader (U-Boot fork) | **Used directly** — boot handoff, framebuffer allocation, pixel format (line cites below) |
| [`christianhaitian/linux`](https://github.com/christianhaitian/linux) | The ArkOS kernel (VOP / DRM / panel drivers) | Authoritative for the kernel-side display + DTS; cross-checked, reserved for format double-checks and later milestones |
| [`christianhaitian/oga_controls`](https://github.com/christianhaitian/oga_controls) | The gamepad input driver | Authoritative for button → GPIO mapping; to be used for milestone 4 |
| [`christianhaitian/arkos`](https://github.com/christianhaitian/arkos) (the wiki link) | Turned out to be the **OTA update distribution** (update `.zip`/`.torrent` bundles) | **Not** build source — not authoritative for code |

### The deduction (all in `chi-u-boot` `drivers/video/drm/rockchip_display.c`)

1. **The framebuffer address is allocated at runtime — there is no constant.**
   `init_display_buffer(plat->base)` (L1298) sets
   `memory_start = base + DRM_ROCKCHIP_FB_SIZE` (L139–141), where `plat->base` is
   reserved from the **top of DRAM by U-Boot's video uclass at boot**.
   `get_drm_memory()` returns `memory_start - DRM_ROCKCHIP_FB_SIZE` (L1612) — the
   live buffer. None of this is a compile-time address, so there was nothing in
   the repo to grep for. (This is why a static number couldn't be "found".)

2. **U-Boot hands that address to us inside the DTB.**
   `rockchip_display_fixup(void *blob)` (L1446) calls
   `fdt_update_reserved_memory(blob, "rockchip,drm-logo", get_drm_memory(), …)`
   (L1459) — it writes the real base/size into the `rockchip,drm-logo`
   reserved-memory node of the DTB it passes on. That is exactly the node shipped
   as a placeholder in our tree at
   [`r36s-og-boot/rf3536k3ka.dts:4416`](r36s-og-boot/rf3536k3ka.dts) —
   `reg = <0x00 0x00 0x00 0x00>` — which U-Boot overwrites at boot. So our code
   reads it from the DTB pointer U-Boot leaves in `x0`.

3. **Pixel format is ARGB8888, 32 bpp.** `s->logo.bpp = 32;` (L1057) — confirming
   `FB_BPP 4` and a 32-bit `COLOR`.

4. **The panel stays on across the handoff.** The "kernel logo" feature
   (`logo,kernel` in the DTB; logo handed from U-Boot to the kernel) means the VOP
   keeps scanning out — so the framebuffer is live when we take over.

### Why the tiny C helper (`fdt.c`) exists

Because of (1) and (2), the framebuffer address is only knowable **at runtime**,
from the DTB in `x0`. A DTB (FDT) is a big-endian, structured binary — a token
stream plus a string table — and walking it correctly is far cleaner and less
bug-prone in C than in assembly. So `fdt.c` is a small **freestanding** (no libc,
no OS) parser: `fdt_find_drm_logo()` returns the framebuffer base (or `0`, in
which case `hello.S` falls back to the compile-time `FB_BASE`). `hello.S` saves
the DTB pointer and calls it. This removes the only manual step and makes the
image correct on every boot, regardless of where U-Boot placed the buffer.

## Layout

```
hello/                 First program: fill the screen with a color.
  hello.S              AArch64 source (image header + framebuffer fill).
  fdt.c                Freestanding DTB parser: finds the framebuffer address.
  linker.ld            Position-independent link layout.
  Makefile             make -> hello.bin
  flash.sh             Reversibly install onto the boot partition (+ restore).
  README.md            Build / flash / restore walkthrough.
r36s-og-boot/          Stock boot files captured from the SD card.
  extlinux/            Original extlinux.conf.
  rf3536k3ka.dts       Decompiled device tree (the one actually loaded).
  rk3326-evb-...dts    Byte-identical duplicate (Rockchip reference name).
  partition_info.txt   SD card GPT layout.
PLAN.md                Milestones, status, technical reference, open questions.
```

## Quick start

```bash
sudo apt install gcc-aarch64-linux-gnu   # toolchain
cd hello && make                         # build hello.bin
```

The framebuffer address is discovered automatically from the DTB at boot (see
[Sources of truth](#sources-of-truth--how-the-framebuffer-address-was-deduced)),
so no editing is needed — just `./flash.sh /your/boot/mountpoint`. See
[`hello/README.md`](hello/README.md) for details and the on-device sanity check.

> **Always image the whole SD card first:**
> `sudo dd if=/dev/sdX of=r36s-backup.img bs=4M status=progress`
