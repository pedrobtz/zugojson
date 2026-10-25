test_that("json_valid is vectorised and keeps NA", {
  expect_identical(
    json_valid(c("[1, 2]", "[1, 2", "{}", NA, '{"a":')),
    c(TRUE, FALSE, TRUE, NA, FALSE)
  )
  expect_identical(json_valid(character()), logical())
})

test_that("json_valid rejects non-character input", {
  expect_error(json_valid(1), class = "zugojson_input_error")
})
