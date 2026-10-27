# Compare an installed zugojson with zujson (yyjson) and jsonlite.
#
# Usage, from the package root:
#   R CMD INSTALL --preclean . && Rscript tools/bench-compare.R
#
# Writes .agents/research/compare.csv with the columns case, task, zugojson,
# zujson and jsonlite, in seconds per call.
#
# zujson has no text-to-text minify or format. Its column times
# json_write(json_parse(x, simplify = FALSE)), which also builds and walks
# R objects. Only the valid rows compare like with like.

library(zugojson)
source("tools/bench-common.R")

docs <- bench_docs()

zujson_minify <- function(x) {
  zujson::json_write(zujson::json_parse(x, simplify = FALSE))
}
zujson_format <- function(x) {
  zujson::json_write(zujson::json_parse(x, simplify = FALSE), pretty = TRUE)
}

rows <- list()
for (case in names(docs)) {
  x <- docs[[case]]
  # Every minifier must agree on what the document means.
  stopifnot(
    identical(jsonlite::fromJSON(json_minify(x)), jsonlite::fromJSON(x)),
    identical(jsonlite::fromJSON(zujson_minify(x)), jsonlite::fromJSON(x))
  )
  rows[[length(rows) + 1L]] <- data.frame(
    case = case,
    task = c("minify", "format", "valid"),
    zugojson = c(
      best_of(json_minify(x)),
      best_of(json_format(x)),
      best_of(json_valid(x))
    ),
    zujson = c(
      best_of(zujson_minify(x)),
      best_of(zujson_format(x)),
      best_of(zujson::json_validate(x))
    ),
    jsonlite = c(
      best_of(jsonlite::minify(x)),
      best_of(jsonlite::prettify(x)),
      best_of(jsonlite::validate(x))
    )
  )
}

bench_write(do.call(rbind, rows), "compare", docs)
