#!/usr/bin/env Rscript

required_packages <- c(
  "jsonlite",
  "readr",
  "dplyr",
  "tibble",
  "xml2"
)
endpoint <- "https://www.holstein.ca/en/AIS/ReadAnimalSearchGrid"
curl_path <- Sys.which("curl")
cloudflare_block_limit <- 3L
# Holstein's lookup endpoint is meant for its website, so these headers make
# our request look like the same browser request the website normally sends.
request_headers <- c(
  "User-Agent" = paste(
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
    "AppleWebKit/537.36 (KHTML, like Gecko)",
    "Chrome/131.0.0.0 Safari/537.36"
  ),
  "Accept" = "application/json, text/javascript, */*; q=0.01",
  "Accept-Language" = "en-US,en;q=0.9",
  "Referer" = "https://www.holstein.ca/",
  "X-Requested-With" = "XMLHttpRequest"
)

args <- commandArgs(trailingOnly = TRUE)
usage <- paste(
  "Usage: Rscript tools/holstein_lookup/holstein_lookup.R",
  "--input <csv-file-or-directory>",
  "--output <output-csv>",
  "[--id-column animal_id]",
  "[--search-prefix 'COLLEGE ']",
  "[--limit N]",
  "[--delay-seconds 2]",
  "[--verbose]"
)

get_arg <- function(name, default = NULL) {
  index <- match(name, args)
  if (is.na(index) || index == length(args)) {
    return(default)
  }
  args[[index + 1]]
}

parse_non_negative_number <- function(value, name) {
  parsed <- suppressWarnings(as.numeric(value))
  if (is.na(parsed) || parsed < 0) {
    stop(sprintf("%s must be a non-negative number", name), call. = FALSE)
  }

  parsed
}

parse_positive_integer <- function(value, name) {
  parsed <- suppressWarnings(as.integer(value))
  if (is.na(parsed) || parsed <= 0 || as.character(parsed) != value) {
    stop(sprintf("%s must be a positive integer", name), call. = FALSE)
  }

  parsed
}

input_path <- get_arg("--input")
output_path <- get_arg("--output")
id_column <- get_arg("--id-column", "animal_id")
search_prefix <- get_arg("--search-prefix", "")
limit <- get_arg("--limit")
if (!is.null(limit)) {
  limit <- parse_positive_integer(limit, "--limit")
}
delay_seconds <- parse_non_negative_number(
  get_arg("--delay-seconds", "2"),
  "--delay-seconds"
)
verbose <- "--verbose" %in% args

if (is.null(input_path) || is.null(output_path)) {
  stop(usage, call. = FALSE)
}

# Failed lookups are kept separate so a partial run can still leave a clean
# results file for the IDs that did return usable matches.
failed_output_path <- paste0(output_path, ".failed.csv")

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0) {
  stop(
    sprintf(
      "Install required packages first: install.packages(c(%s))",
      paste(sprintf('"%s"', missing_packages), collapse = ", ")
    ),
    call. = FALSE
  )
}

if (!nzchar(curl_path)) {
  stop("curl is required and was not found on PATH", call. = FALSE)
}

read_response_body <- function(request_url) {
  # curl gives us better control than R's built-in download helpers here,
  # especially for sending the same headers the Holstein website uses.
  stderr_path <- tempfile("holstein-curl-stderr-")
  on.exit(unlink(stderr_path), add = TRUE)

  curl_headers <- paste(names(request_headers), request_headers, sep = ": ")
  curl_args <- c(
    "-sS",
    "-L",
    "--max-time",
    "60",
    as.vector(rbind("-H", curl_headers)),
    "-w",
    "\n%{http_code}",
    request_url
  )

  stdout <- system2(
    curl_path[[1]],
    shQuote(curl_args),
    stdout = TRUE,
    stderr = stderr_path
  )
  body <- paste(stdout, collapse = "\n")
  http_code <- NA_character_
  # curl appends the HTTP status to the response so we can catch blocked or
  # missing pages before trying to parse them as lookup data.
  if (grepl("\n[0-9]{3}$", body)) {
    http_code <- sub(".*\n([0-9]{3})$", "\\1", body)
    body <- sub("\n[0-9]{3}$", "", body)
  }

  exit_status <- attr(stdout, "status")
  if (is.null(exit_status)) {
    exit_status <- 0L
  }

  stderr <- trimws(paste(readLines(stderr_path, warn = FALSE), collapse = "\n"))
  if (exit_status != 0L) {
    message <- sprintf("curl failed with exit status %s", exit_status)
    if (nzchar(stderr)) {
      message <- paste(message, stderr, sep = ": ")
    }
    stop(message, call. = FALSE)
  }

  if (!is.na(http_code) && http_code != "200") {
    stop(sprintf("HTTP %s from Holstein lookup", http_code), call. = FALSE)
  }

  body
}

