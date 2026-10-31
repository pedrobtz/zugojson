# Fork patches for embedding Goose in R and Python

Written 2026-10-31, from the Goose source at the fork pin `b362b5a5`
(upstream `2ed1a63d` plus the `--header` fix) and from three hosts:
zugojson and zudiff in R, and zugodiff in CPython
(`pedrobtz/py-zugodiff`). It proposes the patches to try in
`pedrobtz/goose`, in order, and revises Pieces 1–3 of
`runtime-research-plan.md`. Nothing here has been built yet.

## What every host needed

All three packages carry a hand-written replacement for Goose's runtime:
zugojson 301 lines, zudiff 509, zugodiff about 300. Python was the test of
what is host-specific. The same five needs came back unchanged:

1. **A failure is the host's error, not a process exit.** Rewind the data
   stacks, keep the message, return to the host.
2. **Fault handlers only while Goose runs.** R and CPython both own SIGSEGV
   (R reports C stack overflow; Python has `faulthandler`).
3. **Interrupts belong to the host.** R polls with
   `R_CheckUserInterrupt()`, Python with `PyErr_CheckSignals()`. Both may
   run host code inside the call: R handlers, Python signal handlers.
4. **A call inside a call must be safe.** Python showed it is not
   hypothetical: a signal handler run by the poll called back into the
   package. Today the only safe answer is to refuse it.
5. **No stdout, stderr, setvbuf, sigaltstack or exit.**

Only the glue differs: `SEXP` against `PyObject *`, `PROTECT` against
reference counts, `R_UnwindProtect` against an exception that is already
set. The runtime should not differ at all.

The copies have also drifted from upstream. Upstream's error table now
has 20 entries and ours has 17, so at the new pin "invalid array length",
"slice not within this array" and "slice pool span tree is corrupt" print
as "runtime error". That is a small bug in all three packages, and the
best argument for the stock runtime.

## What Goose already has

Reading `src/runtime/runtime.h`, `runtime_impl.h`, `jit_runtime.c` and
`codegen.h` at the pin shows that most of the machinery exists. It is
reserved for workers and for the compiler's own in-process JIT.

- **Contained failures.** `gs_fail()` checks a thread-local
  `gs_contain`. When it is set, it saves the message (without the
  "goose runtime error: " prefix) and `longjmp`s there instead of
  printing and calling `gs_end()`. Contained workers use it today. This is
  failure handling for a host. But `gs_panic()`, `gs_exit()`,
  `gs_stack_overflow()` and the fault handler bypass it: they print and
  end the process.
- **An in-process host.** `goose run` runs programs inside the compiler
  through TinyCC (`jit_runtime.c`, `GS_HOSTED_JIT`). In that mode
  `gs_end()` `longjmp`s back to the compiler (`gs_jit_exit`), and the fault
  handlers' installation is recorded so they can be removed afterwards,
  the Windows vectored handler included. This is a host mode with one
  host compiled in.
- **Globals behind one pointer.** Globals live in one `gs_globals_t`. A
  threaded build reaches them through `GS_GL`, defined as
  `((gs_globals_t *)gs_gl)`, a thread-local pointer, and data stacks through
  the thread-local block `gs_stks`. A single-threaded build uses the static
  `gs_globals_main` instead (`codegen.h:1548`). Switching both pointers is
  most of a context.
