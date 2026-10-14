# Use a real background process with a local lookup fixture, never Holstein.
app <- new.env(parent = globalenv())
source("tools/holstein_lookup/app.R", local = app, chdir = TRUE)
fixture <- tempfile("holstein-worker-fixture-")
dir.create(file.path(fixture, "R"), recursive = TRUE)
file.copy("tools/holstein_lookup/R/jobs.R", file.path(fixture, "R", "jobs.R"))
marker <- file.path(fixture, "retried")
writeLines(c(
  paste0("marker <- ", deparse(marker)),
  'create_lookup_client <- function(prefix, delay) {',
  '  force(prefix)',
  '  function(animal_id, input_source) {',
  '    Sys.sleep(0.4)',
  '    failed <- animal_id == "retry" && !file.exists(marker)',
  '    if (failed) file.create(marker)',
  '    data.frame(',
  '      animal_id = animal_id, searched_id = paste0(prefix, animal_id),',
  '      input_source = input_source,',
  '      match_status = if (failed) "error" else "unique",',
  '      error_message = if (failed) "Temporary failure" else ""',
  '    )',
  '  }',
  '}'
), file.path(fixture, "R", "lookup.R"))
fixture_server <- app$create_lookup_server(fixture)

shiny::testServer(fixture_server, {
  ids <- data.frame(
    animal_id = c("001", "002", "003", "004", "retry"),
    input_source = "fixture.csv"
  )
  settings <- list(ids = ids, prefix = "COLLEGE ", delay = 0, filename = "fixture.csv")
  state$settings <- settings
  start_batch(ids, settings)
  deadline <- Sys.time() + 25
  while (state$batch_done == 0L && state$running && Sys.time() < deadline) {
    Sys.sleep(0.1)
    session$elapse(500)
  }
  stopifnot(state$running, state$batch_done > 0L)
  session$setInputs(stop = 1)
  stopifnot(!state$running, nrow(state$rows) > 0, nrow(state$rows) < nrow(ids))

  session$setInputs(resume = 1)
  while (state$running && Sys.time() < deadline) {
    Sys.sleep(0.1)
    session$elapse(500)
  }
  stopifnot(!state$running, nrow(state$rows) == nrow(ids))
  stopifnot(sum(state$rows$match_status == "error") == 1)

  session$setInputs(retry = 1)
  while (state$running && Sys.time() < deadline) {
    Sys.sleep(0.1)
    session$elapse(500)
  }
  stopifnot(!state$running, all(state$rows$match_status == "unique"))
  stopifnot(nrow(state$rows) == 5, length(unique(state$rows$searched_id)) == 5)
})
unlink(fixture, recursive = TRUE)
cat("Background stop, resume, and retry checks passed.\n")
