# Format JSON text

Parses a JSON document and writes it back out, either indented or with
all insignificant whitespace removed. The parser and printer are written
in Goose and compiled to C, which the package bundles.

## Usage

``` r
json_format(x, pretty = TRUE)
```

## Arguments

- x:

  A single string holding one JSON document. It is converted to UTF-8
  first.

- pretty:

  If `TRUE`, the default, indent by two spaces per level. If `FALSE`,
  write the most compact form.

## Value

A single string, marked as UTF-8.

## Details

Numbers are stored as doubles. A whole number below 2^53 in magnitude is
written as an integer, and any other number in the shortest form that
reads back as the same double, so `1.50` becomes `1.5` and `1e2` becomes
`100`. Strings are written with the escapes JSON requires, and every
other byte is passed through unchanged.

## Errors

A syntax error signals a condition of class `zugojson_parse_error`, with
the byte offset of the error in its `byte` field. Input that is not a
single non-missing string signals `zugojson_input_error`. A failure
inside the Goose runtime, such as a document too large for its memory,
signals `zugojson_runtime_error`. All three also inherit from
`zugojson_error`.

## See also

[`json_minify()`](https://pedrobtz.github.io/zugojson/reference/json_minify.md)
for the compact form,
[`json_valid()`](https://pedrobtz.github.io/zugojson/reference/json_valid.md)
to test documents without formatting them.

## Examples

``` r
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
json_format('{"a": [1, 2]}', pretty = FALSE)
#> [1] "{\"a\":[1,2]}"

# Syntax errors carry the byte offset where parsing stopped.
tryCatch(json_format("[1, 2"), zugojson_parse_error = function(e) e$byte)
#> [1] 5
```
