/*
 * Linker script for bare-metal RISC-V preemptive multitasking demo.
 *
 * Memory layout (starting at 0x80200000, where OpenSBI loads S-mode payloads):
 *
 *   .text        - Code (boot, trap handler, task functions)
 *   .rodata      - Read-only data
 *   .data        - Initialized data
 *   .bss         - Zero-initialized data (includes task stacks)
 *   kernel stack - 4KB stack for supervisor-mode boot/trap code
 */

ENTRY(boot)

PHDRS {
    text PT_LOAD FLAGS(5);   /* R-X */
    data PT_LOAD FLAGS(6);   /* RW- */
}

SECTIONS {
    . = 0x80200000;

    .text : {
        KEEP(*(.text.boot));
        *(.text .text.*);
    } :text

    .rodata : ALIGN(4) {
        *(.rodata .rodata.*);
    } :text

    .data : ALIGN(4) {
        *(.data .data.*);
    } :data

    .bss : ALIGN(4) {
        __bss = .;
        *(.bss .bss.* .sbss .sbss.*);
        __bss_end = .;
    } :data

    /* Kernel/supervisor stack: 4KB */
    . = ALIGN(16);
    . += 4096;
    __stack_top = .;
}
