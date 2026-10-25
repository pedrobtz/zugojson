# zugojson: JSON Formatting with a Parser Written in 'Goose'

Formats, minifies and validates 'JSON' text with a parser and printer
written in the 'Goose' programming language
(<https://github.com/aardappel/goose>) and compiled ahead of time to C,
which the package bundles. 'Goose' is a memory-safe systems language
with no heap: the parsed document lives in one contiguous block linked
by 4-byte relative offsets. The package replaces the 'Goose' runtime
with a small one that reports every runtime failure as an R error
instead of ending the process. No 'Goose' compiler is needed to install
the package.

## See also

Useful links:

- <https://github.com/pedrobtz/zugojson>

- <https://pedrobtz.github.io/zugojson/>

- Report bugs at <https://github.com/pedrobtz/zugojson/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Other contributors:

- Wouter van Oortmerssen (author of the 'Goose' language and compiler;
  the JSON sample the parser derives from, the runtime code the
  generated C inlines and the runtime pieces in src/goose_vendor.c)
  \[contributor, copyright holder\]
