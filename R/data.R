# CSV input and result transformations. These functions do not depend on Shiny.

MATCH_LABELS <- c(
  unique = "Unique matches",
  multiple = "Multiple matches",
  not_found = "Not found",
  error = "Errors"
)

read_upload <- function(path, allow_empty = FALSE, has_header = TRUE) {
  rows <- readr::read_csv(
    path,
    col_names = has_header,
    col_types = readr::cols(.default = readr::col_character()),
    name_repair = "check_unique",
    show_col_types = FALSE,
    progress = FALSE,
    na = ""
  )
  if (ncol(rows) == 0 || (nrow(rows) == 0 && !allow_empty)) {
    stop("The CSV needs at least one data row.", call. = FALSE)
  }
  if (nrow(readr::problems(rows)) > 0) {
    stop("The CSV has inconsistent rows. Check its separators and quotes.", call. = FALSE)
  }
  rows
}

prepare_ids <- function(rows, column, filename, allow_empty = FALSE) {
  if (is.null(column) || !column %in% names(rows)) {
    stop("Choose the column containing your animal IDs.", call. = FALSE)
  }
  ids <- trimws(rows[[column]])
  ids <- unique(ids[!is.na(ids) & nzchar(ids)])
  if (length(ids) == 0 && !allow_empty) {
    stop("The selected column has no animal IDs.", call. = FALSE)
  }
  data.frame(
    animal_id = ids,
    input_source = rep(filename, length(ids)),
    stringsAsFactors = FALSE
  )
}

normalize_prefix <- function(prefix) {
  prefix <- trimws(prefix)
  if (!nzchar(prefix)) {
    return("")
  }
  paste0(prefix, " ")
}

lookup_settings <- function(ids, prefix, delay, limit, filename) {
  if (length(delay) != 1 || !is.finite(delay) || delay < 0) {
    stop("Request delay must be a finite number of zero or more seconds.")
  }
  if (length(limit) != 1 || !is.finite(limit) || limit < 0 || limit != floor(limit)) {
    stop("The ID limit must be a whole number of zero or more.")
  }
  if (limit > 0) {
    ids <- head(ids, limit)
  }
  list(
    ids = ids,
    prefix = normalize_prefix(prefix),
    delay = delay,
    filename = filename
  )
}

empty_results <- function() {
  data.frame(
    animal_id = character(),
    searched_id = character(),
    input_source = character(),
    match_count = character(),
    match_status = character(),
    error_message = character(),
    request_url = character(),
    birth_codes = character(),
    genotyping_code = character()
  )
}

merge_results <- function(existing, incoming) {
  if (nrow(incoming) == 0) {
    return(existing)
  }
  # Replace all rows for an ID together, including all of its multiple matches.
  keep <- !existing$searched_id %in% incoming$searched_id
  dplyr::bind_rows(existing[keep, , drop = FALSE], incoming)
}

pending_ids <- function(ids, prefix, results) {
  searched_ids <- paste0(prefix, ids$animal_id)
  ids[!searched_ids %in% results$searched_id, , drop = FALSE]
}

failed_ids <- function(settings, results) {
  failed <- results$searched_id[results$match_status == "error"]
  searched_ids <- paste0(settings$prefix, settings$ids$animal_id)
  settings$ids[searched_ids %in% failed, , drop = FALSE]
}

status_counts <- function(results) {
  ids <- results[!duplicated(results$searched_id), , drop = FALSE]
  table(factor(ids$match_status, levels = names(MATCH_LABELS)))
}

filter_results <- function(rows, status = "all", query = "") {
  if (!is.null(status) && status != "all") {
    rows <- rows[rows$match_status == status, , drop = FALSE]
  }
  if (is.null(query) || !nzchar(trimws(query)) || nrow(rows) == 0) {
    return(rows)
  }
  query <- tolower(trimws(query))
  matches <- lapply(rows, function(column) {
    !is.na(column) & grepl(query, tolower(column), fixed = TRUE)
  })
  rows[Reduce(`|`, matches), , drop = FALSE]
}

export_view <- function(rows, columns, sorted = NULL) {
  columns <- intersect(columns, names(rows))
  sort_columns <- intersect(names(sorted), names(rows))
  if (length(sort_columns) > 0 && nrow(rows) > 0) {
    keys <- lapply(sort_columns, function(column) {
      key <- xtfrm(rows[[column]])
      if (sorted[[column]] == "desc") -key else key
    })
    row_order <- do.call(order, c(keys, list(na.last = TRUE)))
    rows <- rows[row_order, , drop = FALSE]
  }
  rows[, columns, drop = FALSE]
}

read_result_csv <- function(path) {
  if (!file.exists(path) || file.info(path)$size == 0) {
    return(empty_results())
  }
  rows <- readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE,
    na = ""
  )
  required <- c("searched_id", "birth_codes", "genotyping_code")
  if (!all(required %in% names(rows))) {
    stop("Existing output is missing required columns; use a new output path.")
  }
  rows
}

write_result_csv <- function(rows, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(".holstein-results-", tmpdir = dirname(path))
  on.exit(unlink(temporary), add = TRUE)
  readr::write_csv(rows, temporary, na = "")
  if (!file.rename(temporary, path)) {
    stop("Could not save results to ", path, call. = FALSE)
  }
}
