# R-Friendly Goose Runtime ("Option C") Research Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Find out how much of zugojson's R glue disappears when Goose
itself is changed to embed in R. Use zugojson as the test harness.

**Architecture:** Four pieces, cheapest first. Piece 0 changes only
zugojson. Pieces 1–3 change a fork of Goose (`pedrobtz/goose`), and
zugojson pins that fork on research branches. Each piece ends with
zugojson's suite green, `R CMD check` clean and a benchmark compared
against the baseline. A port of the YAML evaluation (zugoyaml) follows as a
second harness. It gets its own plan.

**Tech Stack:** R (>= 4.1), C99, testthat 3, the Goose compiler (C++,
cmake) at `tools/goose/PIN`, GitHub Actions.

**Spec:** the Background section of this file. Read it together with
zugoose's design §6 (`pedrobtz/zugoose/.agents/design.md`), which this plan
extends.

## Background

zugojson runs Goose-generated C inside R through a replacement runtime,
`src/goose_r_runtime.c`, which is 245 lines. It relies on four mechanisms
that suit a process badly but suit R worse:

- the 2 GiB reservation per data stack, with a `PROT_NONE` guard gap;
- the SIGSEGV/SIGBUS handlers it swaps in on every call;
- `sigsetjmp` and `siglongjmp` across a boundary R's API must not cross;
- mutable static globals that every export must clear first.

The evaluations show that hand-written C with the same layout and no
checks runs within 1–3% of Goose (`goose-evaluations/yaml/baselines/twin.c`).
So what Goose adds is the checked code and the default layout, not speed.
This research asks whether the runtime can stop costing more than those
are worth.

Findings in Goose at the pin (`e76d5c9`), which the pieces build on:

- `goose --emit-runtime` already writes the stock runtime as one C file,
  `RuntimeObjectSource()` in `src/main.cpp:607`. zugojson's generated C
  already links against a separate runtime (`GS_API extern`).
- Process-level behaviour is spread through the runtime:
  - `exit`, `_exit` and `stderr` in `runtime_impl.h:28-112, 475-482, 622`;
  - `setvbuf(stdout)` in `gs_rt_start` at `:1526`;
  - `sigaction` and `sigaltstack` at `:497-562`;
  - `gs_out_bytes` at `:1828`;
  - the stdio paths of `runtime_os.h:403-441`.
- Globals already sit in one `gs_globals_t`, reached through `GS_GL`.
  `src/codegen.h:1470` switches it to a thread-local pointer for workers.
- Data stacks are fixed-address. Codegen caches stack tops and writes
  before it bumps them (impl §6.10). It also drops range checks on
  relative references by `GS_STACK_RESERVE` (`docs/implementation.md:4721`).
  The spec (§10.4) describes the alternative, "bounds-checked growth", as
  wasm's fallback. It is not implemented.

The pieces and research questions:

| # | Piece | Question it answers | Estimate |
|---|---|---|---|
| 0 | `R_UnwindProtect` in `goose_r_run` | Can Goose code call R safely today, with no Goose change? | 1–2 days |
| 1 | Hosted runtime (`gs_host` hooks) | How small does zugojson's runtime get on the stock runtime? | ~1 week |
| 2 | Context instead of static globals | Do reentrancy and reset-on-failure cost anything measurable? | 3–5 days |
| 3 | Checked growth instead of guard pages | Can Goose run with no signals and no mmap, and at what cost? | 3–6 weeks, uncertain |

## Global Constraints

- Never commit or push to `main`. Each task works on its own branch,
  `runtime-research/<task-slug>`, branched from `main` or from the
  previous task's branch.
- `main` keeps the upstream pin. A fork pin appears only on research
  branches. A pull request that changes the pin, the runtime or
  `tools/regenerate.sh` must say so.
- Never edit generated files: `src/zugojson_goose.{c,h}`,
  `src/goose_version.h`, and from Task 4 on `src/goose_runtime.c`. Change
  the fork or `tools/regenerate.sh`, then regenerate.
