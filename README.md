# zugojson

<!-- badges: start -->
[![R-CMD-check](https://github.com/pedrobtz/zugojson/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/zugojson/actions/workflows/R-CMD-check.yaml)
[![coverage](https://raw.githubusercontent.com/pedrobtz/zugojson/main/.github/badges/coverage.svg)](https://github.com/pedrobtz/zugojson/actions/workflows/coverage.yaml)
<!-- badges: end -->

zugojson formats, minifies and validates JSON text. Its parser and printer
are written in [Goose](https://github.com/aardappel/goose), a memory-safe
systems language with no heap, and compiled ahead of time to C. The package
ships that C, so installing it needs no Goose compiler.

The package is a demonstration that Goose can be used to write R packages.
It is not a replacement for jsonlite.

## Installation

```r
# install.packages("pak")
pak::pak("pedrobtz/zugojson")
```

zugojson builds on Linux and macOS. Windows is not supported yet.

## Usage

```r
library(zugojson)

cat(json_format('{"a": [1, 2.50, {"b": null}], "s": "x"}'))
#> {
#>   "a": [
#>     1,
#>     2.5,
#>     {
#>       "b": null
#>     }
#>   ],
#>   "s": "x"
#> }

json_minify('{ "a" : [ 1, 2 ] }')
#> [1] "{\"a\":[1,2]}"

json_valid(c("[1, 2]", "[1, 2", NA))
#> [1]  TRUE FALSE    NA
```

A syntax error is a condition of class `zugojson_parse_error`. Its `byte`
field holds the offset where parsing stopped.

```r
tryCatch(json_format("[1, 2"), zugojson_parse_error = function(e) e$byte)
#> [1] 5
```

## How it works

The JSON code is in `tools/goose/zugojson.goose`. `tools/regenerate.sh`
compiles it with a pinned Goose compiler into `src/zugojson_goose.c`, a C
file with no `main`.

The parsed document lives in one contiguous block. Each node links to its
next sibling with a 4-byte offset relative to itself, so the tree holds no
pointers.

Generated Goose code needs a runtime. The stock runtime ends the process on
any error, writes to stdout and stderr, and installs process-wide signal
handlers. That is unacceptable inside R, so zugojson replaces it with
`src/goose_r_runtime.c`:

- A Goose runtime error, such as a failed bounds check, becomes an R error
  of class `zugojson_runtime_error`, and later calls keep working.
- Goose's guard-page fault handler is installed only while Goose code runs.
  R's own handlers are restored afterwards.
- Nothing writes to stdout or stderr, and nothing can end the R process.

## Performance

zugojson is about as fast as jsonlite 2.0.0. The table gives seconds for
four documents of 1 to 4 MB, built with jsonlite's `toJSON()`: an array of
integers, one of random doubles, one of short strings and a table of
records. Each time is the best of five runs, with R 4.5.2 on macOS.

| Document | Task | zugojson | jsonlite |
| --- | --- | --- | --- |
| Integers | Minify | 0.017 s | 0.014 s |
| | Pretty-print | 0.019 s | 0.020 s |
| | Validate | 0.013 s | 0.009 s |
| Doubles | Minify | 0.033 s | 0.028 s |
| | Pretty-print | 0.035 s | 0.034 s |
| | Validate | 0.019 s | 0.018 s |
| Strings | Minify | 0.007 s | 0.008 s |
| | Pretty-print | 0.007 s | 0.010 s |
| | Validate | 0.003 s | 0.004 s |
| Records | Minify | 0.020 s | 0.032 s |
| | Pretty-print | 0.023 s | 0.044 s |
| | Validate | 0.012 s | 0.016 s |

## Licence

zugojson is MIT licensed. The Goose-derived files are under Apache-2.0, as
listed in `inst/COPYRIGHTS`.
