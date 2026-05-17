# kernel.ld — RISC-V 64-bit Linker Script

## Entry Point

```
ENTRY(boot)
```

Declares `boot` as the ELF entry point. The bootloader (or SBI firmware) will transfer control here after loading the kernel image.

## Program Headers (PHDRS)

```
PHDRS {
    text PT_LOAD FLAGS(5);   /* R-X */
    data PT_LOAD FLAGS(6);   /* RW- */
}
```

Defines two ELF LOAD segments with explicit permission flags:

| Segment | FLAGS | Permissions | Contains |
|---------|-------|-------------|----------|
| `text`  | 5 (0b101) | Read + Execute | `.text`, `.rodata` |
| `data`  | 6 (0b110) | Read + Write   | `.data`, `.bss`, stack |

The FLAGS value is a bitmask: bit 0 = Execute, bit 1 = Write, bit 2 = Read.

Without this block, the linker creates a single LOAD segment covering all sections and conservatively assigns RWX (7) permissions, which triggers a `LOAD segment with RWX permissions` warning. Splitting into two segments with minimal permissions eliminates the warning and more accurately describes the memory layout to any loader or debugger inspecting the ELF.

## Base Address: `0x80200000`

```
. = 0x80200000;
```

This is the conventional load address for S-mode payloads launched by OpenSBI. The SBI firmware itself occupies `0x80000000`–`0x801FFFFF` (the first 2MB of DRAM), so supervisor-mode kernels are loaded at the next available address. This address is specific to the RISC-V SBI boot flow and differs from bare-metal M-mode programs which typically start at `0x80000000`.

## Sections

### `.text` — Code

```
.text :{
    KEEP(*(.text.boot));
    *(.text .text.*);
} :text
```

- `.text.boot` is placed first via `KEEP` so the `boot` entry point resides at exactly `0x80200000`. This guarantees the first instruction executed matches what the firmware jumps to.
- `KEEP` prevents the linker from discarding this section during garbage collection (`--gc-sections`), since nothing explicitly references it by symbol.
- `:text` assigns this section to the `text` program header (R-X).

### `.rodata` — Read-Only Data

```
.rodata : ALIGN(4) {
    *(.rodata .rodata.*);
} :text
```

String literals and constants. 4-byte aligned. Assigned to the `text` segment (R-X) since it only needs read access and doesn't warrant its own LOAD segment.

### `.data` — Initialized Data

```
.data : ALIGN(4) {
    *(.data .data.*);
} :data
```

Mutable globals with initial values. 4-byte aligned. Assigned to the `data` segment (RW-).

### `.bss` — Zero-Initialized Data

```
.bss : ALIGN(4) {
    __bss = .;
    *(.bss .bss.* .sbss .sbss.*);
    __bss_end = .;
} :data
```

- `__bss` and `__bss_end` symbols are exported so the kernel can zero this region at startup (before using any uninitialized globals).
- Includes `.sbss` (small BSS), which RISC-V GCC emits for small objects when using GP-relative addressing.
- Assigned to the `data` segment (RW-).

### Stack

```
. = ALIGN(4);
. += 128 * 1024;
__stack_top = .;
```

Reserves 128KB for the kernel stack. `__stack_top` is the highest address (stack grows downward on RISC-V). The boot code loads this into `sp` before jumping to `kernel_main`.

## RISC-V 64-bit Considerations

- **Code model**: The base address `0x80200000` is outside the range of the default `medlow` code model (which assumes symbols near `0x0`). The compiler must use `-mcmodel=medany` to generate PC-relative addressing that works at arbitrary addresses.
- **SBI convention**: `0x80200000` is the standard S-mode entry point for OpenSBI firmware on QEMU's `virt` machine and many real RISC-V boards.
- **Stack alignment**: The RISC-V calling convention requires 16-byte stack alignment. The 4-byte `ALIGN` here is sufficient only because the 128KB allocation is a power-of-two multiple of 16.
- **No GP relaxation**: This script does not define `__global_pointer$`, so linker relaxation for GP-relative accesses is not active. For small kernels this is fine; larger programs may benefit from defining it in the `.sdata` section.
