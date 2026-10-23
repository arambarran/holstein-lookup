# Holstein HTTP requests and response parsing, shared by the CLI and app.
# The client receives its settings and transport explicitly for isolated tests.

HOLSTEIN_SEARCH_URL <- "https://www.holstein.ca/en/AIS/ReadAnimalSearchGrid"

# Capture the module path while sourcing, before CLI callers change directory.
LOOKUP_MODULE_DIRECTORY <- local({
  sources <- Filter(function(frame) !is.null(frame$ofile), sys.frames())
  source_file <- tail(sources, 1)[[1]]$ofile
  file.path(dirname(normalizePath(source_file)), "python")
})

create_http_client <- function(directory) {
  tryCatch({
    module <- reticulate::import_from_path("holstein_http", path = directory)
    module$LookupHTTPClient()
  }, error = function(error) {
    stop(paste(
      "Could not initialize the lookup transport. Install Python 3.10+ and",
      "requirements.txt, then select that environment with RETICULATE_PYTHON.",
      conditionMessage(error)
    ), call. = FALSE)
  })
}

stop_lookup_error <- function(message, retryable = FALSE) {
  stop(structure(
    list(message = message, call = NULL, retryable = retryable),
    class = c("lookup_transport_error", "error", "condition")
  ))
}

response_body <- function(response) {
  if (!is.null(response$error)) {
    stop_lookup_error(paste("Network request failed:", response$error), response$retryable)
  }
  if (isTRUE(response$challenge) || response$status != 200L) {
    message <- sprintf("HTTP %s from Holstein lookup", response$status)
    if (isTRUE(response$challenge)) {
      message <- paste("Cloudflare challenge:", message)
    }
    if (nzchar(response$ray_id)) {
      message <- paste0(message, " [Ray ID: ", response$ray_id, "]")
    }
    if (nzchar(response$retry_after)) {
      message <- paste0(message, " [Retry-After: ", response$retry_after, "]")
    }
    retryable <- !isTRUE(response$challenge) && response$status %in% c(408L, 500L, 502L, 503L, 504L)
    stop_lookup_error(message, retryable)
  }
  response$body
}

create_response_reader <- function(
  module_directory = LOOKUP_MODULE_DIRECTORY, client_factory = create_http_client
) {
  force(module_directory)
  force(client_factory)
  client <- NULL
  function(request_url) {
    if (is.null(client)) {
      client <<- client_factory(module_directory)
    }
    response_body(client$fetch(request_url))
  }
}

read_response_body_with_retry <- function(request_url, read_response, tries = 3L, sleep = Sys.sleep) {
  for (attempt in seq_len(tries)) {
    result <- tryCatch(read_response(request_url), error = identity)
    if (!inherits(result, "error")) {
      return(result)
    }
    if (!isTRUE(result$retryable)) {
      stop(result)
    }

    if (attempt < tries) {
      # Short pauses avoid failing the whole batch because of one temporary
      # network hiccup or a slow response from the Holstein site.
      sleep(2 ^ attempt)
    }
  }

  stop(result)
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
  rows <- as.data.frame(parsed$Data, stringsAsFactors = FALSE)
  if ("Colour" %in% names(rows)) {
    colours <- c("B&W" = "Black & white", "R&W" = "Red & white")
    known <- rows$Colour %in% names(colours)
    rows$Colour[known] <- unname(colours[rows$Colour[known]])
  }
  rows
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
  prefix = "", delay = 2, read_response = NULL
) {
  force(prefix)
  force(delay)
  if (is.null(read_response)) {
    reader <- create_response_reader()
    read_response <- function(url) read_response_body_with_retry(url, reader)
  }
  force(read_response)
  function(animal_id, input_source) {
    lookup_one(animal_id, input_source, prefix, delay, read_response)
  }
}