- `tools/check-symbols.sh` stays clean on every built `zugojson.so`.
- `devtools::check()` gives 0 errors, 0 warnings and 0 notes, apart from
  "New submission".
- Tests assert on condition classes, never on message text. Every test
  builds its own inputs inside `test_that()`.
- First-party native symbols take the prefix `zugojson_` or `goose_r_`.
  The prefix `gs_*` belongs to Goose.
- Benchmark an installed build (`R CMD INSTALL .`), never `load_all()`.
- When a task changes an invariant in `CLAUDE.md`, the same commit updates
  `CLAUDE.md`.
- Creating the fork, opening upstream issues and posting results are
  outward-facing steps. Ask the user before each one.

## Review Focus

These five failures are the most likely to bite and no task would test
them by default. Each one has a test in the task that owns the code.

1. **An R error or interrupt inside a body after Goose grew its stacks.**
   The stacks must be rewound, the fault handler gone and Goose still
   usable. Test: Task 2, `an R error inside a Goose call leaves Goose
   usable`.
2. **A Goose failure after the body allocated R objects.** There must be
   no PROTECT stack imbalance warning. Test: Task 2, `a Goose failure
   after R allocation leaves PROTECT balanced`.
3. **R code inside a body calls back into zugojson.** Before contexts
   exist, a nested call must be refused with a runtime error, not run over
   the outer call's globals. With contexts (Task 5), it must work. Tests:
   Task 2, `re-entering Goose from R is refused`, which Task 5 flips to
   `re-entering Goose from R works`.
4. **A fault outside the data stacks while a body runs R code**, such as
   deep R recursion. R must still handle it. Test: Task 2, `R's recursion
   limit still works inside a Goose call`.
5. **A data stack overflow.** It must be an R error, not a crash. It is
   untested today, because it needs stacks shrunk at compile time. Test:
   Task 6, `a small stack overflows into a runtime error`.

---

### Task 1: Reproducible benchmark baseline

**Files:**
- Create: `tools/bench.R`
- Create: `.agents/research/bench-baseline.csv` (output, committed)

**Interfaces:**
- Produces: `Rscript tools/bench.R <label>` writes
  `.agents/research/bench-<label>.csv` with the columns `case`, `task` and
  `seconds`. Later tasks compare against `bench-baseline.csv`.

- [ ] **Step 1:** Write `tools/bench.R`. It builds the four README
  documents with `jsonlite::toJSON()`: integers, doubles, short strings
  and records, each 1–4 MB, with `set.seed(1)`. It times `json_minify`,
  `json_format` and `json_valid` on each one, as the best of five
  `system.time()` elapsed values. It adds one case, `per_call`:
  `json_valid(rep("[1]", 1e5))`. This case measures the set-up cost per
  call (stack save and handler swap).
- [ ] **Step 2:** Run `R CMD INSTALL . && Rscript tools/bench.R baseline`.
  Expected: a 13-row CSV. The minify and format rows are within 20% of the
  README table.
- [ ] **Step 3:** Commit: `Add a benchmark script and baseline for the
  runtime research`.

### Task 2: Piece 0: let bodies call R (`R_UnwindProtect`)

**Files:**
- Modify: `src/goose_r_runtime.c` (`goose_r_run`, new helpers)
- Modify: `src/goose_r_runtime.h`
- Modify: `src/zugojson_r.c` (a test hook and registration)
- Modify: `R/json.R` (internal probe wrappers, next to `index_probe`)
- Modify: `CLAUDE.md` (the "No R API inside `goose_r_run()`" invariant)
- Test: `tests/testthat/test-runtime.R`

**Interfaces:**
- Produces, in `goose_r_runtime.h`:
  - `int goose_r_run(void (*body)(void *), void *data, char *err, size_t errlen);`
    keeps its signature. It now also survives an R longjmp out of `body`.
  - `int goose_r_stack_use(double *use, int max);` writes `top - base` for
    each region and returns the count.
  - `int goose_r_fault_handler_installed(void);` returns 1 while Goose's
    SIGSEGV handler is the current one.
