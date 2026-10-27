# Shared by tools/bench.R and tools/bench-compare.R: the timer and the four
# documents, so both scripts time the same inputs.

# The best of n elapsed times, divided by the number of repetitions in one
# timing, so it is seconds per call.
best_of <- function(expr, reps = 20L, n = 10L) {
  expr <- substitute(expr)
  env <- parent.frame()
  min(vapply(seq_len(n), function(i) {
    system.time(for (r in seq_len(reps)) eval(expr, env))[["elapsed"]]
  }, numeric(1))) / reps
}

bench_docs <- function() {
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
  lapply(docs, as.character)
}

bench_write <- function(res, name, docs) {
  dir.create(".agents/research", showWarnings = FALSE, recursive = TRUE)
  path <- file.path(".agents/research", paste0(name, ".csv"))
  utils::write.csv(res, path, row.names = FALSE)
  sizes <- vapply(docs, function(x) nchar(x, type = "bytes") / 2^20, numeric(1))
  message(paste(sprintf("%-8s %.1f MB", names(sizes), sizes), collapse = "\n"))
  print(res, row.names = FALSE)
  message("Wrote ", path)
}
