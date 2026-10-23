source("R/data.R")
source("R/jobs.R")

ids <- data.frame(animal_id = c("001", "002"), input_source = "fixture.csv")
lookup <- function(id, source) {
  data.frame(
    animal_id = id, searched_id = id, input_source = source,
    match_status = "unique", error_message = ""
  )
}
directory <- tempfile("holstein-job-test-")
dir.create(directory)
outcome <- run_lookup_batch(ids, lookup, 0, directory)
stopifnot(outcome$reason == "complete", length(result_files(directory)) == 2)
writeLines("incomplete", file.path(directory, "result-00000003.rds.tmp"))
stopifnot(length(result_files(directory)) == 2)
stopifnot(readRDS(result_files(directory)[[1]])$animal_id == "001")

blocked_directory <- tempfile("holstein-block-test-")
dir.create(blocked_directory)
blocked_lookup <- function(id, source) {
  data.frame(
    searched_id = id,
    match_status = "error",
    error_message = "Request was blocked by Cloudflare"
  )
}
outcome <- run_lookup_batch(
  data.frame(animal_id = as.character(1:5), input_source = "fixture.csv"),
  blocked_lookup, 0, blocked_directory
)
stopifnot(outcome$reason == "blocked", length(result_files(blocked_directory)) == 3)
unlink(c(directory, blocked_directory), recursive = TRUE)
cat("Batch snapshots and access-block checks passed.\n")
