# Holstein HTTP requests and response parsing, shared by the CLI and app.
# The client receives its settings and transport explicitly for isolated tests.

HOLSTEIN_SEARCH_URL <- "https://www.holstein.ca/en/AIS/ReadAnimalSearchGrid"

HOLSTEIN_HEADERS <- c(
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

read_response_body <- function(request_url) {
  # curl gives us better control than R's built-in download helpers here,
  # especially for sending the same headers the Holstein website uses.
  stderr_path <- tempfile("holstein-curl-stderr-")
  on.exit(unlink(stderr_path), add = TRUE)

  curl_headers <- paste(names(HOLSTEIN_HEADERS), HOLSTEIN_HEADERS, sep = ": ")
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
    Sys.which("curl")[[1]],
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

parse_search_response <- function(body) {
  if (grepl("cloudflare|just a moment|cf-mitigated", tolower(body))) {
    stop("Request was blocked by Cloudflare", call. = FALSE)
  }
  if (!startsWith(trimws(body), "{")) {
    stop("Request failed or response was not JSON", call. = FALSE)
  }
  parsed <- tryCatch(jsonlite::fromJSON(body, flatten = TRUE), error = function(error) NULL)
  if (is.null(parsed)) {
    stop("Response JSON could not be parsed", call. = FALSE)
  }
  if (is.null(parsed$Data) || length(parsed$Data) == 0) {
    return(data.frame())
  }
  as.data.frame(parsed$Data, stringsAsFactors = FALSE)
}

parse_animal_codes <- function(html) {
  document <- xml2::read_html(html)
  nodes <- xml2::xml_find_all(
    document, "//body//text()[not(ancestor::script) and not(ancestor::style)]"
  )
  text <- paste(xml2::xml_text(nodes), collapse = " ")
  text <- gsub("[[:space:]\u00a0]+", " ", text)
  # Only the animal's registration header counts, never a parent's codes.
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

lookup_animal_codes <- function(animal, delay, read_response) {
  id_column <- match("animalid", tolower(names(animal)))
  if (is.na(id_column) || is.na(animal[[id_column]][[1]])) {
    stop("Search result is missing AnimalId", call. = FALSE)
  }
  url <- paste0("https://www.holstein.ca/en/AIS/AIS?animalId=", animal[[id_column]][[1]])
  if (delay > 0) {
    Sys.sleep(delay)
  }
  parse_animal_codes(read_response(url))
}

lookup_metadata <- function(animal_id, input_source, prefix) {
  searched_id <- paste0(prefix, animal_id)
  url <- paste0(
    HOLSTEIN_SEARCH_URL,
    "?animalSearchString=",
    utils::URLencode(searched_id, reserved = TRUE)
  )
  tibble::tibble(
    animal_id = animal_id,
    searched_id = searched_id,
    input_source = input_source,
    match_count = 0L,
    match_status = "not_found",
    error_message = "",
    request_url = url,
    birth_codes = "",
    genotyping_code = ""
  )
}

lookup_one <- function(animal_id, input_source, prefix, delay, read_response) {
  metadata <- lookup_metadata(animal_id, input_source, prefix)
  tryCatch({
    matches <- parse_search_response(read_response(metadata$request_url))
    metadata$match_count <- nrow(matches)
    if (nrow(matches) == 0) {
      return(metadata)
    }
    metadata$match_status <- if (nrow(matches) == 1) "unique" else "multiple"
    rows <- dplyr::bind_cols(metadata, tibble::as_tibble(matches))
    for (index in seq_len(nrow(matches))) {
      codes <- lookup_animal_codes(matches[index, , drop = FALSE], delay, read_response)
      rows[index, names(codes)] <- codes
    }
    rows
  }, error = function(error) {
    metadata$match_status <- "error"
    metadata$error_message <- conditionMessage(error)
    metadata
  })
}

create_lookup_client <- function(
  prefix = "", delay = 2, read_response = read_response_body_with_retry
) {
  force(prefix)
  force(delay)
  force(read_response)
  function(animal_id, input_source) {
    lookup_one(animal_id, input_source, prefix, delay, read_response)
  }
}
