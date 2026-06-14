# R36S bare-metal hello world (RK3326 / AArch64)

A minimal freestanding ARM64 program that the stock R36S U-Boot boots in place
of the Linux kernel. It fills the 640×480 panel with a solid color — proof that
your own code runs bare metal and owns the display.

## How it works

The R36S boot chain is `BootROM → TPL (DDR) → SPL/U-Boot+ATF → extlinux`. We do
**not** touch any of that. We only replace what `extlinux.conf` loads as the
"kernel" (`LINUX`). The image carries a valid ARM64 Linux image header, so
U-Boot's `booti` accepts it, jumps in with the DTB pointer in `x0`, and we run.

U-Boot already powered the MIPI-DSI panel (ST7703, 640×480) to draw the boot
logo, so a framebuffer is alive in RAM when we take over — we just write pixels.

## 1. Install the toolchain

```bash
sudo apt install gcc-aarch64-linux-gnu
```

## 2. Build

```bash
make
```

Produces `hello.bin`.

## 3. Framebuffer address — discovered automatically

You do **not** need to find or set the address. At boot, `fdt.c`'s
`fdt_find_drm_logo()` parses the DTB U-Boot hands us (pointer in `x0`) and reads
the framebuffer base from the `rockchip,drm-logo` reserved-memory node — the value
U-Boot patches in. Pixel format is ARGB8888/32 bpp per the U-Boot source, which is
why `FB_BPP` is `4`. See the root [`README.md`](../README.md) "Sources of truth"
for the line-level reasoning.

`FB_BASE` in `hello.S` remains only as a **fallback** if the parser returns 0
(e.g. the fixup didn't run on this boot path).

Optional sanity check, from the **running stock ArkOS**, to compare against what
the program finds:

```bash
# on the R36S over SSH / a terminal:
cat /proc/device-tree/reserved-memory/drm-logo@*/reg | xxd    # physical FB addr
dmesg | grep -i 'logo\|rockchip-drm'
```

## 4. Flash to the SD card

> **Back up first** (whole card): `sudo dd if=/dev/sdX of=r36s-backup.img bs=4M status=progress`

Mount the **boot partition** (the 512 MB FAT one — `sda1` in
`../r36s-og-boot/partition_info.txt`), then:

```bash
./flash.sh /media/you/BOOT_MOUNT
```

It backs up the original `extlinux.conf`, copies `hello.bin`, and switches the
boot entry. Put the card in the R36S and power on — the screen should go red.

## 5. Restore ArkOS

```bash
./flash.sh /media/you/BOOT_MOUNT restore
```

(or restore the whole-card image you dd'd).

## Roadmap

- [x] Milestone 1/2 — run on bare metal, fill the screen (this).
- [ ] Milestone 3 — bitmap-font text blitter ("HELLO WORLD").
- [ ] Milestone 4 — read buttons by polling GPIO data registers (banks at
      `0xff2xxxxx`) and the SARADC volume keys; change color on press.

## Notes / gotchas

- No easy serial console (`ttyFIQ0` needs a soldered UART pad), so the **screen
  is your only output** until milestone 3 — that's why step 1 is a color fill.
- If the screen stays on the logo / goes black: `FB_BASE` is wrong or the format
  differs. Double-check step 3. Nothing is bricked — restore and retry.
- The code is position-independent, so U-Boot may relocate it freely.
