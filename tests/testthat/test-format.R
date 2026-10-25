test_that("json_format indents by two spaces per level", {
  out <- json_format('{"a":[1,{"b":null}],"c":true}')
  expect_identical(
    out,
    '{\n  "a": [\n    1,\n    {\n      "b": null\n    }\n  ],\n  "c": true\n}'
  )
})

test_that("json_minify removes insignificant whitespace", {
  expect_identical(json_minify(' { "a" : [ 1 , 2 ] } '), '{"a":[1,2]}')
  expect_identical(json_minify("[]"), "[]")
  expect_identical(json_minify("{}"), "{}")
  expect_identical(json_format("[]", pretty = FALSE), "[]")
})

test_that("scalars at the top level are documents", {
  expect_identical(json_minify("null"), "null")
  expect_identical(json_minify("false"), "false")
  expect_identical(json_minify('"x"'), '"x"')
  expect_identical(json_minify("-2.5"), "-2.5")
})

test_that("whole numbers are written as integers only within 2^53", {
  expect_identical(json_minify("[1.0, 1e2, -0.5, 1.50]"), "[1,100,-0.5,1.5]")
  expect_identical(json_minify("9007199254740991"), "9007199254740991")
  expect_identical(json_minify("1e300"), "1e+300")
  expect_identical(
    json_minify("1.7976931348623157e308"),
    "1.7976931348623157e+308"
  )
  expect_identical(json_minify("5e-324"), "5e-324")
})

test_that("numbers follow JSON's grammar", {
  bad <- c("01", "1.", ".5", "+1", "1e", "1e+", "--1", "1-2", "0x10", "-")
  for (x in bad) {
    expect_error(json_minify(x), class = "zugojson_parse_error")
  }
  expect_error(json_minify("1e999"), class = "zugojson_parse_error")
  expect_identical(json_minify("[-0, 0.5e-3, 2E+2]"), "[0,0.0005,200]")
})

test_that("strings round-trip through the escapes JSON requires", {
  expect_identical(json_minify('"a\\"b\\\\c"'), '"a\\"b\\\\c"')
  expect_identical(json_minify('"\\n\\t\\r"'), '"\\n\\t\\r"')
  expect_identical(json_minify('"\\b\\f"'), '"\\u0008\\u000c"')
  expect_identical(json_minify('"\\/"'), '"/"')
})

test_that("unicode escapes decode to UTF-8", {
  out <- json_minify('"\\u00e9\\u4e2d"')
  expect_identical(out, "\"é中\"")
  expect_identical(Encoding(out), "UTF-8")
})

test_that("UTF-8 input passes through unchanged", {
  out <- json_minify("[\"été\"]")
  expect_identical(out, "[\"été\"]")
})

test_that("syntax errors are classed and carry the byte offset", {
  err <- expect_error(json_format("[1, 2"), class = "zugojson_parse_error")
  expect_s3_class(err, "zugojson_error")
  expect_identical(err$byte, 5)
  expect_error(json_format('{"a" 1}'), class = "zugojson_parse_error")
  expect_error(json_format("[tru]"), class = "zugojson_parse_error")
  expect_error(json_format("1 2"), class = "zugojson_parse_error")
  expect_error(json_format(""), class = "zugojson_parse_error")
})

test_that("nesting is limited to 512 levels", {
  ok <- paste0(strrep("[", 512), strrep("]", 512))
  expect_identical(json_minify(ok), ok)
  expect_error(
    json_minify(paste0(strrep("[", 513), strrep("]", 513))),
    class = "zugojson_parse_error"
  )
  # Far past the limit is still an error, never a crashed process.
  expect_error(json_minify(strrep("[", 1e6)), class = "zugojson_parse_error")
})

test_that("bad arguments are input errors", {
  expect_error(json_format(1), class = "zugojson_input_error")
  expect_error(json_format(c("[]", "[]")), class = "zugojson_input_error")
  expect_error(json_format(NA_character_), class = "zugojson_input_error")
  expect_error(json_format("[]", pretty = NA), class = "zugojson_input_error")
  bad <- "\xff"
  Encoding(bad) <- "UTF-8"
  expect_error(json_format(bad), class = "zugojson_input_error")
})
