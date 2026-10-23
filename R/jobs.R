# A worker publishes one complete RDS file per ID. The UI reads only new files.

result_files <- function(directory) {
  sort(list.files(directory, pattern = "^result-[0-9]+\\.rds$", full.names = TRUE))
}

save_lookup_result <- function(rows, directory, index) {
  rows[] <- lapply(rows, as.character)
  path <- file.path(directory, sprintf("result-%08d.rds", index))
  saveRDS(rows, paste0(path, ".tmp"))
  # Renaming prevents the UI from reading a partially written result.
  if (!file.rename(paste0(path, ".tmp"), path)) {
    stop("Could not save lookup progress.")
  }
}

is_access_block <- function(rows) {
  rows$match_status[[1]] == "error" && grepl(
    "cloudflare|HTTP 403|HTTP 429",
    rows$error_message[[1]],
    ignore.case = TRUE
  )
}

run_lookup_batch <- function(ids, lookup, delay, directory) {
  consecutive_blocks <- 0L
  for (index in seq_len(nrow(ids))) {
    rows <- lookup(ids$animal_id[[index]], ids$input_source[[index]])
    save_lookup_result(rows, directory, index)
    consecutive_blocks <- if (is_access_block(rows)) consecutive_blocks + 1L else 0L
    if (consecutive_blocks >= 3L) {
      return(list(reason = "blocked"))
    }
    if (index < nrow(ids) && delay > 0) {
      Sys.sleep(delay + runif(1, 0, 0.5))
    }
  }
  list(reason = "complete")
}

start_lookup_worker <- function(app_directory, ids, settings, directory) {
  callr::r_bg(
    function(app_directory, ids, settings, directory) {
      source(file.path(app_directory, "R", "lookup.R"))
      source(file.path(app_directory, "R", "jobs.R"))
      lookup <- create_lookup_client(settings$prefix, settings$delay)
      run_lookup_batch(ids, lookup, settings$delay, directory)
    },
    args = list(app_directory, ids, settings, directory),
    libpath = .libPaths(),
    supervise = TRUE,
    stdout = file.path(directory, "stdout.log"),
    stderr = file.path(directory, "stderr.log")
  )
}

create_session_job <- function(app_directory, start_worker = start_lookup_worker) {
  session_directory <- tempfile("holstein-session-")
  dir.create(session_directory)
  process <- NULL
  batch_directory <- NULL
  seen_files <- character()

  is_running <- function() {
    !is.null(process) && process$is_alive()
  }

  stop <- function() {
    if (is_running()) {
      process$kill_tree()
    }
  }

  start <- function(ids, settings) {
    batch_directory <<- tempfile("batch-", tmpdir = session_directory)
    dir.create(batch_directory)
    seen_files <<- character()
    process <<- start_worker(app_directory, ids, settings, batch_directory)
  }

  read_new <- function() {
    if (is.null(batch_directory)) {
      return(list(rows = empty_results(), completed = 0L))
    }
    files <- result_files(batch_directory)
    fresh <- setdiff(files, seen_files)
    rows <- empty_results()
    if (length(fresh) > 0) {
      rows <- dplyr::bind_rows(lapply(fresh, readRDS))
      seen_files <<- files
    }
    list(rows = rows, completed = length(files))
  }

  close <- function() {
    stop()
    unlink(session_directory, recursive = TRUE)
  }

  list(
    start = start,
    stop = stop,
    is_running = is_running,
    read_new = read_new,
    outcome = function() tryCatch(process$get_result(), error = identity),
    close = close
  )
}
