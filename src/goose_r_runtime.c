/* goose_r_runtime.c -- the part of the Goose runtime that zugojson's
   generated C needs, rewritten to live inside an R process. First-party
   code; it replaces goose's src/runtime/runtime_impl.h, which is not
   vendored.

   Differences from the stock runtime (goose src/runtime/runtime_impl.h):
   - Nothing ends the process. Every runtime failure jumps back to
     goose_r_run(), which rewinds the data stacks and hands the message to
     the caller, who raises an ordinary R error.
   - Bodies may call R. goose_r_run() runs inside R_UnwindProtect, so an R
     error or interrupt still rewinds the stacks and restores R's handlers
     before R carries on unwinding. A nested call is refused.
   - No stdout, stderr, setvbuf, sigaltstack or threads.
   - The guard-page fault handler is installed only while Goose code runs
     inside goose_r_run(). R's own handlers are restored afterwards, and a
     fault outside the data stacks is passed back to them.
   - POSIX only. Windows needs the VirtualAlloc and vectored-handler
     equivalent.

   Byte search and number formatting live in goose_vendor.c, copied
   verbatim from the stock runtime by tools/regenerate.sh. */

#ifdef _WIN32
#error "goose_r_runtime.c: Windows support is not written yet"
#endif

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <setjmp.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define R_NO_REMAP
#include <Rinternals.h>

#include "goose_r_runtime.h"
#include "goose_version.h"

#define GS_API
#define GS_NORETURN __attribute__((noreturn))
#define GS_CAT_(a, b) a##b
#define GS_CAT(a, b) GS_CAT_(a, b)
#define gs_rt_start GS_CAT(gs_rt_start_, GS_RUNTIME_VERSION)

typedef struct gs_stack { uint8_t *top; } gs_stack;

/* --- data stack regions -------------------------------------------------- */

#define GS_R_MAX_REGIONS 64

typedef struct {
    uint8_t *base;
    size_t size;      /* usable part plus the PROT_NONE guard gap */
    gs_stack *stack;  /* whose top goose_r_run saves and rewinds */
    uint8_t *saved;
} gs_r_region;

static gs_r_region regions[GS_R_MAX_REGIONS];
static long nregions;
static size_t region_usable, region_gap;

/* --- failures: jump back to goose_r_run ---------------------------------- */

static sigjmp_buf *active_jump;
static char failure[512];

static GS_NORETURN void gs_r_fail(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(failure, sizeof failure, fmt, ap);
    va_end(ap);
    if (active_jump) siglongjmp(*active_jump, 1);
    /* Goose code ran outside goose_r_run: a bug in the glue. Nothing has
       been rewound, but R can still report it. */
    Rf_error("goose runtime error outside goose_r_run: %s", failure);
}

GS_API GS_NORETURN void gs_panic(const char *msg) { gs_r_fail("%s", msg); }

static const char *const errmsgs[] = {
    "limited array capacity exceeded",
    "slice bounds out of range",
    "relative reference offset overflow",
    "assert failed",
    "invalid capacity",
    "resize growth requires a fill value",
    "resize to a negative length",
    "pop on empty array",
    "thread_wait on an unknown thread id",
    "a worker cannot wait for itself",
    "corrupt ADT tag",
    "serialization needs a little-endian host",
    "invalid slice length",
    "slice not from this pool",
    "non-null relative reference encodes as null",
    "pop_n count negative or beyond the array's length",
    "queue limit of zero or less",
};

GS_API GS_NORETURN void gs_abort(int err, const char *file, int line) {
    const char *m = err >= 0 && err < (int)(sizeof errmsgs / sizeof *errmsgs)
                        ? errmsgs[err] : "runtime error";
    gs_r_fail("%s (%s:%d)", m, file, line);
}

GS_API GS_NORETURN void gs_abort_msg(const uint8_t *msg, int64_t len, const char *file,
                                     int line) {
    gs_r_fail("%.*s (%s:%d)", (int)(len > 400 ? 400 : len), (const char *)msg, file, line);
}

GS_API GS_NORETURN void gs_exit(int64_t code) {
    gs_r_fail("exit(%lld) called", (long long)code);
}

GS_API GS_NORETURN void gs_idxfail(int64_t i, int64_t n, const char *file, int line) {
    gs_r_fail("index %lld out of bounds (length %lld) (%s:%d)", (long long)i,
              (long long)n, file, line);
}

GS_API GS_NORETURN void gs_divfail(const char *file, int line) {
    gs_r_fail("division by zero (%s:%d)", file, line);
}

GS_API GS_NORETURN void gs_divovf(const char *file, int line) {
    gs_r_fail("division overflow (%s:%d)", file, line);
}

GS_API GS_NORETURN void gs_ovf(int64_t a, const char *op, int64_t b, const char *type,
                               const char *file, int line) {
    gs_r_fail("%s overflow: %lld %s %lld (%s:%d)", type, (long long)a, op, (long long)b,
              file, line);
}

GS_API GS_NORETURN void gs_ovf_neg(int64_t a, const char *type, const char *file, int line) {
    gs_r_fail("%s overflow: -%lld (%s:%d)", type, (long long)a, file, line);
}

GS_API GS_NORETURN void gs_asfail_i(const char *why, int64_t v, const char *type,
                                    const char *file, int line) {
    gs_r_fail("%lld as %s: %s (%s:%d)", (long long)v, type, why, file, line);
}

