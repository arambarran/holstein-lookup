# Exercise session behavior without a browser or external HTTP requests.
app <- new.env(parent = globalenv())
source("tools/holstein_lookup/app.R", local = app, chdir = TRUE)

# Render an active batch: example data alone does not exercise progress text.
progress <- htmltools::renderTags(app$progress_panel(list(
  notice = "Lookup in progress",
  running = TRUE,
  batch_total = 2L,
  batch_done = 1L
)))$html
stopifnot(grepl("1 of 2 IDs processed in this run", progress, fixed = TRUE))
stopifnot(grepl("Stop lookup", progress, fixed = TRUE))

shiny::testServer(app$server, {
  session$setInputs(example = 1)
  stopifnot(nrow(state$rows) == 7, state$is_example, !state$running)

  session$setInputs(status = "multiple", search = "", columns = c("animal_id", "Name"))
  stopifnot(nrow(result_view$filtered()) == 2)
  session$setInputs(status = "all", search = "maple")
  stopifnot(result_view$filtered()$animal_id[[1]] == "004464")
  session$setInputs(search = "[")
  stopifnot(nrow(result_view$filtered()) == 0)
  session$setInputs(search = "timed out")
  stopifnot(result_view$filtered()$match_status[[1]] == "error")
  session$setInputs(search = "", columns = character())
  stopifnot(length(result_view$visible_columns()) == 0)

  csv <- tempfile(fileext = ".csv")
  writeLines(c("tag,notes", "004464,a", "004464,b", "2034,c"), csv)
  session$setInputs(csv = data.frame(
    name = "herd.csv", datapath = csv, size = file.info(csv)$size, type = "text/csv"
  ))
  session$setInputs(id_column = "tag", prefix = "COLLEGE")
  stopifnot(identical(prepared_ids()$animal_id, c("004464", "2034")))

  # A bad upload clears the previous input, preventing accidental reuse.
  session$setInputs(csv = data.frame(
    name = "invalid.txt", datapath = csv, size = 10, type = "text/plain"
  ))
  stopifnot(is.null(state$upload), !is.null(state$upload_error))
  unlink(csv)
})
cat("Shiny session checks passed.\n")
