#!/usr/bin/env Rscript

required_packages <- c("jsonlite", "httr2", "readr", "dplyr", "purrr", "tibble")
endpoint <- "https://www.holstein.ca/en/AIS/ReadAnimalSearchGrid"
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

input_path <- get_arg("--input")
output_path <- get_arg("--output")
id_column <- get_arg("--id-column", "animal_id")
search_prefix <- get_arg("--search-prefix", "")
limit <- get_arg("--limit")
delay_seconds <- as.numeric(get_arg("--delay-seconds", "2"))
verbose <- "--verbose" %in% args

if (is.null(input_path) || is.null(output_path)) {
  stop(usage, call. = FALSE)
}

check_required_package <- function(package) {
  if (requireNamespace(package, quietly = TRUE)) {
    return(invisible(TRUE))
  }

  stop(
    sprintf("Install %s first: install.packages('%s')", package, package),
    call. = FALSE
  )
}

invisible(lapply(required_packages, check_required_package))

add_request_headers <- function(request) {
  do.call(
    httr2::req_headers,
    c(list(request), as.list(request_headers))
  )
}

read_response_body <- function(search_string) {
  response <- httr2::request(endpoint) |>
    httr2::req_url_query(animalSearchString = search_string) |>
    add_request_headers() |>
    httr2::req_timeout(60) |>
    httr2::req_error(is_error = function(response) {
      FALSE
    }) |>
    httr2::req_perform()

  httr2::resp_body_string(response)
}

response_error_message <- function(body) {
  if (is.na(body)) {
    return("Request failed")
  }

  body_lower <- tolower(body)
  if (grepl("cloudflare|just a moment|cf-mitigated", body_lower)) {
    return("Request was blocked by Cloudflare")
  }

  "Request failed or response was not JSON"
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

files <- input_files(input_path)
if (length(files) == 0) {
  stop("No CSV files found in input directory", call. = FALSE)
}

ids <- purrr::map_dfr(files, read_ids)
ids <- dplyr::filter(ids, !is.na(.data$animal_id), .data$animal_id != "")
ids <- dplyr::distinct(ids, .data$animal_id, .keep_all = TRUE)

if (nrow(ids) == 0) {
  stop("No animal IDs found", call. = FALSE)
}

if (!is.null(limit)) {
  ids <- head(ids, as.integer(limit))
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
      request_url = request_url
    )
  }

  if (verbose) {
    message("Looking up ", search_string)
  }

  body <- tryCatch(
    suppressWarnings(
      read_response_body(search_string)
    ),
    error = function(error) {
      NA_character_
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
    error = function(error) {
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

  dplyr::bind_cols(
    output_row(match_count, match_status),
    tibble::as_tibble(matches)
  )
}

lookup_with_delay <- function(animal_id, input_source, index) {
  row <- lookup_one(animal_id, input_source)
  if (index < nrow(ids) && delay_seconds > 0) {
    Sys.sleep(delay_seconds)
  }

  row
}

rows <- purrr::pmap(
  list(ids$animal_id, ids$input_source, seq_len(nrow(ids))),
  lookup_with_delay
)
result <- dplyr::bind_rows(rows)
dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(result, output_path, na = "")

if (verbose) {
  message("Wrote ", nrow(result), " rows to ", output_path)
}
