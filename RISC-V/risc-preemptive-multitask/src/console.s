# console.s - Character output via SBI Legacy Console Putchar.
#
# SBI Legacy extension EID=1 outputs a single character.
# a0 = character to print, a7 = 1 (extension ID), then ecall.

    .global sbi_putchar

# void sbi_putchar(int ch)
sbi_putchar:
    li      a7, 1           # SBI Legacy Console Putchar EID
    ecall
    ret
