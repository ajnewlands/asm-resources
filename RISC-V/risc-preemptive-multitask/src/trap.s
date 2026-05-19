# trap.s - Supervisor trap entry/exit for context switching.
#
# When a timer interrupt fires, the CPU:
#   1. Saves the current PC into sepc (Supervisor Exception PC).
#   2. Sets scause to indicate the interrupt reason.
#   3. Clears sstatus.SIE (disabling further interrupts).
#   4. Copies the old SIE into sstatus.SPIE.
#   5. Jumps to the address in stvec (here!).
#
# Here we:
#   - Swap sp with sscratch to get the kernel stack pointer.
#   - Check scause early (using the kernel stack as scratch space)
#     to verify this is a timer interrupt before doing a full save.
#   - If confirmed, swap back to get the task's sp and push a
#     "trap frame" (all registers) onto the task's own stack.
#   - Switch to the kernel stack and call the C scheduler.
#   - Restore the next task's registers from its trap frame.
#   - Return to the next task via sret.
#
# sscratch usage:
#   While a task is running, sscratch holds the kernel stack pointer.
#   On trap entry, we swap sp with sscratch so:
#     sp = kernel stack (for our use)
#     sscratch = task's sp (which we then use to push the trap frame)
#
# Trap frame layout (pushed onto the task stack):
#   pc + 30 registers + original sp
#
# The task's sp (pointing to the top of this frame) is stored in
# task_sp[current_task] by the trap handler, and restored from
# task_sp[next_task] when switching.

    .global trap_entry
    .global switch_to_task
    .extern task_sp
    .extern current_task
    .extern schedule

# Size of trap frame: 32 slots * 8 bytes = 256 bytes
.equ FRAME_SIZE, 32*8

    .align 4
