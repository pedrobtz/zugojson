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

# Piece 0 of the runtime research: bodies may call R. An R error, a Goose
# failure and a nested call must each leave Goose and R's handlers intact.

test_that("an R error inside a Goose call leaves Goose usable", {
  probe_error <- function() {
    stop(structure(
      class = c("probe_error", "error", "condition"),
      list(message = "probe", call = NULL)
    ))
  }
  json_minify("[1]")
  before <- stack_use()
  for (k in 1:200) {
    expect_error(callback_probe(probe_error), class = "probe_error")
  }
  expect_identical(stack_use(), before)
  expect_false(fault_handler_installed())
  expect_identical(json_minify("[1,[2,{}]]"), "[1,[2,{}]]")
})

test_that("a Goose failure after R allocation leaves PROTECT balanced", {
  expect_no_warning(for (k in 1:200) {
    try(callback_probe(function() 1, fail_after = TRUE), silent = TRUE)
  })
  expect_error(
    callback_probe(function() 1, fail_after = TRUE),
    class = "zugojson_runtime_error"
  )
})

test_that("re-entering Goose from R is refused", {
  expect_error(
    callback_probe(function() json_minify("[1]")),
    class = "zugojson_runtime_error"
  )
  expect_identical(json_minify("[2]"), "[2]")
})

test_that("R's recursion limit still works inside a Goose call", {
  f <- function(n) f(n + 1)
  res <- tryCatch(callback_probe(function() f(1)), error = function(e) "caught")
  expect_identical(res, "caught")
  expect_false(fault_handler_installed())
})
