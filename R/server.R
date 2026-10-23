# Session orchestration: upload, start, poll, stop, resume, and retry.
# Each session owns its state and worker. Layout and rendering live elsewhere.

create_lookup_server <- function(app_directory, start_worker = start_lookup_worker) {
  force(app_directory)
  force(start_worker)

  function(input, output, session) {
    state <- reactiveValues(
      upload = NULL,
      upload_error = NULL,
      rows = empty_results(),
      settings = NULL,
      running = FALSE,
      is_example = FALSE,
      notice = NULL,
      batch_total = 0L,
      batch_done = 0L,
      dataset_id = 0L
    )
    job <- create_session_job(app_directory, start_worker)
    session$onSessionEnded(job$close)

    prepared_ids <- reactive({
      req(state$upload)
      prepare_ids(state$upload, input$id_column, input$csv$name)
    })

    can_run <- reactive({
      if (state$running || is.null(state$upload)) {
        return(FALSE)
      }
      tryCatch(nrow(prepared_ids()) > 0, error = function(error) FALSE)
    })

    collect_completed <- function() {
      snapshot <- job$read_new()
      if (nrow(snapshot$rows) > 0) {
        state$rows <- merge_results(isolate(state$rows), snapshot$rows)
      }
      state$batch_done <- snapshot$completed
    }

    start_batch <- function(ids, settings) {
      if (state$running || nrow(ids) == 0) {
        return(invisible(NULL))
      }
      state$batch_total <- nrow(ids)
      state$batch_done <- 0L
      tryCatch({
        job$start(ids, settings)
        state$running <- TRUE
        state$notice <- "Lookup in progress"
      }, error = function(error) {
        state$notice <- paste("Could not start the lookup:", conditionMessage(error))
      })
    }

    observe({
      session$sendCustomMessage("lookupBusy", list(
        busy = state$running, canRun = can_run(), hasUpload = !is.null(state$upload)
      ))
    })

    observeEvent(input$csv, {
      if (state$running) {
        return()
      }
      state$upload <- NULL
      state$upload_error <- NULL
      updateSelectInput(session, "id_column", choices = character())
      tryCatch({
        if (!grepl("\\.csv$", input$csv$name, ignore.case = TRUE)) {
          stop("Please choose a .csv file.")
        }
        rows <- read_upload(input$csv$datapath)
        state$upload <- rows
        preferred <- if ("animal_id" %in% names(rows)) "animal_id" else names(rows)[[1]]
        updateSelectInput(session, "id_column", choices = names(rows), selected = preferred)
      }, error = function(error) {
        state$upload_error <- conditionMessage(error)
      })
    })

    observeEvent(input$run, {
      if (state$running) {
        return()
      }
      tryCatch({
        if (is.null(state$upload)) {
          stop("Upload a CSV to start a lookup.")
        }
        settings <- lookup_settings(
          prepared_ids(), input$prefix, input$delay, input$limit, input$csv$name
        )
        state$settings <- settings
        state$rows <- empty_results()
        state$dataset_id <- state$dataset_id + 1L
        state$is_example <- FALSE
        start_batch(settings$ids, settings)
      }, error = function(error) {
        showNotification(conditionMessage(error), type = "error", duration = 8)
      })
    })

    observe({
      if (!state$running) {
        return()
      }
      invalidateLater(500, session)
      collect_completed()
      if (!job$is_running()) {
        # One final read closes the race between the last snapshot and worker exit.
        collect_completed()
        state$running <- FALSE
        state$notice <- completion_message(job$outcome())
      }
    })

    observeEvent(input$stop, {
      req(state$running)
      job$stop()
      collect_completed()
      state$running <- FALSE
      state$notice <- "Lookup stopped. Export completed results or resume this batch."
    })
    observeEvent(input$resume, {
      req(state$settings, !state$running, !state$is_example)
      settings <- state$settings
      ids <- pending_ids(settings$ids, settings$prefix, state$rows)
      start_batch(ids, settings)
    })
    observeEvent(input$retry, {
      req(state$settings, !state$running, !state$is_example)
      start_batch(failed_ids(state$settings, state$rows), state$settings)
    })
    observeEvent(input$example, {
      if (state$running) {
        return()
      }
      state$rows <- example_results()
      state$dataset_id <- state$dataset_id + 1L
      state$is_example <- TRUE
      state$settings <- NULL
      state$batch_total <- 0L
      state$batch_done <- 0L
      state$notice <- "Example data. These fictional records demonstrate filtering and export."
    })

    register_input_outputs(input, output, state, prepared_ids)
    result_view <- register_result_outputs(input, output, session, state)
    output$progress_panel <- renderUI(progress_panel(state))
  }
}