- Produces `.Call` hooks: `zugojson_c_callback_probe(fn, fail_after)`,
  `zugojson_c_stack_use()` and `zugojson_c_fault_handler_installed()`.
  Their R wrappers are `callback_probe(fn, fail_after = FALSE)`,
  `stack_use()` and `fault_handler_installed()`.

- [ ] **Step 1: Write the failing tests** in `test-runtime.R`:

```r
probe_error <- function() {
  stop(structure(class = c("probe_error", "error", "condition"),
                 list(message = "probe", call = NULL)))
}

test_that("an R error inside a Goose call leaves Goose usable", {
  json_minify("[1]")
  before <- stack_use()
  for (k in 1:200) {
    expect_error(callback_probe(probe_error), class = "probe_error")
  }
  expect_identical(stack_use(), before)
  expect_false(fault_handler_installed())
  expect_identical(json_minify("[1,[2,{}]]"), "[1,[2,{}]]")
})

test_that("a Goose failure after R allocation leaves PROTECT balanced", {
  expect_no_warning(for (k in 1:200) {
    try(callback_probe(function() 1, fail_after = TRUE), silent = TRUE)
  })
  expect_error(callback_probe(function() 1, fail_after = TRUE),
               class = "zugojson_runtime_error")
})

test_that("re-entering Goose from R is refused", {
  expect_error(callback_probe(function() json_minify("[1]")),
               class = "zugojson_runtime_error")
  expect_identical(json_minify("[2]"), "[2]")
})

test_that("R's recursion limit still works inside a Goose call", {
  f <- function(n) f(n + 1)
  res <- tryCatch(callback_probe(function() f(1)), error = function(e) "caught")
  expect_identical(res, "caught")
  expect_false(fault_handler_installed())
})
```

- [ ] **Step 2:** Run `Rscript -e 'devtools::test(filter = "runtime")'`.
  Expected: FAIL, because `callback_probe` is not defined.
- [ ] **Step 3: Implement.**
  - `goose_r_run` wraps the `sigsetjmp` and `body` call in
    `R_UnwindProtect`. The cleanup runs only when `jump` is TRUE. It
    rewinds the stack tops, restores `active_jump` and both signal
    handlers, then lets R continue the unwind. The continuation token is
    made with `R_MakeUnwindCont()` and protected before the run.
  - `goose_r_run` returns 1 with the message "Goose re-entered from R
    during a Goose call" when `active_jump` is already set.
  - The body of `zugojson_c_callback_probe`:
    1. it calls `zugojson_format()` on a 10,000-element array, so the
       stacks grow;
    2. it evaluates `fn()`, holding R objects only in a `VECSXP` holder
       that the entry point protected before the run (no `PROTECT` inside
       the body);
    3. if `fail_after` is set, it calls `zugojson_index_probe(7)`.
- [ ] **Step 4:** Run `Rscript -e 'devtools::test(shuffle = TRUE)'`.
  Expected: all tests pass.
- [ ] **Step 5:** Rewrite the `CLAUDE.md` invariant to say: "Bodies may
  call R. They hold R objects only in a holder protected outside
  `goose_r_run()`, never with `PROTECT` inside it." Then run
  `devtools::check()`, `tools/check-symbols.sh` and
  `Rscript tools/bench.R piece0`. Expected: check clean, and `per_call`
  within 10% of baseline (the cost of `R_UnwindProtect`).
- [ ] **Step 6:** Commit: `Let Goose bodies call R through R_UnwindProtect`.

### Task 3: Pin plumbing for a Goose fork

**Files:**
- Create: `tools/goose/REMOTE` (one line, `https://github.com/aardappel/goose.git`)
- Modify: `tools/regenerate.sh` (it writes `goose_repository` from `REMOTE` into `PROVENANCE`)
- Modify: `.github/workflows/goose.yaml:24` (it clones `$(cat tools/goose/REMOTE)`)