- **Memory given back.** `gs_trim_memory()` (Goose's `os.trim_memory`)
  returns unused stack pages to the OS on every platform. zugoose's design
  §6.2 planned to write this itself.
- **One checked growth site.** `gs_stack_overflow()` reports one bulk
  append that would pass `GS_STACK_RESERVE`, without a fault (`0e62366f`).
  It is the hook Piece 3 needs, used in one place.

## Proposed patches

Each patch is a branch in the fork, stacked in this order (Fork workflow
in the plan). It is proven in zugojson and zudiff and, from patch 1 on, in
zugodiff, before anything goes upstream. Each patch lists the code it
deletes from the packages.

### Patch 0: small fixes (no design question)

- `__extension__` on the `unsigned __int128` typedef. Removes the `sed`
  patch in every package's `regenerate.sh`.
- `frexp`'s exponent through an aligned local in `std`. Removes the one
  clang `-Walign-mismatch` warning zugojson's builds show.
- `GS_API` wrapped in `#ifndef GS_API`, so a host can define it as
  `__attribute__((visibility("hidden")))` for the runtime object. Hidden
  symbols then stop depending on `-fvisibility=hidden` alone.
- Already done: `--header` declares the alignment types (`b362b5a5`,
  offered upstream when aardappel/goose#125 was closed).

Cost: a few lines each. Upstream candidates as they are.

### Patch 1: `GS_HOSTED`, a host mode (replaces Piece 1)

Generalize `GS_HOSTED_JIT` into a mode any host can use, built on
`gs_contain`. The runtime object (`goose --emit-runtime --hosted`) then
offers one call:

```c
/* Runs body(data) as a contained call: a failure anywhere in it, a data
   stack overflow included, rewinds every data stack, stores the message
   and returns 1 (2 when the host's poll asked to stop). Fault handlers are
   installed for the call only. A call made during another is refused
   with 1, until contexts (patch 2) allow it. */
int gs_host_call(void (*body)(void *), void *data, const uint8_t **msg, int64_t *len);

typedef struct {
    void (*out)(int stream, const uint8_t *p, int64_t len); /* print, eprint */
    int (*poll)(void);  /* nonzero: stop the call */
} gs_host;
void gs_host_set(const gs_host *host);
```

with these changes in the runtime under `GS_HOSTED`:

- `gs_panic()`, `gs_exit()`, `gs_stack_overflow()` and the fault handler's
  overflow branch go through `gs_fail()`, so they reach `gs_contain` like
  every other failure. The fault handler `siglongjmp`s from the signal
  (`_setjmp` does not restore the mask, so the hosted jump needs
  `sigsetjmp`).
- The fault handler is installed by `gs_host_call()` and removed when it
  returns, as the JIT's already is. On Windows the vectored handler is
  added once and removed by a `gs_host_unload()`, as zudiff does.
- No `setvbuf`, `sigaltstack` or `_setmode`. Printing goes to `host.out`.
  The native stack's overflow guard (`gs_native_stack_init`) is left to the
  host.
- `gs_host_poll()`, an `extern fn` every program can call, calls
  `host.poll` and fails the call with an interrupt when it returns
  nonzero. That replaces each package's own `zudiff_check_interrupt` or
  equivalent. Polling stays cooperative: the Goose code decides where.

**Deleted from the packages:** `goose_r_runtime.c` and
`goose_py_runtime.c` shrink to the glue's few lines. `goose_vendor.c` and
`regenerate.sh`'s anchor ranges go, because the runtime object is
generated whole. The error-table drift goes. zudiff's interrupt machinery
goes too; zudiff#22 does part of that without Goose's help.

**Simpler than the plan's Piece 1.** The plan proposed hooks for `fail`,
`out` and `reserve`. `fail` is not needed as a hook: `gs_contain` already
does it, and a host only needs the call that sets it. `reserve` is not
needed in this patch: reserved address space does not conflict with R or
CPython, only the signals do.

**Proof:** zugojson's Task 4 gates (suite, check, symbols, benchmark
within 3%). Plus zudiff's and zugodiff's test suites, unchanged, against
the hosted runtime: `tests/test_runtime.py` already covers each failure
path, the guard gap and Ctrl-C.

### Patch 2: contexts (replaces Piece 2)

Behind `--context`, a single-threaded build also reaches globals through
`gs_gl`, and the runtime offers:

```c
gs_ctx *gs_ctx_new(void);         /* fresh globals and stack block */
gs_ctx *gs_ctx_swap(gs_ctx *ctx); /* gs_gl, gs_stks, gs_nstks; returns the old */
void gs_ctx_reset(gs_ctx *ctx);   /* globals re-initialized, tops rewound */
void gs_ctx_free(gs_ctx *ctx);    /* regions released */
```

`gs_ctx_new()` does what `gs_program_init()` and a worker's entry thunk
already do: allocate the globals, reserve the stack block, run
`gs_init_globals()`. The region registry becomes per context instead of
per thread (`gs_regions` is thread-local today).

**What it gives the hosts:**

- R and Python: a nested call runs in its own context instead of being
  refused (Python's signal handler, an R callback). zugojson's test
  "re-entering Goose from R is refused" becomes "works".
- Every export's "clear the globals first" rule goes:
  `gs_ctx_reset()` after a failure restores them.
- Python only: with one context per thread, a long diff can release the
  GIL. `gs_gl` and `gs_stks` are already thread-local. That is the way to
  free-threaded CPython (3.13t), which no global-state design can support.

**Cost to measure:** `GS_GL` through a pointer instead of a static
address. The threaded build already pays it, so the evaluations' threaded
programs give a first estimate before zugojson's benchmark does.

### Patch 3: checked growth (Piece 3, unchanged in aim)

`--checked-stacks` checks capacity before stack space is claimed, and
calls `gs_stack_overflow()` instead of relying on the guard gap. The
function exists and is called from one site. The plan's Task 6 has the
details.

**Why it is still needed after patch 1:** on POSIX, patch 1's fault
handler is enough, since growth into reserved memory needs no handler and
only overflow does. On Windows, growth itself needs the vectored handler
to commit pages (zudiff design D10). Checked growth is what removes it,
and with it the last signal or exception handler from every host. It is
the piece that decides whether Goose packages can be ordinary C
extensions on all three platforms.

**Proof:** zudiff, as the plan's Task 6 step 5 and Task 7 say. The hot
stack loops and the Windows half are there.

### Patch 4: numeric slice results from exports

Spec §7.11 allows only `const u8[:]` as a slice result. Allow
`const i32[:]`, `const i64[:]` and `const f64[:]` the same way: a pointer
plus an `int64_t *out_len`, borrowed until the next call.

**Deleted:** zudiff's packed script format and its version field (design
§7, D4), and its unpacking in R and Python. Each host copies the result
with one `memcpy` into an integer vector or an `array('i')`.

This is a language change, so it is the patch most likely to be done
differently upstream. Propose it as a request with zudiff as the example,
not as a finished patch.

## Not proposed

- **Equality or hashing in Goose.** The id step dominates in both hosts:
  R's `match()` is 65% of zudiff's text benchmark, and Python's `dict` is
  45 of 48 ms in zugodiff, where the Goose core takes 1.9 ms. The host's
  own equality must stay (zudiff D3), so the speed-up is host C, not
  Goose.
- **A Goose-side R or Python API.** Values cross only at the export
  boundary (zugoose §1.1). The patches make the boundary cheaper, not
  wider.
- **A `reserve` hook.** It is not needed until a host wants to own the
  memory itself. Neither does.

## Order and what each unblocks

| Patch | Size | Unblocks |
| --- | --- | --- |
| 0 small fixes | hours | `regenerate.sh` without patches |
| 1 `GS_HOSTED` | days | stock runtime in all three packages; zugoose's runtime is generated, not written |
| 2 contexts | days | re-entry; no clear-globals rule; GIL release in Python |
| 3 checked growth | weeks, uncertain | Windows without handlers; Goose packages as plain C extensions |
| 4 numeric results | upstream's call | no packed formats |

Patches 0 and 1 are the ones to start with. They are small, and close to
what upstream already does for its JIT. Each removes code from all three
packages at once.
