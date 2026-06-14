/*
 * R36S bare-metal "hello world" for RK3326 (4x Cortex-A35, AArch64).
 *
 * Strategy: we are loaded and entered by the stock U-Boot via `booti`,
 * exactly the way the Linux kernel /Image is. U-Boot has already done DDR
 * init, clocks, power, AND has turned the MIPI-DSI panel on to draw the
 * boot logo -- so a framebuffer is live in RAM at handoff. All we do is
 * write pixels into it.
 *
 * Entry conditions (ARM64 Linux boot protocol):
 *   - MMU off, D-cache off, I-cache may be on.
 *   - x0 = physical address of the DTB. x1..x3 = 0 (reserved).
 *   - We may be at EL2 or EL1; doesn't matter for this task.
 *   - Only the primary CPU is running; the others are parked.
 *
 * Milestone: fill the whole screen with a solid color. A red screen means
 * your own code is executing on bare metal and you own the display.
 */

/* ====================================================================== */
/*  EDIT THESE to match your panel / U-Boot framebuffer.                  */
/*                                                                        */
/*  FB_BASE is the ONE value you must discover (see README "Finding the   */
/*  framebuffer"). 0 is a deliberately-invalid placeholder so you don't   */
/*  forget. The panel is 640x480 per the device tree.                     */
/* ====================================================================== */
.equ FB_BASE,  0x00000000          /* <-- EDIT: physical FB address from U-Boot */
.equ FB_W,     640                 /* hactive  (0x280 in the dtb) */
.equ FB_H,     480                 /* vactive  (0x1e0 in the dtb) */
#define FB_BPP 4                   /* bytes/pixel: 4 = XRGB8888, 2 = RGB565 */
                                   /* NOTE: must be #define (not .equ) so the */
                                   /* C preprocessor #if below can see it.    */
.equ COLOR,    0x00FF0000          /* XRGB8888 red (for RGB565 use e.g. 0xF800) */

/* ---------------------------------------------------------------------- */

.section .head.text, "ax"
.global _start
_start:
    /*
     * 64-byte ARM64 Image header (Documentation/arm64/booting.rst).
     * U-Boot checks the magic at offset 0x38 and jumps to offset 0x00,
     * so code0 must branch over the header to the real entry point.
     */
    b       entry                  /* 0x00 code0: branch to entry          */
    .long   0                      /* 0x04 code1: reserved                 */
    .quad   0                      /* 0x08 text_offset: 0                  */
    .quad   _image_size            /* 0x10 image_size (effective)          */
    .quad   8                      /* 0x18 flags: bit3=1 -> 2MB-aligned any */
    .quad   0                      /* 0x20 res2                            */
    .quad   0                      /* 0x28 res3                            */
    .quad   0                      /* 0x30 res4                            */
    .long   0x644d5241             /* 0x38 magic = "ARM\x64"               */
    .long   0                      /* 0x3c res5 (PE/COFF offset, unused)   */

entry:
    /* Preserve the DTB pointer (x0) for later milestones (button/FB info). */
    mov     x19, x0

    /* Set up a small stack (PC-relative, so load address doesn't matter). */
    adrp    x1, _stack_top
    add     x1, x1, :lo12:_stack_top
    mov     sp, x1

    /* ---- Fill the framebuffer ---- */
    ldr     x2, =FB_BASE           /* dest pointer  */
    ldr     w4, =COLOR             /* pixel value   */
    ldr     w3, =(FB_W * FB_H)     /* pixel count   */

.fill_loop:
#if FB_BPP == 4
    str     w4, [x2], #4
#else
    strh    w4, [x2], #2
#endif
    subs    w3, w3, #1
    b.ne    .fill_loop

    /* Make sure the writes land before we idle (caches are off, but be tidy). */
    dsb     sy

    /* ---- Done. Park forever. ---- */
.hang:
    wfi
    b       .hang