**Interfaces:**
- Produces: a research branch switches to the fork by changing `REMOTE`
  and `PIN` together. Nothing else changes.

- [ ] **Step 1:** Ask the user before running `gh repo fork aardappel/goose
  --clone=false`. Create the branch `hosted-runtime` in the fork at
  `e76d5c9`.
- [ ] **Step 2:** Make the changes listed above.
- [ ] **Step 3:** Run `tools/regenerate.sh --verify <checkout at pin>`.
  Expected: it passes. `PROVENANCE` is unchanged, because `REMOTE` is
  still upstream.
- [ ] **Step 4:** Commit: `Read the Goose repository from tools/goose/REMOTE`.
  The pull request says it changes `tools/regenerate.sh`.

### Task 4: Piece 1: hosted stock runtime

**Files (fork, branch `hosted-runtime`):**
- Modify: `src/runtime/runtime.h` (the `gs_host` API, and `GS_HOSTED` implies `GS_NEED_THREADS 0`)
- Modify: `src/runtime/runtime_impl.h` (failures, output, start-up and `gs_reserve_region` go through the host)
- Modify: `src/runtime/runtime_os.h:403-441` (stdio goes through `host.out` or `host.fail`)
- Modify: `src/main.cpp` (`--emit-runtime --hosted` writes `#define GS_HOSTED 1`)
- Modify: the `__int128` typedef, wrapped in `__extension__`, so zugojson's patch goes
- Create: `test/hosted/run.sh`, `test/hosted/fail.goose`, `test/hosted/host.c`

**Files (zugojson):**
- Create: `src/goose_runtime.c` (generated by `goose --emit-runtime --hosted`)
- Create: `src/goose_r_host.c`, which replaces `src/goose_r_runtime.c`. It
  holds the hooks, `goose_r_run`, the fault handler and Task 2's helpers.
- Delete: `src/goose_vendor.c` and `src/goose_r_runtime.c`
- Modify: `tools/regenerate.sh` (emit the runtime; drop the anchor ranges and the `__int128` sed)
- Modify: `tools/goose/PIN` and `tools/goose/REMOTE` (the fork)
- Modify: `inst/COPYRIGHTS`, the `DESCRIPTION` comment on `goose_vendor.c`, and the Architecture section of `CLAUDE.md`

**Interfaces:**
- Produces, in the fork's `runtime.h` under `GS_HOSTED`. This is zugoose
  design §6.3, with sizes added to `reserve` and a stream added to `out`:

```c
typedef struct {
    void (*fail)(const char *msg);                          /* must not return */
    void (*out)(int stream, const uint8_t *p, int64_t len); /* 1 stdout, 2 stderr */
    uint8_t *(*reserve)(gs_stack *stack, uint64_t usable, uint64_t gap);
} gs_host;
GS_API void gs_set_host(const gs_host *host);
```

- Consumes: Task 2's `goose_r_run`, `goose_r_stack_use` and
  `goose_r_fault_handler_installed`. Their signatures stay the same, so
  `src/zugojson_r.c` does not change.

- [ ] **Step 1: Fork test first.** `test/hosted/run.sh` does four things:
  1. it emits the runtime with `--hosted`;
  2. it compiles `fail.goose`, an export that indexes out of bounds, with
     `goose -o`;
  3. it links both with `host.c`, which sets the hooks and catches `fail`
     with `setjmp`;
  4. it runs the program, which exits 0 only if `fail` received the
     message, and checks that `nm -u` shows none of the symbols
     `tools/check-symbols.sh` forbids.

  Expected before the change: it fails, because `--hosted` is unknown.
- [ ] **Step 2:** Implement `GS_HOSTED` in the fork. Under it, the runtime
  references none of the forbidden symbols, installs no signal handler,
  calls no `sigaltstack` and does not call `setvbuf`. Run
  `test/hosted/run.sh` and Goose's own suite. Expected: both pass. Commit
  in the fork.
