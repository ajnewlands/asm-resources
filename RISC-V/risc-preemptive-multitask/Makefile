CC=/usr/bin/riscv64-unknown-elf-gcc

CFLAGS=-Wall -Wextra -O2 -ffreestanding -nostdlib -fno-stack-protector -mcmodel=medany

SRCS=src/main.c src/boot.s src/trap.s src/timer.s src/console.s

multitask: $(SRCS) src/kernel.ld
	${CC} ${CFLAGS} -T src/kernel.ld -Wl,-Map=multitask.map -o multitask.elf $(SRCS)

run: multitask
	qemu-system-riscv64 -machine virt -serial mon:stdio -no-reboot -nographic \
		-bios /usr/lib/riscv64-linux-gnu/opensbi/generic/fw_dynamic.bin -kernel multitask.elf

clean:
	rm -f multitask.elf multitask.map
