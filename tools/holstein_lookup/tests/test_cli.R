source("tools/holstein_lookup/R/data.R")
source("tools/holstein_lookup/R/jobs.R")
source("tools/holstein_lookup/R/cli.R")

directory <- tempfile("holstein-cli-test-")
dir.create(directory)
input <- file.path(directory, "input.csv")
output <- file.path(directory, "output.csv")
writeLines(c("animal_id", "001", "002", "003"), input)
options <- parse_cli_options(c(
  "--input", input, "--output", output,
  "--search-prefix", "COLLEGE ", "--delay-seconds", "0"
))
lookup <- function(id, source) {
  row <- data.frame(
    animal_id = id, searched_id = paste0("COLLEGE ", id), input_source = source,
    match_count = "0", match_status = "not_found", error_message = "",
    birth_codes = "", genotyping_code = ""
  )
  if (id == "002") {
    row$match_status <- "unique"
    row$match_count <- "1"
    row$Name <- "Fixture animal"
  }
  if (id == "003") {
    row$match_status <- "error"
    row$error_message <- "Temporary failure"
  }
  row
}
run_cli(options, lookup)
rows <- read_result_csv(output)
stopifnot(nrow(rows) == 2, rows$Name[[2]] == "Fixture animal")
stopifnot(nrow(read_result_csv(paste0(output, ".failed.csv"))) == 1)

retried <- character()
run_cli(options, function(id, source) {
  retried <<- c(retried, id)
  row <- lookup(id, source)
  row$match_status <- "not_found"
  row$error_message <- ""
  row
})
stopifnot(identical(retried, "003"), nrow(read_result_csv(output)) == 3)
stopifnot(inherits(try(parse_cli_options(c("--input", input)), silent = TRUE), "try-error"))
# A directory batch can contain empty files alongside populated files.
input_directory <- file.path(directory, "inputs")
dir.create(input_directory)
file.copy(input, file.path(input_directory, "animals.csv"))
writeLines("animal_id", file.path(input_directory, "empty.csv"))
stopifnot(nrow(read_cli_ids(input_directory, "animal_id")) == 3)
unlink(directory, recursive = TRUE)
cat("CLI schema, resume, and retry checks passed.\n")