- [ ] **Step 3:** In zugojson, point `PIN` and `REMOTE` at the fork and
  change `regenerate.sh`. Write `goose_r_host.c` with the same behaviour
  as today, and Task 2's, through the hooks. Run `tools/regenerate.sh` and
  then `--verify`. Expected: the generated files are rewritten, and
  `--verify` passes.
- [ ] **Step 4:** Run `devtools::test(shuffle = TRUE)`, `devtools::check()`,
  `tools/check-symbols.sh` on the installed `.so`, and
  `Rscript tools/bench.R piece1`. Expected: everything passes, every row
  is within 3% of `piece0`, and `wc -l src/goose_r_host.c` is under 120,
  against 245 today.
- [ ] **Step 5:** Record in `.agents/research/notes.md`:
  - the first-party runtime line counts before and after;
  - the `regenerate.sh` line counts before and after;
  - every `runtime_os.h` function `GS_HOSTED` had to touch, as material
    for the upstream proposal.

  Commit: `Run on the hosted stock runtime from the Goose fork`.

### Task 5: Piece 2: contexts instead of static globals

**Files:**
- Fork: `src/codegen.h:1470` and the worker-instance code it shares
  (`gs_stack_block`, `gs_init_globals`). Behind `--context`, the
  generated header gains the context API.
- zugojson: `tools/regenerate.sh` (passes `--context`)
- zugojson: `src/goose_r_host.c` (a pool of contexts, one per nesting
  depth, up to 8)
- zugojson: `tools/goose/zugojson.goose`:
  - delete the clearing at the top of each export;
  - add the export `zugojson_dirty_probe(fail: bool) -> const u8[:]`,
    which appends `"x"` to `out` and then fails if `fail` is true.
- zugojson: `src/zugojson_r.c`, `R/json.R` (the `dirty_probe()` hook)
- zugojson: `CLAUDE.md`, which drops "Every export clears its globals first"
- Test: `tests/testthat/test-runtime.R`

**Interfaces:**
- Produces, in the generated `zugojson_goose.h`:

```c
typedef struct goose_ctx goose_ctx;
goose_ctx *goose_ctx_new(void);               /* fresh globals, own data stacks */
void goose_ctx_reset(goose_ctx *ctx);         /* globals re-initialised, stacks empty */
void goose_ctx_free(goose_ctx *ctx);
goose_ctx *goose_ctx_swap(goose_ctx *ctx);    /* make ctx current; returns the previous */
```

- Consumes: Task 4's `reserve` hook, which every new context's stacks go
  through.
- On a failure, `goose_r_run` resets the failed context. It no longer
  rewinds tops one by one.

- [ ] **Step 1: Write the failing tests.**

```r
test_that("a failed call leaves no half-built state", {
  expect_error(dirty_probe(TRUE), class = "zugojson_runtime_error")
  expect_identical(dirty_probe(FALSE), "x")
})

test_that("re-entering Goose from R works", {
  inner <- NULL
  callback_probe(function() inner <<- json_minify("[ 1 ]"))
  expect_identical(inner, "[1]")
  expect_identical(json_minify("[2]"), "[2]")
})
```

  Delete Task 2's `re-entering Goose from R is refused`. Run the tests.
  Expected: both FAIL. The first gives `"xx"`. The second is refused.
- [ ] **Step 2:** Implement `--context` in the fork. Without the flag, the
  output must be byte-identical. Check with Goose's suite and zugojson's
  `--verify` at the previous fork commit. Commit in the fork.
- [ ] **Step 3:** Regenerate zugojson, use contexts in `goose_r_host.c`,
  and delete the clearing in `zugojson.goose`. Run the full suite, check,
  `check-symbols.sh` and `Rscript tools/bench.R piece2`. Expected: all
  green, and each row within 3% of `piece1`. A larger slowdown is the
  cost of reaching `GS_GL` through a pointer. Record it.
- [ ] **Step 4:** Commit: `Run each Goose call in a context and drop the
  clear-globals rule`.

