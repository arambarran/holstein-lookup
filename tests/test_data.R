# Pure data contracts used by both the app and command line.
source("R/data.R")
source("R/example.R")

csv <- tempfile(fileext = ".csv")
writeLines(c("tag,note", "004464,a", "004464,b", ",c", "2034,d"), csv)
input <- read_upload(csv)
stopifnot(identical(input$tag, c("004464", "004464", NA_character_, "2034")))
ids <- prepare_ids(input, "tag", "herd.csv")
stopifnot(identical(ids$animal_id, c("004464", "2034")))
stopifnot(normalize_prefix(" COLLEGE  ") == "COLLEGE ")
stopifnot(normalize_prefix("  ") == "")
stopifnot(inherits(try(prepare_ids(input, "missing", "herd.csv"), silent = TRUE), "try-error"))

# Settings reject invalid values before the worker starts.
settings <- lookup_settings(ids, " COLLEGE ", 2, 1, "herd.csv")
stopifnot(nrow(settings$ids) == 1, settings$prefix == "COLLEGE ")
for (invalid in c(NA, Inf, -1, 1.5)) {
  stopifnot(inherits(try(lookup_settings(ids, "", 2, invalid, "x.csv"), silent = TRUE), "try-error"))
}

old <- data.frame(searched_id = c("A", "B"), match_status = c("error", "unique"))
new <- data.frame(searched_id = c("A", "A"), match_status = c("multiple", "multiple"), Name = c("one", "two"))
merged <- merge_results(old, new)
stopifnot(nrow(merged) == 3, sum(merged$searched_id == "A") == 2, !any(merged$match_status == "error"))
stopifnot(identical(pending_ids(ids, "COLLEGE ", data.frame(searched_id = "COLLEGE 004464"))$animal_id, "2034"))

rows <- example_results()
stopifnot(nrow(filter_results(rows, "multiple", "willow")) == 2)
stopifnot(nrow(filter_results(rows, "all", "[")) == 0)
stopifnot(nrow(filter_results(rows, "all", "TIMED OUT")) == 1)
stopifnot(sum(status_counts(rows)) == 6, status_counts(rows)[["multiple"]] == 1)
view <- export_view(rows, c("Name", "animal_id"), list(Name = "desc"))
stopifnot(identical(names(view), c("Name", "animal_id")), view$Name[[1]] == "EXAMPLE WILLOW B")

# CSV persistence must retain a stable schema when later results add fields.
output <- tempfile(fileext = ".csv")
old$birth_codes <- ""
old$genotyping_code <- ""
merged$birth_codes <- ""
merged$genotyping_code <- ""
write_result_csv(old, output)
write_result_csv(merged, output)
restored <- read_result_csv(output)
stopifnot(nrow(restored) == 3, "Name" %in% names(restored))
unlink(c(csv, output))
cat("Data preparation, filtering, export, and CSV checks passed.\n")
