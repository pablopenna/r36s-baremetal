# Plan & Status

Bare-metal AArch64 on the R36S (RK3326), SD-card only — no case opening, no
soldering, bootloader untouched.

_Last updated: 2026-06-14_

## Strategy

Let the stock U-Boot do all low-level bring-up, then hand off to our code by
replacing the "kernel" entry in `extlinux.conf`. Our image carries a valid ARM64
Linux image header, so `booti` loads it and enters with `x0 = DTB pointer`,
MMU/D-cache off, only the primary core running. Everything is a file swap on the
boot partition, so every step is reversible.

## Milestones

| # | Goal | Status |
|---|------|--------|
| 0 | Recon: confirm SoC, boot flow, display, buttons from the stock files | ✅ done |
| 1 | Build a freestanding ARM64 image U-Boot will boot (valid header) | ✅ done — `hello/hello.bin` builds & verified |
| 2 | **Fill the screen with a color** (first visible output) | 🔜 code complete (FB address auto-discovered); needs on-device test |
| 3 | Bitmap-font text blitter — draw "HELLO WORLD" | ⬜ not started |
| 4 | Read buttons (GPIO matrix + SARADC keys); react on screen | ⬜ not started |

### Milestone 2 — detail (current focus)

What's done:
- `hello.S` fills 640×480 ARGB8888 with red, then `wfi`-parks.
- Header verified: branch @0x00, magic `ARM\x64` @0x38, `image_size` set.
- Build is clean; fill loop confirmed using `str w4,[x2],#4` (32-bit).
- **Framebuffer address is auto-discovered** at boot: `fdt.c`'s
  `fdt_find_drm_logo()` parses the DTB in `x0` for the `rockchip,drm-logo`
  reserved-memory `reg` that U-Boot patches in (see README "Sources of truth";
  format confirmed ARGB8888/32bpp). Parser unit-tested on host + on the real DTB.

What's needed (on the user, on-device):
1. `make`, `./flash.sh <boot-mount>`, power on. No address editing required.
2. Sanity check (optional) from running stock ArkOS, to compare against what the
   program finds:
   ```bash
   cat /proc/device-tree/reserved-memory/drm-logo@*/reg | xxd
   dmesg | grep -i 'logo\|rockchip-drm'
   ```

Acceptance: screen turns solid red.

Risk / fallback: vendor U-Boot may **blank the panel** right before `booti`. If
the screen goes black instead of red, milestone 2 needs the harder path —
re-poking the VOP scanout + backlight (PWM) — which becomes its own sub-task.

## Open questions

- [x] Framebuffer address — resolved: auto-discovered from the DTB at runtime
      (`fdt.c`); U-Boot patches the real address into the `drm-logo` `reg`.
- [x] Pixel format — resolved: ARGB8888 / 32 bpp (chi-u-boot
      `rockchip_display.c:1057`, `s->logo.bpp = 32`).
- [~] Does the stock U-Boot leave the panel scanning out at handoff? Source says
      yes (the `logo,kernel` handoff feature), but confirm on first boot.
- [ ] Does `rockchip_display_fixup` run on the extlinux/`booti` path? If not, the
      `drm-logo` `reg` stays 0 and we hit the `FB_BASE` fallback — confirm on boot.
- [ ] Exception level on entry (EL1 vs EL2) — irrelevant for M2, matters later.

## Technical reference

### Boot chain
`BootROM → TPL (DDR init) → SPL/U-Boot + ATF(BL31) → extlinux.conf → booti`.
The bootloader lives in raw sectors before partition 1 (GPT starts at sector
32768 = 16 MiB). We never touch it.

### SD card (from `partition_info.txt`)
- p1: 512 MB FAT "EFI System" — **boot partition** (`Image`, `extlinux/`, dtbs).
- p2: 8 GB ext4 — rootfs (`root=/dev/mmcblk1p2`).
- p3: 79 GB — data.

### Stock `extlinux.conf`
```
LINUX /Image · FDT /rf3536k3ka.dtb · INITRD /uInitrd
APPEND ... console=ttyFIQ0 ...
```
We replace `LINUX` with `/hello.bin` and keep `FDT` (drop `INITRD`).

### Two DTB files
`rf3536k3ka.dtb` (loaded) and `rk3326-evb-lp3-v12-linux.dtb` are **byte-identical
content** (`diff` of the decompiled `.dts` is empty). The latter is the Rockchip
reference-board name it derives from (`model = "Rockchip rk3326 evb..."`); only
`rf3536k3ka.dtb` is actually used.

### Display
ST7703 MIPI-DSI, 640×480 (`hactive 0x280`, `vactive 0x1e0`), 4 lanes, long
`panel-init-sequence` in the DTB. Bringing DSI up from scratch is hard; the plan
is to reuse U-Boot's already-initialized framebuffer instead.

### Buttons (for milestone 4)
- `adc-keys` on SARADC — volume keys, decoded by voltage threshold.
- Custom GPIO matrix — `key-gpios = <...>` across GPIO banks (`@0xff2xxxxx`);
  dpad/face/shoulder buttons. Reading them is just polling GPIO data registers.

### No easy console
`ttyFIQ0` needs a soldered UART pad, which is out of scope. Therefore the
**screen is the only output** until milestone 3 — this is why milestone 2 (a
color fill) is the first observable result.
