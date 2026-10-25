# Test whether strings are valid JSON

Test whether strings are valid JSON

## Usage

``` r
json_valid(x)
```

## Arguments

- x:

  A character vector. Each element is tested as one JSON document.

## Value

A logical vector the length of `x`: `TRUE` for a valid document, `FALSE`
for a syntax error and `NA` for a missing value.

## Examples

``` r
json_valid(c("[1, 2]", "[1, 2", "{}", NA))
#> [1]  TRUE FALSE  TRUE    NA
```
