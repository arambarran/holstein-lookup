source("R/data.R")
source("R/jobs.R")
source("R/cli.R")

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

# Headerless CLI runs default to X1 and preserve the first ID through export.
stopifnot(options$has_header, options$id_column == "animal_id")
headerless_input <- file.path(directory, "headerless.csv")
headerless_output <- file.path(directory, "headerless-output.csv")
writeLines(c("0001,note", "0002,other"), headerless_input)
headerless_options <- parse_cli_options(c(
  "--input", headerless_input, "--output", headerless_output,
  "--no-header", "--delay-seconds", "0"
))
stopifnot(!headerless_options$has_header, headerless_options$id_column == "X1")
run_cli(headerless_options, lookup)
stopifnot(identical(read_result_csv(headerless_output)$animal_id, c("0001", "0002")))

# Generated column names also allow selecting IDs outside the first column.
writeLines(c("note,0001", "other,0002"), headerless_input)
second_column <- parse_cli_options(c(
  "--input", headerless_input, "--output", headerless_output,
  "--no-header", "--id-column", "X2"
))
stopifnot(identical(read_cli_ids(second_column$input, second_column$id_column,
  has_header = second_column$has_header)$animal_id, c("0001", "0002")))
stopifnot(inherits(try(read_cli_ids(headerless_input, "X3", has_header = FALSE), silent = TRUE), "try-error"))

# Directory mode applies the header setting to every file and deduplicates IDs.
headerless_directory <- file.path(directory, "headerless-inputs")
dir.create(headerless_directory)
writeLines(c("0001", "0002"), file.path(headerless_directory, "first.csv"))
writeLines(c("0002", "0003"), file.path(headerless_directory, "second.csv"))
stopifnot(identical(read_cli_ids(headerless_directory, "X1", has_header = FALSE)$animal_id,
  c("0001", "0002", "0003")))
unlink(directory, recursive = TRUE)
cat("CLI schema, resume, and retry checks passed.\n")
