# Benchmark an installed zugojson for the runtime research.
#
# Usage, from the package root:
#   R CMD INSTALL --preclean . && Rscript tools/bench.R <label>
#
# --preclean matters: devtools::load_all() leaves -O0 objects in src/, and
# a plain install reuses them.
#
# Writes .agents/research/bench-<label>.csv with the columns case, task and
# seconds, in seconds per call.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L || !nzchar(args[[1]])) {
  stop("usage: Rscript tools/bench.R <label>", call. = FALSE)
}
label <- args[[1]]

library(zugojson)
source("tools/bench-common.R")

docs <- bench_docs()

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

bench_write(do.call(rbind, rows), paste0("bench-", label), docs)
