# boot.s - Entry point and supervisor-mode initialization.
#
# OpenSBI jumps here in S-mode. We:
#   1. Set up the kernel stack pointer.
#   2. Install our trap vector (trap_entry) into stvec.
#   3. Enable supervisor timer interrupts in sie (sie.STIE = 1).
#   4. Jump to kernel_main which sets up tasks and arms the timer.
#
# Note: kernel_main sets sstatus.SPIE=1 before the initial sret,
# which causes sret to set SIE=1 when entering the first task.

    .section .text.boot
    .global boot

boot:
    # Set up the kernel stack
    la      sp, __stack_top

    # Install the trap handler into stvec (Direct mode, bit 0 = 0).
    # All traps (interrupts and exceptions) will vector here.
    la      t0, trap_entry
    csrw    stvec, t0

    # Enable Supervisor Timer Interrupt in sie register.
    # sie bit 5 (STIE) = Supervisor Timer Interrupt Enable.
    # This allows timer interrupts to be taken when sstatus.SIE=1.
    li      t0, (1 << 5)
    csrs    sie, t0

    # Jump to C initialization code
    j       kernel_main
