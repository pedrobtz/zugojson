# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

zugojson formats, minifies and validates JSON text with a parser and
printer written in Goose (<https://github.com/aardappel/goose>) and compiled
ahead of time to C. It is a demonstration that a Goose library can be
bundled in an R package, not a jsonlite competitor. It has no hard runtime
dependencies. It does not convert JSON to R objects yet.

`.agents/design.md` and `.agents/roadmap.md` are still the `pkg-init`
stubs. Until they are written, this file is the reference.

## Current state

Verified 2026-10-25 on Linux, R 4.6.1:

- `json_format()`, `json_minify()` and `json_valid()` work, with classed
  conditions for parse, input and runtime errors.
- `R CMD check --as-cran` is clean apart from the new-submission NOTE.
- The test suite passes, including jsonlite as an oracle.
- macOS should work, because it uses the same POSIX code, but it has not
  been run. Windows is not written: `goose_r_runtime.c` stops the build with
  an `#error`, and `DESCRIPTION` says `OS_type: unix`.
- About as fast as jsonlite; the README has the numbers.
- Not built: parsing to R lists, path queries, and the Windows runtime.

## Commands

Run from the package root.

```sh
Rscript -e 'devtools::document()'                # roxygen -> NAMESPACE, man/
Rscript -e 'devtools::test()'                    # full testthat suite
Rscript -e 'devtools::check()'                   # R CMD check
tools/regenerate.sh <goose-checkout>             # rewrite generated C
tools/regenerate.sh --verify <goose-checkout>    # check it is current
tools/check-symbols.sh <path>/zugojson.so        # forbidden symbols
```

The Goose checkout must be at the commit in `tools/goose/PIN` and built
with `cmake -S . -B build && cmake --build build`.

`devtools::load_all()` compiles at `-O0`. Benchmark an installed build.

## Architecture

```text
tools/goose/zugojson.goose   the parser and printer, in Goose (the source)
tools/regenerate.sh          Goose -> the four generated files in src/
src/zugojson_goose.{c,h}     generated: the program, with no main
src/goose_version.h          generated: the runtime interface hash
src/goose_vendor.c           generated: byte search and number formatting,
                             verbatim from Goose's runtime_impl.h
src/goose_r_runtime.{c,h}    the replacement Goose runtime for R
src/zugojson_number.c        strtod for the parser, through an extern fn
src/zugojson_r.c             the .Call entry points
R/json.R                     the R API and the condition constructors
```

The R-to-Goose boundary is `goose_r_run()`. Every call into generated code
goes through it, including `goose_init()` in `R_init_zugojson()`. It saves
each data stack's top and installs the guard-page fault handler. A Goose
failure then jumps back to it, the tops are rewound and the handlers
restored, and it returns the message. The entry point raises the R
condition only after that.

Exports return bytes plus a length. A syntax error comes back as text
starting with `!`, which rendered JSON never does. The `.Call` functions
return `c(kind, text)`, and `unwrap()` in R turns a non-empty `kind` into a
condition.

## Invariants that are easy to break

- **No R API inside `goose_r_run()`.** A body function or anything Goose
  calls, such as `zugojson_strtod`, must not allocate R objects or raise R
  errors. An R longjmp would skip the stack rewind and leave Goose's
  SIGSEGV handler in place of R's.
- **Every export clears its globals first.** After a failure the data stack
  tops are rewound but Goose globals are not. An export that relies on what
  a previous call left in `pool` or `out` reads half-built state.
- **Never edit generated files.** CI rebuilds Goose at the pin and fails if
  `src/zugojson_goose.c`, its header, `goose_version.h` or
  `goose_vendor.c` differ from what `tools/regenerate.sh` writes.
- **Generated code has no capacity checks.** Goose relies on a PROT_NONE
  guard gap after each data stack. `gs_reserve_region()` must keep that gap
  and the fault handler must keep turning a hit into a runtime error, or an
  overflow becomes a crash.
- **The nesting limit protects the C stack.** Rendering and parsing
  recurse. Without the 512 limit in `parse_value`, deep input overflows the
  native stack, which no handler here catches.
- **Bumping the Goose pin can change the runtime interface.** The version
  hash in `goose_version.h` makes a mismatch a link error. Read the diff of
  Goose's `runtime.h` too: a new `GS_API` function the generated C
  references needs an implementation in `goose_r_runtime.c` or a new range
  in `goose_vendor.c`. Link at `-O0`, because `-O2` hides references from
  unused inline helpers.
- **The `__int128` patch.** `tools/regenerate.sh` wraps the 128-bit type in
  `__extension__`, because `-pedantic` calls it "ISO C", which R CMD check
  counts as significant. The script fails if the anchor is not found
  exactly once.
- **The symbol names `gs_*` are Goose's.** They cannot take the package
  prefix, because the generated C calls them by those names.

## Testing conventions

- Every test builds its own inputs inside `test_that()`.
- Assert on condition classes, never message text.
- jsonlite is the oracle in `test-jsonlite.R`, skipped when it is missing.
  It checks that formatting does not change what a document means.
- `test-runtime.R` drives the runtime's error path through
  `zugojson_index_probe`, a Goose export that fails a bounds check on
  demand. A data stack overflow is not tested in the suite, because it
  needs stacks shrunk at compile time. It was tested by hand with
  `-DGS_STACK_RESERVE='(1ull<<20)'` in `PKG_CPPFLAGS`.

## Definition of done

`devtools::document()` and `devtools::check()` clean, meaning 0 errors, 0
warnings and 0 notes, except "New submission" before the first release.
`devtools::test(shuffle = TRUE)` green. `tools/regenerate.sh --verify`
passes. A user-facing change also needs a test, roxygen documentation and
a `NEWS.md` entry.

## Editing rules

- Change the JSON code in `tools/goose/zugojson.goose`, then run
  `tools/regenerate.sh`, and commit both together.
- roxygen comments are the source. Never edit `man/` or `NAMESPACE` by hand.
- Keep prose simple and short. One idea per sentence.
- Use `lower_snake_case`, and prefix first-party native symbols with
  `zugojson_`.

## Vendored native code

Goose, Apache-2.0, Wouter van Oortmerssen. The pinned commit is in
`tools/goose/PIN`, and `tools/goose/PROVENANCE` records the checksums of
the generated files. `inst/licenses/goose-LICENSE` is upstream's licence,
and `inst/COPYRIGHTS` lists which files it covers.

The stock runtime, `src/runtime/runtime_impl.h` upstream, is not vendored.
Only `goose_vendor.c`'s verbatim ranges come from it. CRAN's compiled-code
check applies to everything: `tools/check-symbols.sh` fails on `exit`,
`_exit`, `_Exit`, `abort`, `stdout`, `stderr`, the printf family and the
system RNG, and `goose.yaml` runs it on Linux and macOS.

## Upstream defects found

- Goose's `parse_flt` in `stdlib/std.goose` can be one ulp off for long
  mantissas and large exponents, as its own comment says. `1e300` reads
  back as `1.0000000000000002e+300`. zugojson uses `strtod` instead.
- The stock runtime has no way for an embedding host to take over aborts
  and printing. A hook for that would remove most of
  `goose_r_runtime.c`.

Neither has been reported upstream yet.

## Commits and pull requests

Short, imperative, sentence-case commit subjects. Never commit or push to
the default branch. Work on a branch and open a pull request. A change to
the pin, the runtime or `tools/regenerate.sh` must say so in the pull
request.
