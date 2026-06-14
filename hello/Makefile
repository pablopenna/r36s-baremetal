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

all: hello.bin

hello.o: hello.S
	$(CC) $(ASFLAGS) -c $< -o $@

hello.elf: hello.o linker.ld
	$(LD) -T linker.ld hello.o -o $@

hello.bin: hello.elf
	$(OBJCOPY) -O binary $< $@
	@echo "Built hello.bin ($$(stat -c %s hello.bin) bytes)"

dump: hello.elf
	$(OBJDUMP) -d hello.elf

clean:
	rm -f hello.o hello.elf hello.bin

.PHONY: all dump clean