read_response_body_with_retry <- function(request_url, tries = 3L) {
  for (attempt in seq_len(tries)) {
    result <- tryCatch(read_response_body(request_url), error = identity)
    if (!inherits(result, "error")) {
      return(result)
    }

    if (attempt < tries) {
      # Short pauses avoid failing the whole batch because of one temporary
      # network hiccup or a slow response from the Holstein site.
      Sys.sleep(2 ^ attempt)
    }
  }

  stop(conditionMessage(result), call. = FALSE)
}

response_error_message <- function(body) {
  if (is.na(body)) {
    message <- attr(body, "error_message", exact = TRUE)
    if (!is.null(message)) {
      return(message)
    }

    return("Request failed")
  }

  body_lower <- tolower(body)
  # Cloudflare returns an HTML challenge page instead of animal data when it
  # blocks us, so we flag that separately from normal lookup failures.
  if (grepl("cloudflare|just a moment|cf-mitigated", body_lower)) {
    return("Request was blocked by Cloudflare")
  }

  "Request failed or response was not JSON"
}

lookup_animal_codes <- function(animal) {
  id_column <- match("animalid", tolower(names(animal)))
  if (is.na(id_column) || is.na(animal[[id_column]][[1]])) {
    stop("Search result is missing AnimalId", call. = FALSE)
  }
  detail_url <- paste0(
    "https://www.holstein.ca/en/AIS/AIS?animalId=", animal[[id_column]][[1]]
  )
  if (delay_seconds > 0) Sys.sleep(delay_seconds)
  document <- xml2::read_html(read_response_body_with_retry(detail_url))
  nodes <- xml2::xml_find_all(
    document, "//body//text()[not(ancestor::script) and not(ancestor::style)]"
  )
  text <- gsub("[[:space:]\u00a0]+", " ", paste(xml2::xml_text(nodes), collapse = " "))
  # Exclude the animal's name and its relatives' codes.
  header <- regmatches(text, regexpr(
    "Registration Status\\s*:.*?(?=\\b(?:Sire|Dam)\\s*:)", text, perl = TRUE
  ))
  if (length(header) == 0) {
    stop("Animal detail header was not found", call. = FALSE)
  }
  tokens <- strsplit(header, " ")[[1]]
  birth <- unique(tokens[tokens %in% c("ET", "ETA", "ETM", "IVF", "MB")])
  genotyping <- unique(tokens[tokens %in% c("GT", "GTM", "GTS", "GTSM")])
  list(
    birth_codes = paste(birth, collapse = " "),
    genotyping_code = paste(genotyping, collapse = " ")
  )
}

input_files <- function(path) {
  if (dir.exists(path)) {
    return(list.files(path, pattern = "\\.csv$", full.names = TRUE))
  }

  path
}

read_ids <- function(path) {
  data <- readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  )

  if (!id_column %in% names(data)) {
    stop(sprintf("Column '%s' not found in %s", id_column, path), call. = FALSE)
  }

  tibble::tibble(
    animal_id = trimws(data[[id_column]]),
    input_source = basename(path)
  )
}

read_existing_results <- function(path) {
  if (!file.exists(path) || file.info(path)$size == 0) {
    return(tibble::tibble())
  }

  readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  )
}

validate_existing_results <- function(results) {
  if (ncol(results) == 0) {
    return(results)
  }

  if (!all(c("searched_id", "birth_codes", "genotyping_code") %in% names(results))) {
    stop(
      "Existing output is missing required columns; use a new output path.",
      call. = FALSE
    )
  }

  results
}

write_result <- function(row, path, append) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(row, path, na = "", append = append)
}

files <- input_files(input_path)
if (length(files) == 0) {
  stop("No CSV files found in input directory", call. = FALSE)
}

existing_results <- validate_existing_results(
  read_existing_results(output_path)
)
# These flags decide whether write_csv should add a header row. They start from
# the files already on disk so rerunning the script appends cleanly.
append_results <- nrow(existing_results) > 0
append_failed_results <- file.exists(failed_output_path) &&
  file.info(failed_output_path)$size > 0
ids <- dplyr::bind_rows(lapply(files, read_ids)) |>
  dplyr::filter(!is.na(.data$animal_id), .data$animal_id != "") |>
  dplyr::distinct(.data$animal_id, .keep_all = TRUE)

if (nrow(existing_results) > 0) {
  # Skip IDs already present in the output so interrupted runs can be resumed
  # without asking Holstein for the same animal again.
  searched_ids <- paste0(search_prefix, ids$animal_id)
  ids <- dplyr::filter(ids, !searched_ids %in% existing_results$searched_id)
}