trap_entry:
    # Swap sp with sscratch.
    # After: sp = kernel stack, sscratch = task's sp.
    csrrw   sp, sscratch, sp

    # We need a register to read scause, but we haven't saved anything yet.
    # Use the kernel stack to spill t0 temporarily.
    addi    sp, sp, -8
    sd      t0, 0(sp)

    # --- Check whether this trap is a supervisor timer interrupt ---
    #
    # The scause register tells us why we trapped. Its format is:
    #   bit 63    = Interrupt flag (1 = interrupt, 0 = exception)
    #   bits 62:0 = Cause code
    #
    # For a supervisor timer interrupt:
    #   bit 63 = 1 (it's an interrupt, not an exception like a page fault)
    #   code   = 5 (supervisor timer)
    #
    # Other codes we might see (but don't handle):
    #   code 1 = supervisor software interrupt
    #   code 9 = supervisor external interrupt
    #
    # We check bit 63 first using bgez (branch if >= 0, i.e. sign bit clear).
    # Then we mask the low bits and compare against 5.

    csrr    t0, scause
    bgez    t0, .Lnot_timer     # bit 63 clear = exception, not interrupt
    andi    t0, t0, 0xff        # mask off the interrupt bit, keep cause code
    addi    t0, t0, -5          # subtract 5: result is 0 only if code == 5
    bnez    t0, .Lnot_timer     # non-zero = not a timer interrupt

    # --- Timer interrupt confirmed ---

    # Recover t0 from kernel stack (restoring it to its pre-trap value)
    ld      t0, 0(sp)
    addi    sp, sp, 8

    # Swap back: get the task's sp from sscratch, put kernel sp back
    csrrw   sp, sscratch, sp
    # Now: sp = task's sp, sscratch = kernel sp

    # Allocate trap frame on the task's stack
    addi    sp, sp, -FRAME_SIZE

    # Save all registers into the trap frame
    sd      x1,   1*8(sp)
    sd      x3,   2*8(sp)
    sd      x4,   3*8(sp)
    sd      x5,   4*8(sp)
    sd      x6,   5*8(sp)
    sd      x7,   6*8(sp)
    sd      x8,   7*8(sp)
    sd      x9,   8*8(sp)
    sd      x10,  9*8(sp)
    sd      x11, 10*8(sp)
    sd      x12, 11*8(sp)
    sd      x13, 12*8(sp)
    sd      x14, 13*8(sp)
    sd      x15, 14*8(sp)
    sd      x16, 15*8(sp)
    sd      x17, 16*8(sp)
    sd      x18, 17*8(sp)
    sd      x19, 18*8(sp)
    sd      x20, 19*8(sp)
    sd      x21, 20*8(sp)
    sd      x22, 21*8(sp)
    sd      x23, 22*8(sp)
    sd      x24, 23*8(sp)
    sd      x25, 24*8(sp)
    sd      x26, 25*8(sp)
    sd      x27, 26*8(sp)
    sd      x28, 27*8(sp)
    sd      x29, 28*8(sp)
    sd      x30, 29*8(sp)
    sd      x31, 30*8(sp)

    # Save sepc (the PC to resume at)
    csrr    t0, sepc
    sd      t0,  0*8(sp)

    # Save the task's original sp (before frame allocation).
    # Original sp = current sp + FRAME_SIZE.
    addi    t0, sp, FRAME_SIZE
    sd      t0, 31*8(sp)

    # Store this task's frame pointer into task_sp[current_task].
    la      t0, current_task
    lw      t0, 0(t0)          # t0 = current_task index
    la      t1, task_sp
    slli    t0, t0, 3          # t0 = index * 8
    add     t1, t1, t0
    sd      sp, 0(t1)          # task_sp[current_task] = sp

    # Switch to kernel stack for the scheduler call
    csrr    sp, sscratch

    # Call schedule() in C. It will:
    #   - Toggle current_task index
    #   - Re-arm the timer
    call    schedule

    # --- Restore next task ---

    # Load next task's saved sp from task_sp[current_task]
    la      t0, current_task
    lw      t0, 0(t0)
    la      t1, task_sp
    slli    t0, t0, 3
    add     t1, t1, t0
    ld      sp, 0(t1)          # sp = next task's trap frame

    # Restore sepc
    ld      t0, 0*8(sp)
    csrw    sepc, t0

    # Set sstatus for sret:
    #   SPP  (bit 8) = 1 -> return to S-mode
    #   SPIE (bit 5) = 1 -> after sret, SIE=1 (interrupts re-enabled)
    li      t0, (1 << 8) | (1 << 5)
    csrs    sstatus, t0

    # Put kernel sp back into sscratch for next trap
    la      t0, __stack_top
    csrw    sscratch, t0

    # Restore all registers from the trap frame
    ld      x1,   1*8(sp)
    ld      x3,   2*8(sp)
    ld      x4,   3*8(sp)
    ld      x5,   4*8(sp)
    ld      x6,   5*8(sp)
    ld      x7,   6*8(sp)
    ld      x8,   7*8(sp)
    ld      x9,   8*8(sp)
    ld      x10,  9*8(sp)
    ld      x11, 10*8(sp)
    ld      x12, 11*8(sp)
    ld      x13, 12*8(sp)
    ld      x14, 13*8(sp)
    ld      x15, 14*8(sp)
    ld      x16, 15*8(sp)
    ld      x17, 16*8(sp)
    ld      x18, 17*8(sp)
    ld      x19, 18*8(sp)
    ld      x20, 19*8(sp)
    ld      x21, 20*8(sp)
    ld      x22, 21*8(sp)
    ld      x23, 22*8(sp)
    ld      x24, 23*8(sp)
    ld      x25, 24*8(sp)
    ld      x26, 25*8(sp)
    ld      x27, 26*8(sp)
    ld      x28, 27*8(sp)
    ld      x29, 28*8(sp)
    ld      x30, 29*8(sp)
    ld      x31, 30*8(sp)

    # Restore sp: load original sp from frame, deallocating the frame
    ld      sp, 31*8(sp)

    # Return to the task. sret:
    #   - Sets PC = sepc
    #   - Sets SIE = SPIE (re-enables interrupts)
    #   - Sets privilege = SPP, then clears SPP
    sret

.Lnot_timer:
    # Unexpected trap. Restore t0, undo swap, halt.
    ld      t0, 0(sp)
    addi    sp, sp, 8
    csrrw   sp, sscratch, sp
.Lhalt:
    j       .Lhalt


# switch_to_task - Initial entry into the first task.
#
# Called once from kernel_main. Sets up sscratch with the kernel sp,
# loads the first task's saved sp (which points to a pre-built trap
# frame on its stack), and enters via sret.
#
# Before calling this, kernel_main must:
#   - Set sstatus.SPP = 1 (so sret returns to S-mode)
#   - Set sstatus.SPIE = 1 (so sret enables interrupts)
#   - Set current_task and populate task_sp[]
switch_to_task:
    # Put kernel stack into sscratch for future traps
    la      t0, __stack_top
    csrw    sscratch, t0

    # Load first task's sp from task_sp[current_task]
    la      t0, current_task
    lw      t0, 0(t0)
    la      t1, task_sp
    slli    t0, t0, 3
    add     t1, t1, t0
    ld      sp, 0(t1)

    # Restore sepc from the trap frame
    ld      t0, 0*8(sp)
    csrw    sepc, t0

    # Restore a0 (argument to task function)
    ld      x10, 9*8(sp)

    # Restore sp to the task's original stack top
    ld      sp, 31*8(sp)

    sret
