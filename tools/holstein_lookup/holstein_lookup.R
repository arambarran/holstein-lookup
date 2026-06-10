#!/usr/bin/env Rscript

required_packages <- c("jsonlite")
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
curl_path <- Sys.which("curl")

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

read_response_body <- function(request_url) {
  if (nzchar(curl_path)) {
    curl_headers <- paste(names(request_headers), request_headers, sep = ": ")
    curl_args <- c(
      "-sS",
      "-L",
      "--max-time",
      "60",
      as.vector(rbind("-H", curl_headers)),
      request_url
    )

    return(paste(
      system2(curl_path[[1]], shQuote(curl_args), stdout = TRUE, stderr = TRUE),
      collapse = "\n"
    ))
  }

  connection <- url(request_url, headers = request_headers)
  on.exit(close(connection), add = TRUE)

  paste(
    readLines(connection, warn = FALSE),
    collapse = "\n"
  )
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

input_files <- if (dir.exists(input_path)) {
  list.files(input_path, pattern = "\\.csv$", full.names = TRUE)
} else {
  input_path
}

if (length(input_files) == 0) {
  stop("No CSV files found in input directory", call. = FALSE)
}

read_ids <- function(path) {
  data <- read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  if (!id_column %in% names(data)) {
    stop(sprintf("Column '%s' not found in %s", id_column, path), call. = FALSE)
  }

  data.frame(
    animal_id = trimws(data[[id_column]]),
    input_source = basename(path),
    stringsAsFactors = FALSE
  )
}

ids <- do.call(rbind, lapply(input_files, read_ids))
ids <- ids[ids$animal_id != "" & !is.na(ids$animal_id), ]
ids <- ids[!duplicated(ids$animal_id), ]

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
    data.frame(
      animal_id = animal_id,
      searched_id = search_string,
      input_source = input_source,
      match_count = match_count,
      match_status = match_status,
      error_message = error_message,
      request_url = request_url,
      stringsAsFactors = FALSE
    )
  }

  if (verbose) {
    message("Looking up ", search_string)
  }

  body <- tryCatch(
    suppressWarnings(
      read_response_body(request_url)
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

  cbind(output_row(match_count, match_status), matches)
}

rows <- vector("list", nrow(ids))
for (i in seq_len(nrow(ids))) {
  rows[[i]] <- lookup_one(ids$animal_id[[i]], ids$input_source[[i]])
  if (i < nrow(ids) && delay_seconds > 0) {
    Sys.sleep(delay_seconds)
  }
}

all_columns <- unique(unlist(lapply(rows, names)))
rows <- lapply(rows, function(row) {
  missing_columns <- setdiff(all_columns, names(row))
  for (column in missing_columns) {
    row[[column]] <- NA
  }
  row[all_columns]
})

result <- do.call(rbind, rows)
dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write.csv(result, output_path, row.names = FALSE, na = "")

if (verbose) {
  message("Wrote ", nrow(result), " rows to ", output_path)
}
