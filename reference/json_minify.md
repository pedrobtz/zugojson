# Minify JSON text

Removes all insignificant whitespace from a JSON document. This is
`json_format(x, pretty = FALSE)`.

## Usage

``` r
json_minify(x)
```

## Arguments

- x:

  A single string holding one JSON document. It is converted to UTF-8
  first.

## Value

A single string, marked as UTF-8.

## Errors

A syntax error signals a condition of class `zugojson_parse_error`, with
the byte offset of the error in its `byte` field. Input that is not a
single non-missing string signals `zugojson_input_error`. A failure
inside the Goose runtime, such as a document too large for its memory,
signals `zugojson_runtime_error`. All three also inherit from
`zugojson_error`.

## Examples

``` r
json_minify('{ "a" : [ 1, 2 ] }')
#> [1] "{\"a\":[1,2]}"
```
