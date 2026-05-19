// main.c - Preemptive multitasking demo for RISC-V
//
// Two tasks each print a different character ('a' and 'b'). A timer interrupt
// fires every ~10ms triggering a context switch.
//
// Register state is saved/restored on each task's own stack as a "trap frame"
//

typedef unsigned long uint64;

// --- External symbols from assembly ---
extern void sbi_putchar(int ch);
extern void set_interval_timer(uint64 offset);
extern void switch_to_task(void);

// --- Timer configuration ---

// QEMU virt machine timer frequency = 10 MHz
// so 100K ticks => 10ms
#define TIMER_INTERVAL 100000

// --- Task state ---

#define NUM_TASKS 2

// Each task's stack (4KB each)
static char __attribute__((aligned(16))) task_stack[NUM_TASKS][4096];

// Saved stack pointer for each task. Points to the trap frame on the
// task's stack. This is the only per-task state the scheduler needs.
uint64 task_sp[NUM_TASKS];

// Index of the currently running task
int current_task;

// --- Task function ---

void task_print(int ch)
{
    for (;;)
    {
        sbi_putchar(ch);
        for (int i = 0; i < 500000; i++)
            __asm__ volatile("nop");
    }
}

// --- Scheduler ---

void schedule(void)
{
    current_task = (current_task + 1) % NUM_TASKS;
    set_interval_timer(TIMER_INTERVAL);
}

// --- Kernel entry point ---

// Build an initial trap frame on a task's stack so that the first
// context switch into it looks the same as any other restore.
//
// Trap frame layout (32 slots of 8 bytes, matching trap.s):
//   [0]  = sepc (entry point)
//   [1]  = ra   (x1)
//   [2]  = gp   (x3)
//   ...
//   [9]  = a0   (x10) — the task's argument
//   ...
//   [31] = original sp (stack top, before frame was pushed)
static void init_task(int id, void (*entry)(int), int arg, char *stack_top)
{
    uint64 *frame;

    // Place the trap frame at the top of the stack
    frame = (uint64 *)(stack_top - 32 * 8);

    // Zero the whole frame (all registers start at 0)
    for (int i = 0; i < 32; i++)
        frame[i] = 0;

    frame[0] = (uint64)entry;      // sepc = entry point
    frame[9] = (uint64)arg;        // a0 = argument (slot 9 = x10)
    frame[31] = (uint64)stack_top; // original sp

    // Save the frame pointer as this task's sp
    task_sp[id] = (uint64)frame;
}

void kernel_main(void)
{
    init_task(0, task_print, 'a', &task_stack[0][4096]);
    init_task(1, task_print, 'b', &task_stack[1][4096]);

    current_task = 0;

    // Arm the first timer
    set_interval_timer(TIMER_INTERVAL);

    // Set SPP=1 (sret -> S-mode) and SPIE=1 (sret -> interrupts enabled)
    __asm__ volatile("csrs sstatus, %0" ::"r"((1 << 8) | (1 << 5)));

    switch_to_task();
}