if (nrow(ids) == 0) {
  if (nrow(existing_results) > 0) {
    message("No new animal IDs to look up; output already has results.")
    quit(save = "no", status = 0)
  }

  stop("No animal IDs found", call. = FALSE)
}

if (!is.null(limit)) {
  ids <- head(ids, limit)
}

lookup_one <- function(animal_id, input_source) {
  search_string <- paste0(search_prefix, animal_id)
  request_url <- paste0(
    endpoint,
    "?animalSearchString=",
    utils::URLencode(search_string, reserved = TRUE)
  )

  output_row <- function(match_count, match_status, error_message = "") {
    tibble::tibble(
      animal_id = animal_id,
      searched_id = search_string,
      input_source = input_source,
      match_count = match_count,
      match_status = match_status,
      error_message = error_message,
      request_url = request_url,
      birth_codes = "",
      genotyping_code = ""
    )
  }

  body <- tryCatch(
    read_response_body_with_retry(request_url),
    error = function(error) {
      # Keep the failure message in the same row shape as successful lookups so
      # the main loop can write every outcome consistently.
      body <- NA_character_
      attr(body, "error_message") <- conditionMessage(error)
      body
    }
  )

  if (is.na(body) || !startsWith(trimws(body), "{")) {
    return(output_row(
      0,
      "error",
      response_error_message(body)
    ))
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(body, flatten = TRUE),
    error = function(...) {
      NULL
    }
  )

  if (is.null(parsed)) {
    return(output_row(
      0,
      "error",
      "Response JSON could not be parsed"
    ))
  }

  matches <- parsed$Data
  if (is.null(matches) || length(matches) == 0) {
    return(output_row(0, "not_found"))
  }

  if (!is.data.frame(matches)) {
    matches <- as.data.frame(matches, stringsAsFactors = FALSE)
  }

  match_count <- nrow(matches)
  match_status <- if (match_count == 1) "unique" else "multiple"

  rows <- dplyr::bind_cols(
    output_row(match_count, match_status),
    tibble::as_tibble(matches)
  )
  tryCatch({
    for (index in seq_len(match_count)) {
      codes <- lookup_animal_codes(matches[index, , drop = FALSE])
      rows[index, names(codes)] <- codes
    }
    rows
  }, error = function(error) {
    output_row(match_count, "error", conditionMessage(error))
  })
}

consecutive_cloudflare_blocks <- 0L
total_ids <- nrow(ids)

for (index in seq_len(total_ids)) {
  message("[", index, "/", total_ids, "] Looking up ", ids$animal_id[[index]])
  row <- lookup_one(ids$animal_id[[index]], ids$input_source[[index]])
  row <- dplyr::mutate(row, dplyr::across(dplyr::everything(), as.character))

  lookup_failed <- identical(row$match_status[[1]], "error")
  cloudflare_blocked <- lookup_failed &&
    grepl("cloudflare", row$error_message[[1]], ignore.case = TRUE)

  if (lookup_failed) {
    message(
      "Lookup failed for ",
      row$searched_id[[1]],
      ": ",
      row$error_message[[1]]
    )
    write_result(row, failed_output_path, append_failed_results)
    append_failed_results <- TRUE
  } else {
    write_result(row, output_path, append_results)
    append_results <- TRUE
  }

  consecutive_cloudflare_blocks <- if (cloudflare_blocked) {
    consecutive_cloudflare_blocks + 1L
  } else {
    # One successful lookup or non-Cloudflare error means the site is not
    # continuously blocking us, so reset the safety counter.
    0L
  }

  if (consecutive_cloudflare_blocks >= cloudflare_block_limit) {
    # Repeated Cloudflare blocks usually mean continuing will only generate more
    # failures, so stop and let the existing partial results stay saved.
    message(
      "Stopping after ",
      consecutive_cloudflare_blocks,
      " consecutive Cloudflare blocks."
    )
    break
  }

  if (index < total_ids && delay_seconds > 0) {
    # A small random delay is friendlier to the Holstein site and avoids sending
    # every request on an exact, machine-like schedule.
    Sys.sleep(delay_seconds + runif(1, 0, 0.5))
  }
}

results <- validate_existing_results(read_existing_results(output_path))
match_status_counts <- sort(
  table(results$match_status),
  decreasing = TRUE
)
message(
  "Match status summary: ",
  paste(
    names(match_status_counts),
    as.integer(match_status_counts),
    sep = "=",
    collapse = ", "
  )
)

if (verbose) {
  message("Wrote ", nrow(results), " rows to ", output_path)
}