GS_API GS_NORETURN void gs_asfail_u(const char *why, uint64_t v, const char *type,
                                    const char *file, int line) {
    gs_r_fail("%llu as %s: %s (%s:%d)", (unsigned long long)v, type, why, file, line);
}

GS_API GS_NORETURN void gs_asfail_f(const char *why, double d, int f32, const char *type,
                                    const char *file, int line) {
    (void)f32;
    gs_r_fail("%g as %s: %s (%s:%d)", d, type, why, file, line);
}

/* --- start-up and regions ------------------------------------------------ */

GS_API void gs_rt_start(int argc, char **argv, uint64_t reserve, uint64_t gap,
                        uint64_t budget, int64_t mainregions, int64_t workerregions) {
    (void)argc; (void)argv; (void)budget; (void)workerregions;
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    if (mainregions > GS_R_MAX_REGIONS) gs_r_fail("too many data stacks");
    region_usable = (size_t)reserve - (size_t)reserve % page;
    region_gap = ((size_t)gap + page - 1) / page * page;
    if (!region_usable || !region_gap) gs_r_fail("bad data stack sizes");
}

/* Address space for one data stack: the usable part read-write, committed
   by the kernel as it is touched (overcommit, as the stock runtime does on
   Linux), then a PROT_NONE gap that turns runaway growth into a fault. */
GS_API uint8_t *gs_reserve_region(gs_stack *stack) {
    if (nregions >= GS_R_MAX_REGIONS) gs_r_fail("too many data stack regions");
    size_t size = region_usable + region_gap;
    int flags = MAP_PRIVATE | MAP_ANONYMOUS;
#ifdef MAP_NORESERVE
    flags |= MAP_NORESERVE;
#endif
    void *p = mmap(NULL, size, PROT_READ | PROT_WRITE, flags, -1, 0);
    if (p == MAP_FAILED) gs_r_fail("cannot reserve data stack address space");
    if (mprotect((uint8_t *)p + region_usable, region_gap, PROT_NONE)) {
        munmap(p, size);
        gs_r_fail("cannot protect data stack guard gap");
    }
    regions[nregions].base = (uint8_t *)p;
    regions[nregions].size = size;
    regions[nregions].stack = stack;
    nregions++;
    return (uint8_t *)p;
}

/* --- running Goose code -------------------------------------------------- */

static struct sigaction prev_segv, prev_bus;

static void fault_handler(int sig, siginfo_t *info, void *ctx) {
    (void)ctx;
    uintptr_t hit = (uintptr_t)info->si_addr;
    for (long i = 0; i < nregions; i++) {
        if (hit - (uintptr_t)regions[i].base < regions[i].size && active_jump) {
            snprintf(failure, sizeof failure, "data stack overflow");
            siglongjmp(*active_jump, 1);
        }
    }
    /* Not ours: put R's handler back; the access faults again under it. */
    sigaction(sig, sig == SIGSEGV ? &prev_segv : &prev_bus, NULL);
}

static void restore_handlers(void) {
    sigaction(SIGSEGV, &prev_segv, NULL);
#ifdef SIGBUS
    sigaction(SIGBUS, &prev_bus, NULL);
#endif
}

/* Stacks that existed before the call go back to their old tops; regions
   made during it (goose_init) are left as they are. */
static void rewind_stacks(void) {
    for (long i = 0; i < nregions; i++)
        if (regions[i].saved) regions[i].stack->top = regions[i].saved;
}

typedef struct {
    void (*body)(void *);
    void *data;
    int failed;
} gs_r_call;

static SEXP run_body(void *p) {
    gs_r_call *c = p;
    sigjmp_buf jump;
    if (sigsetjmp(jump, 1) == 0) {
        active_jump = &jump;
        c->body(c->data);
    } else {
        c->failed = 1;
        rewind_stacks();
    }
    active_jump = NULL;
    return R_NilValue;
}

/* Runs only when R unwinds out of the body: an R error, an interrupt or a
   condition handler's jump. R continues the unwind afterwards. */
static void unwind_cleanup(void *p, Rboolean jump) {
    (void)p;
    if (!jump) return;
    rewind_stacks();
    active_jump = NULL;
    restore_handlers();
}

int goose_r_run(void (*body)(void *), void *data, char *err, size_t errlen) {
    /* One continuation token, reused: calls never nest. */
    static SEXP token = NULL;
    struct sigaction sa;
    gs_r_call c = {body, data, 0};

    if (active_jump) {
        if (err && errlen) snprintf(err, errlen, "Goose re-entered from R during a Goose call");
        return 1;
    }
    if (!token) {
        token = R_MakeUnwindCont();
        R_PreserveObject(token);
    }

    for (long i = 0; i < nregions; i++) regions[i].saved = regions[i].stack->top;

    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = fault_handler;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGSEGV, &sa, &prev_segv);
#ifdef SIGBUS
    sigaction(SIGBUS, &sa, &prev_bus);
#endif

    R_UnwindProtect(run_body, &c, unwind_cleanup, NULL, token);

    restore_handlers();
    if (c.failed && err && errlen) snprintf(err, errlen, "%s", failure);
    return c.failed;
}

int goose_r_stack_use(double *use, int max) {
    int n = nregions < max ? (int)nregions : max;
    for (int i = 0; i < n; i++)
        use[i] = (double)(regions[i].stack->top - regions[i].base);
    return n;
}

int goose_r_fault_handler_installed(void) {
    struct sigaction cur;
    sigaction(SIGSEGV, NULL, &cur);
    return (cur.sa_flags & SA_SIGINFO) && cur.sa_sigaction == fault_handler;
}
