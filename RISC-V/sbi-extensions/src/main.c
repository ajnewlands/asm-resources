typedef unsigned long size_t;

extern void kputs_dbcn(const char *s, size_t length);
extern void kputs_legacy(const char *s, size_t length);
extern long sbi_probe_extension(long id);
extern void sbi_system_reset(long reset_type, long reset_reason);

/* SBI Extension IDs */
#define SBI_EID_BASE 0x10
#define SBI_EID_TIME 0x54494D45
#define SBI_EID_SPI 0x735049
#define SBI_EID_RFNC 0x52464E43
#define SBI_EID_HSM 0x48534D
#define SBI_EID_SRST 0x53525354
#define SBI_EID_PMU 0x504D55
#define SBI_EID_DBCN 0x4442434E
#define SBI_EID_SUSP 0x53555350
#define SBI_EID_CPPC 0x43505043
#define SBI_EID_NACL 0x4E41434C
#define SBI_EID_STA 0x535441
#define SBI_EID_FWFT 0x46574654
#define SBI_EID_SSE 0x535345
#define SBI_EID_DBTR 0x44425452

/* SBI SRST reset types */
#define SBI_SRST_SHUTDOWN 0
#define SBI_SRST_COLD_REBOOT 1
#define SBI_SRST_WARM_REBOOT 2

/* SBI SRST reset reasons */
#define SBI_SRST_REASON_NONE 0
#define SBI_SRST_REASON_FAILURE 1

typedef void (*kputs_fn)(const char *s, size_t length);

static kputs_fn kputs;

static size_t strlen(const char *s)
{
    size_t n = 0;
    while (s[n])
        n++;
    return n;
}

static void print_probe(const char *name, long eid)
{
    kputs(name, strlen(name));
    sbi_probe_extension(eid) ? kputs(": 1\n", 4) : kputs(": 0\n", 4);
}

void kernel_main(void)
{
    if (sbi_probe_extension(SBI_EID_DBCN))
        kputs = kputs_dbcn;
    else
        kputs = kputs_legacy;

    kputs("\nSBI Extension Probe:\n", 22);

    print_probe("Base (BASE)", SBI_EID_BASE);
    print_probe("Timer (TIME)", SBI_EID_TIME);
    print_probe("IPI (sPI)", SBI_EID_SPI);
    print_probe("RFENCE (RFNC)", SBI_EID_RFNC);
    print_probe("HSM", SBI_EID_HSM);
    print_probe("System Reset (SRST)", SBI_EID_SRST);
    print_probe("PMU", SBI_EID_PMU);
    print_probe("Debug Console (DBCN)", SBI_EID_DBCN);
    print_probe("Suspend (SUSP)", SBI_EID_SUSP);
    print_probe("CPPC", SBI_EID_CPPC);
    print_probe("NACL", SBI_EID_NACL);
    print_probe("STA", SBI_EID_STA);
    print_probe("FWFT", SBI_EID_FWFT);
    print_probe("SSE", SBI_EID_SSE);
    print_probe("DBTR", SBI_EID_DBTR);

    /* Shutdown if SRST is available, otherwise idle */
    if (sbi_probe_extension(SBI_EID_SRST)) {
        kputs("\nShutting down...\n", 19);
        sbi_system_reset(SBI_SRST_SHUTDOWN, SBI_SRST_REASON_NONE);
    }

    for (;;)
        __asm__ __volatile__("wfi");
}