### Task 6: Piece 3: checked growth (research spike)

This task is a spike, not a feature. It ends in one of two ways:
- **go**: the tests below pass and the costs are within the limits;
- **stop**: a written account in `notes.md` of where it failed.

**Files:**
- Fork: `--checked-stacks`. `gs_stack` gains `uint8_t *limit`, which
  changes `goose.h`, `gs_bld_append` and the runtime interface hash.
  Codegen checks capacity before the first write at every site that claims
  stack space: the roughly 21 direct top bumps in `src/*.h` and the
  helpers in `src/runtime_inline.h`. A failed check calls `gs_abort` with
  a new code, "data stack full".
- zugojson: `goose_r_host.c`:
  - `reserve` uses `malloc(usable)`, with no gap;
  - the signal handling, `sigsetjmp` and the region registry are deleted;
  - failures still need a non-local exit, so they use `setjmp` inside
    `R_UnwindProtect`.
- zugojson: a hook, `small_stack_probe(bytes, x)`. It creates a context
  whose stacks are `bytes` large, formats `x` in it, and frees it.
- Test: `tests/testthat/test-runtime.R`

- [ ] **Step 1: Write the failing test.**

```r
test_that("a small stack overflows into a runtime error", {
  big <- paste0("[", strrep("[1,2,3],", 5000), "[]]")
  expect_error(small_stack_probe(4096, big), class = "zugojson_runtime_error")
  expect_identical(small_stack_probe(1e6, "[ 1 ]"), "[1]")
  expect_identical(json_minify("[1]"), "[1]")
})
```

- [ ] **Step 2:** Implement `--checked-stacks` in the fork. Find every
  write that stack-top caching places before a bump, and check before
  that write.
- [ ] **Step 3:** Run zugojson's suite, check and `Rscript tools/bench.R
  piece3`.
  - **Go:** all green, and no row more than 5% slower than `piece2`.
  - **Stop:** a row more than 5% slower, or covering every claim site
    needs stack-top caching turned off. Write up which sites and why in
    `notes.md`.
- [ ] **Step 4 (go only):** Remove the POSIX requirements:
  - remove the `#error` for Windows;
  - remove `OS_type: unix` and the mmap and signals line in
    `SystemRequirements`;
  - add a `NEWS.md` entry.

  Run the r-actions Windows leg. Expected: green.
- [ ] **Step 5:** Commit: `Replace guard pages with checked stack growth`,
  or `Record why checked growth stops here`.

### Task 7: zugoyaml harness (separate repository, its own plan)

When Task 6 starts, write that plan from this outline:
- Port `goose-evaluations/yaml/goose/yaml.goose` (593 lines, Apache-2.0)
  to exports:
  - parse plus canonical JSON out;
  - the node and byte counts;
  - a nesting limit like zugojson's 512.
- Use zugojson's `goose_r_host.c` from the furthest piece that reached go.
- Use the `yaml` package as the oracle, on the YAML subset the port
  supports. Anchors, aliases and tags must give a classed error.
- Run the four-way benchmark in one process, on the evaluation's
  Kubernetes inputs:
  - `twin.c` built into the package behind a test hook;
  - Goose on today's R runtime;
  - Goose on the furthest research runtime;
  - the `yaml` package.

### Task 8: Write-up and upstream proposal

**Files:**
- Create: `.agents/research/report.md`

- [ ] **Step 1:** Write the report from `notes.md` and the benchmark CSVs.
  For each piece, it gives:
  - lines of first-party glue before and after;
  - the invariants removed from `CLAUDE.md`;
  - the benchmark delta;
  - the fork diff size.
- [ ] **Step 2:** Draft one upstream issue per piece that reached go, for
  `aardappel/goose`, with the fork commits. Pieces 1 and 3 are separate
  proposals: hooks are small, checked growth changes codegen. Show the
  drafts to the user. Post nothing without approval.
- [ ] **Step 3:** Draft the matching change to zugoose's design (§6.3 and
  Q1) for the user to review in that repository.
