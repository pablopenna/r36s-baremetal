# R36S bare-metal hello world build.
#
#   make            -> hello.bin   (the raw ARM64 image to place on the SD card)
#   make dump       -> disassemble for inspection
#   make clean

CROSS   ?= aarch64-linux-gnu-
CC      := $(CROSS)gcc
LD      := $(CROSS)ld
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump

# -ffreestanding/-nostdlib: no libc, no runtime. We preprocess hello.S with gcc
# so the #if in the source works.
ASFLAGS := -nostdlib -ffreestanding -Wall
# C helper (fdt.c): freestanding, no stack protector / PIC runtime, position-
# independent via the default adrp small code model so U-Boot may relocate us.
CFLAGS  := -nostdlib -ffreestanding -fno-stack-protector -fno-pic \
           -Os -Wall -Wextra -march=armv8-a

OBJS := hello.o fdt.o

all: hello.bin

hello.o: hello.S
	$(CC) $(ASFLAGS) -c $< -o $@

fdt.o: fdt.c
	$(CC) $(CFLAGS) -c $< -o $@

hello.elf: $(OBJS) linker.ld
	$(LD) -T linker.ld $(OBJS) -o $@

hello.bin: hello.elf
	$(OBJCOPY) -O binary $< $@
	@echo "Built hello.bin ($$(stat -c %s hello.bin) bytes)"

dump: hello.elf
	$(OBJDUMP) -d hello.elf

clean:
	rm -f $(OBJS) hello.elf hello.bin

.PHONY: all dump clean
