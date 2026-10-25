# The replacement Goose runtime: a runtime failure must be an R error, and
# Goose must keep working afterwards.

test_that("a Goose bounds-check failure is a runtime error", {
  expect_identical(index_probe(1), 20)
  err <- expect_error(index_probe(7), class = "zugojson_runtime_error")
  expect_s3_class(err, "zugojson_error")
})

test_that("Goose keeps working after many runtime failures", {
  for (k in 1:1000) {
    try(index_probe(7), silent = TRUE)
  }
  expect_identical(json_minify("[1,[2,{}]]"), "[1,[2,{}]]")
  expect_identical(index_probe(2), 30)
})

test_that("R's own error handling still works after Goose calls", {
  json_minify("[1]")
  try(index_probe(7), silent = TRUE)
  f <- function(n) f(n + 1)
  res <- tryCatch(f(1), error = function(e) "caught")
  expect_identical(res, "caught")
})
