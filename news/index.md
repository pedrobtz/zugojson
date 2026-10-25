# Changelog

## zugojson 0.0.0.9000

- Numbers that are not whole are written about five times faster,
  through the shortest-digits code in Goose’s standard library. The text
  written is unchanged.

- Initial version:
  [`json_format()`](https://pedrobtz.github.io/zugojson/reference/json_format.md),
  [`json_minify()`](https://pedrobtz.github.io/zugojson/reference/json_minify.md)
  and
  [`json_valid()`](https://pedrobtz.github.io/zugojson/reference/json_valid.md),
  with a JSON parser and printer written in Goose and compiled to C, and
  a replacement Goose runtime that reports runtime failures as R errors.
