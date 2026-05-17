    .global sbi_probe_extension

    # long sbi_probe_extension(long extension_id)
    # SBI Base Extension (EID 0x10), probe_extension (FID 3)
sbi_probe_extension:
    li      a6, 3
    li      a7, 0x10
    ecall
    mv      a0, a1
    ret
