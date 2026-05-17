    .global sbi_system_reset

    # void sbi_system_reset(long reset_type, long reset_reason)
    # SBI System Reset Extension (EID 0x53525354), system_reset (FID 0)
    # reset_type: 0 = shutdown, 1 = cold reboot, 2 = warm reboot
    # reset_reason: 0 = no reason, 1 = system failure
sbi_system_reset:
    li      a6, 0
    li      a7, 0x53525354
    ecall
    ret
