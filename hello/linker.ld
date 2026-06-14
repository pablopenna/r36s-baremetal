/*
 * Link layout for the bare-metal image.
 *
 * The link base below is mostly cosmetic: the code is position-independent
 * (PC-relative branches, adrp for the stack, literal-pool loads for the
 * absolute FB/COLOR constants), so U-Boot is free to relocate the image to
 * whatever 2MB-aligned address it likes. The header advertises that with
 * flags bit 3.
 */
ENTRY(_start)

SECTIONS
{
    . = 0x00280000;

    .head : { KEEP(*(.head.text)) }
    .text : { *(.text*) }
    .rodata : { *(.rodata*) }
    .data : { *(.data*) }

    .bss : {
        . = ALIGN(16);
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        _bss_end = .;
    }

    /* 16 KiB stack, growing down from _stack_top */
    . = ALIGN(16);
    . = . + 0x4000;
    _stack_top = .;

    _end = .;
    _image_size = _end - _start;

    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
