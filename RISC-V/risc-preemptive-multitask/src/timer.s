# timer.s - SBI timer interface.
#
# void sbi_set_timer(uint64 stime_value)
#
# Arms the supervisor timer by calling the SBI Timer Extension.
#   EID = 0x54494D45 ("TIME")
#   FID = 0 (set_timer)
#   a0  = absolute time value at which the interrupt should fire
#
# This sets mtimecmp in M-mode so that when mtime >= mtimecmp,
# a supervisor timer interrupt is delivered to S-mode.

    .global sbi_set_timer

sbi_set_timer:
    # a0 already contains the timer value (first argument)
    li      a6, 0              # FID = 0 (set_timer)
    li      a7, 0x54494D45     # EID = TIME extension
    ecall
    ret
