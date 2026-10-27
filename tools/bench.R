# Benchmark an installed zugojson for the runtime research.
#
# Usage, from the package root:
#   R CMD INSTALL . && Rscript tools/bench.R <label>
#
# Writes .agents/research/bench-<label>.csv with the columns case, task and
# seconds. Each time is the best of ten elapsed times, divided by the
# number of repetitions in one timing, so it is seconds per call.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L || !nzchar(args[[1]])) {
  stop("usage: Rscript tools/bench.R <label>", call. = FALSE)
}
label <- args[[1]]

library(zugojson)

best_of <- function(expr, reps = 20L, n = 10L) {
  expr <- substitute(expr)
  env <- parent.frame()
  min(vapply(seq_len(n), function(i) {
    system.time(for (r in seq_len(reps)) eval(expr, env))[["elapsed"]]
  }, numeric(1))) / reps
}

set.seed(1)
n <- 200000L
docs <- list(
  integers = jsonlite::toJSON(sample.int(1e6, n)),
  doubles = jsonlite::toJSON(runif(n / 2) * 1000, digits = NA),
  strings = jsonlite::toJSON(
    vapply(seq_len(n), function(i) paste(sample(letters, 6), collapse = ""), "")
  ),
  records = jsonlite::toJSON(data.frame(
    id = seq_len(n / 10),
    name = sprintf("item%05d", seq_len(n / 10)),
    price = round(runif(n / 10) * 100, 2),
    ok = sample(c(TRUE, FALSE), n / 10, replace = TRUE)
  ))
)
docs <- lapply(docs, as.character)

rows <- list()
for (case in names(docs)) {
  x <- docs[[case]]
  rows[[length(rows) + 1L]] <- data.frame(
    case = case,
    task = c("minify", "format", "valid"),
    seconds = c(
      best_of(json_minify(x)),
      best_of(json_format(x)),
      best_of(json_valid(x))
    )
  )
}

# The set-up cost of one call: stack save and handler swap.
short <- rep("[1]", 1e5)
rows[[length(rows) + 1L]] <- data.frame(
  case = "per_call", task = "valid", seconds = best_of(json_valid(short), reps = 1L)
)

res <- do.call(rbind, rows)
dir.create(".agents/research", showWarnings = FALSE, recursive = TRUE)
path <- file.path(".agents/research", paste0("bench-", label, ".csv"))
utils::write.csv(res, path, row.names = FALSE)

sizes <- vapply(docs, function(x) nchar(x, type = "bytes") / 2^20, numeric(1))
message(paste(sprintf("%-8s %.1f MB", names(sizes), sizes), collapse = "\n"))
print(res, row.names = FALSE)
message("Wrote ", path)
