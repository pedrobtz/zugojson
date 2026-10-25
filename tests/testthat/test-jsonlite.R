# jsonlite as an oracle: formatting must not change what a document means.

test_that("formatting preserves the document jsonlite reads", {
  skip_if_not_installed("jsonlite")
  docs <- c(
    '{"a": [1, 2.5, -3e-2, true, false, null], "b": {"c": "d\\u00e9"}}',
    '[{"x": 1}, {"x": 2, "y": [[], {}]}]',
    '"just a string"',
    "[1.7976931348623157e308, 5e-324, 0.1, 123456789012]"
  )
  for (doc in docs) {
    want <- jsonlite::fromJSON(doc, simplifyVector = FALSE)
    expect_identical(
      jsonlite::fromJSON(json_format(doc), simplifyVector = FALSE),
      want
    )
    expect_identical(
      jsonlite::fromJSON(json_minify(doc), simplifyVector = FALSE),
      want
    )
  }
})

test_that("json_valid agrees with jsonlite on a mixed set", {
  skip_if_not_installed("jsonlite")
  docs <- c("[1,2]", "[1,2", "{\"a\":1}", "{a:1}", "null", "[,]", "{}")
  expect_identical(json_valid(docs), vapply(docs, jsonlite::validate, TRUE,
    USE.NAMES = FALSE))
})
