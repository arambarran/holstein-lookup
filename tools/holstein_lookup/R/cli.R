# Command-line configuration and batch execution. Sourcing this file does not run it.

CLI_USAGE <- paste(
  "Usage: Rscript tools/holstein_lookup/holstein_lookup.R",
  "--input <csv-file-or-directory> --output <output-csv>",
  "[--id-column animal_id] [--search-prefix 'COLLEGE ']",
  "[--limit N] [--delay-seconds 2] [--verbose]"
)

argument_value <- function(args, name, default = NULL) {
  index <- match(name, args)
  if (is.na(index)) {
    return(default)
  }
  if (index == length(args) || startsWith(args[[index + 1]], "--")) {
    stop("Missing value for ", name, call. = FALSE)
  }
  args[[index + 1]]
}

parse_cli_options <- function(args) {
  options <- list(
    input = argument_value(args, "--input"),
    output = argument_value(args, "--output"),
    id_column = argument_value(args, "--id-column", "animal_id"),
    prefix = argument_value(args, "--search-prefix", ""),
    delay = suppressWarnings(as.numeric(argument_value(args, "--delay-seconds", "2"))),
    limit = argument_value(args, "--limit"),
    verbose = "--verbose" %in% args
  )
  if (is.null(options$input) || is.null(options$output)) {
    stop(CLI_USAGE, call. = FALSE)
  }
  if (!is.finite(options$delay) || options$delay < 0) {
    stop("--delay-seconds must be a finite non-negative number", call. = FALSE)
  }
  if (!is.null(options$limit)) {
    limit <- suppressWarnings(as.integer(options$limit))
    if (is.na(limit) || limit <= 0 || as.character(limit) != options$limit) {
      stop("--limit must be a positive integer", call. = FALSE)
    }
    options$limit <- limit
  }
  options
}

read_cli_ids <- function(path, column) {
  files <- path
  if (dir.exists(path)) {
    files <- list.files(path, pattern = "\\.csv$", full.names = TRUE)
  }
  if (length(files) == 0) {
    stop("No CSV files found in input directory", call. = FALSE)
  }
  rows <- lapply(files, function(file) {
    input <- read_upload(file, allow_empty = TRUE)
    prepare_ids(input, column, basename(file), allow_empty = TRUE)
  })
  ids <- dplyr::bind_rows(rows)
  ids[!duplicated(ids$animal_id), , drop = FALSE]
}

print_result_summary <- function(rows, path, verbose) {
  counts <- sort(table(rows$match_status), decreasing = TRUE)
  summary <- paste(names(counts), as.integer(counts), sep = "=", collapse = ", ")
  message("Match status summary: ", summary)
  if (verbose) {
    message("Wrote ", nrow(rows), " rows to ", path)
  }
}

run_cli <- function(options, lookup = create_lookup_client(options$prefix, options$delay)) {
  results <- read_result_csv(options$output)
  failed_path <- paste0(options$output, ".failed.csv")
  failures <- read_result_csv(failed_path)
  ids <- read_cli_ids(options$input, options$id_column)
  ids <- pending_ids(ids, options$prefix, results)
  if (!is.null(options$limit)) {
    ids <- head(ids, options$limit)
  }
  if (nrow(ids) == 0) {
    if (nrow(results) == 0) {
      stop("No animal IDs found", call. = FALSE)
    }
    message("No new animal IDs to look up; output already has results.")
    return(invisible(results))
  }

  consecutive_blocks <- 0L
  for (index in seq_len(nrow(ids))) {
    message("[", index, "/", nrow(ids), "] Looking up ", ids$animal_id[[index]])
    rows <- lookup(ids$animal_id[[index]], ids$input_source[[index]])
    rows[] <- lapply(rows, as.character)
    if (rows$match_status[[1]] == "error") {
      message("Lookup failed for ", rows$searched_id[[1]], ": ", rows$error_message[[1]])
      failures <- dplyr::bind_rows(failures, rows)
      write_result_csv(failures, failed_path)
    } else {
      results <- dplyr::bind_rows(results, rows)
      # Rewriting the accumulated rows keeps the header aligned when new fields appear.
      write_result_csv(results, options$output)
    }
    consecutive_blocks <- if (is_access_block(rows)) consecutive_blocks + 1L else 0L
    if (consecutive_blocks >= 3L) {
      message("Stopping after three consecutive access blocks.")
      break
    }
    if (index < nrow(ids) && options$delay > 0) {
      Sys.sleep(options$delay + runif(1, 0, 0.5))
    }
  }
  print_result_summary(results, options$output, options$verbose)
  invisible(results)
}
