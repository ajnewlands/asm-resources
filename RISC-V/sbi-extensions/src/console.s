    .global kputs_dbcn
    .global kputs_legacy

    # void kputs_dbcn(const char *s, size_t length)
    # SBI Debug Console Extension (EID 0x4442434E), console_write (FID 0)
kputs_dbcn:
    mv      t0, a0
    mv      a0, a1
    mv      a1, t0
    mv      a2, zero
    li      a6, 0
    li      a7, 0x4442434E
    ecall
    ret

    # void kputs_legacy(const char *s, size_t length)
    # SBI Legacy Console Putchar (EID 1)
kputs_legacy:
    mv      t0, a0
    add     t1, a0, a1
.Lputloop:
    bge     t0, t1, .Lputdone
    lbu     a0, 0(t0)
    li      a7, 1
    ecall
    addi    t0, t0, 1
    j       .Lputloop
.Lputdone:
    ret
