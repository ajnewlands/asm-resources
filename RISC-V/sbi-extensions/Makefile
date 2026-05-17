CC=/usr/bin/riscv64-unknown-elf-gcc

CFLAGS=-Wall -Wextra -O2 -ffreestanding -nostdlib -fno-stack-protector -mcmodel=medany

SRCS=src/main.c src/boot.s src/console.s src/base.s src/srst.s

probe: $(SRCS) src/kernel.ld
	${CC} ${CFLAGS} -T src/kernel.ld -Wl,-Map=probe.map -o probe.elf $(SRCS)

run: probe
	qemu-system-riscv64 -machine virt -serial mon:stdio -no-reboot -nographic \
		-bios /usr/lib/riscv64-linux-gnu/opensbi/generic/fw_dynamic.bin -kernel probe.elf

clean:
	rm -f probe.elf probe.map
