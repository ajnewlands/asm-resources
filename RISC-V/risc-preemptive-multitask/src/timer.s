# timer.s - SBI timer interface.
#
# void set_interval_timer(uint64 offset)
#
# Arms the supervisor timer to fire 'offset' ticks in the future.
# Reads the current time from the 'time' CSR, adds the offset,
# and calls the SBI Timer Extension to set the deadline.
#   EID = 0x54494D45 ("TIME")
#   FID = 0 (set_timer)
#   a0  = absolute time value at which the interrupt should fire
#
# This sets mtimecmp in M-mode so that when mtime >= mtimecmp,
# a supervisor timer interrupt is delivered to S-mode.

    .global set_interval_timer

set_interval_timer:
    csrr    t0, time           # read current time
    add     a0, t0, a0         # a0 = now + offset
    li      a6, 0              # FID = 0 (set_timer)
    li      a7, 0x54494D45     # EID = TIME extension
    ecall
    ret
