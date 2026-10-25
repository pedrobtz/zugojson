#' Format JSON text
#'
#' Parses a JSON document and writes it back out, either indented or with
#' all insignificant whitespace removed. The parser and printer are written
#' in Goose and compiled to C, which the package bundles.
#'
#' Numbers are stored as doubles. A whole number below 2^53 in magnitude is
#' written as an integer, and any other number in the shortest form that
#' reads back as the same double, so `1.50` becomes `1.5` and `1e2` becomes
#' `100`. Strings are written with the escapes JSON requires, and every
#' other byte is passed through unchanged.
#'
#' @param x A single string holding one JSON document. It is converted to
#'   UTF-8 first.
#' @param pretty If `TRUE`, the default, indent by two spaces per level.
#'   If `FALSE`, write the most compact form.
#'
#' @return A single string, marked as UTF-8.
#'
#' @section Errors:
#' A syntax error signals a condition of class `zugojson_parse_error`, with
#' the byte offset of the error in its `byte` field. Input that is not a
#' single non-missing string signals `zugojson_input_error`. A failure
#' inside the Goose runtime, such as a document too large for its memory,
#' signals `zugojson_runtime_error`. All three also inherit from
#' `zugojson_error`.
#'
#' @seealso [json_minify()] for the compact form, [json_valid()] to test
#'   documents without formatting them.
#'
#' @examples
#' cat(json_format('{"a": [1, 2.50, {"b": null}], "s": "x"}'))
#' json_format('{"a": [1, 2]}', pretty = FALSE)
#'
#' # Syntax errors carry the byte offset where parsing stopped.
#' tryCatch(json_format("[1, 2"), zugojson_parse_error = function(e) e$byte)
#' @export
json_format <- function(x, pretty = TRUE) {
  x <- check_document(x)
  if (!is.logical(pretty) || length(pretty) != 1L || is.na(pretty)) {
    abort_input("`pretty` must be TRUE or FALSE.")
  }
  unwrap(.Call(zugojson_c_format, x, pretty))
}

#' Minify JSON text
#'
#' Removes all insignificant whitespace from a JSON document. This is
#' `json_format(x, pretty = FALSE)`.
#'
#' @inheritParams json_format
#' @inherit json_format return
#' @inheritSection json_format Errors
#'
#' @examples
#' json_minify('{ "a" : [ 1, 2 ] }')
#' @export
json_minify <- function(x) {
  json_format(x, pretty = FALSE)
}

#' Test whether strings are valid JSON
#'
#' @param x A character vector. Each element is tested as one JSON
#'   document.
#'
#' @return A logical vector the length of `x`: `TRUE` for a valid document,
#'   `FALSE` for a syntax error and `NA` for a missing value.
#'
#' @examples
#' json_valid(c("[1, 2]", "[1, 2", "{}", NA))
#' @export
json_valid <- function(x) {
  if (!is.character(x)) {
    abort_input("`x` must be a character vector.")
  }
  x <- enc2utf8(x)
  res <- .Call(zugojson_c_valid, x)
  if (is.character(res)) {
    unwrap(res)
  }
  res
}

check_document <- function(x) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) {
    abort_input("`x` must be a single, non-missing string.")
  }
  x <- enc2utf8(x)
  if (!validUTF8(x)) {
    abort_input("`x` is not valid UTF-8.")
  }
  x
}

# The C entry points return c(kind, text): kind is "" on success.
unwrap <- function(res) {
  kind <- res[[1L]]
  text <- res[[2L]]
  if (identical(kind, "")) {
    return(text)
  }
  if (identical(kind, "parse")) {
    byte <- regmatches(text, regexpr("[0-9]+$", text))
    abort(
      paste0("JSON syntax error: ", text, "."),
      "zugojson_parse_error",
      byte = if (length(byte)) as.numeric(byte) else NA_real_
    )
  }
  abort(paste0("Goose runtime error: ", text, "."), "zugojson_runtime_error")
}

abort_input <- function(message) {
  abort(message, "zugojson_input_error")
}

abort <- function(message, class, ...) {
  cond <- structure(
    class = c(class, "zugojson_error", "error", "condition"),
    list(message = message, call = NULL, ...)
  )
  stop(cond)
}

# Test hook: a Goose bounds-check failure on demand.
index_probe <- function(i) {
  res <- .Call(zugojson_c_index_probe, as.integer(i))
  if (is.character(res)) {
    unwrap(res)
  }
  res
}
