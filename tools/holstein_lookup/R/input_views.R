# Upload feedback and progress controls, separate from session transitions.

register_input_outputs <- function(input, output, state, prepared_ids) {
  output$has_upload <- reactive(!is.null(state$upload))
  outputOptions(output, "has_upload", suspendWhenHidden = FALSE)
  output$upload_info <- renderUI({
    if (!is.null(state$upload_error)) {
      return(div(class = "inline-error", role = "alert", state$upload_error))
    }
    if (is.null(state$upload)) {
      return(NULL)
    }
    tryCatch({
      ids <- prepared_ids()
      div(
        class = "upload-info",
        strong(sprintf("%s rows / %s unique IDs", nrow(state$upload), nrow(ids))),
        span("Blank IDs skipped; duplicates searched once.")
      )
    }, error = function(error) {
      div(class = "inline-error", conditionMessage(error))
    })
  })
  output$preview <- renderTable({
    req(state$upload)
    head(state$upload, 5)
  }, striped = TRUE, spacing = "xs")
  output$search_preview <- renderUI({
    id <- tryCatch({
      req(state$upload)
      prepared_ids()$animal_id[[1]]
    }, error = function(error) NULL)
    if (is.null(id)) {
      return(div(class = "search-preview is-empty", "A search preview will appear after you select your IDs."))
    }
    div(
      class = "search-preview",
      span("First search"),
      code(paste0(normalize_prefix(input$prefix), id))
    )
  })
  output$template <- downloadHandler(
    filename = "holstein-template.csv",
    content = function(path) writeLines(c("animal_id", "004464", "2034"), path)
  )
}

progress_controls <- function(state) {
  if (state$running) {
    return(actionButton("stop", "Stop lookup", class = "btn-sm"))
  }
  if (is.null(state$settings) || state$is_example) {
    return(NULL)
  }
  remaining <- pending_ids(state$settings$ids, state$settings$prefix, state$rows)
  failures <- failed_ids(state$settings, state$rows)
  tagList(
    if (nrow(remaining) > 0) {
      actionButton("resume", sprintf("Resume %s IDs", nrow(remaining)), class = "btn-sm")
    },
    if (nrow(failures) > 0) {
      actionButton("retry", "Retry failed", class = "btn-sm")
    }
  )
}

progress_panel <- function(state) {
  if (is.null(state$notice)) {
    return(NULL)
  }
  div(
    class = paste("progress-panel", if (state$running) "is-running"),
    role = "status",
    div(
      class = "progress-copy",
      span(state$notice),
      if (state$batch_total > 0) {
        tags$small(sprintf(
          "%s of %s IDs processed in this run",
          state$batch_done, state$batch_total
        ))
      }
    ),
    div(class = "progress-actions", progress_controls(state)),
    if (state$batch_total > 0) {
      tags$progress(
        value = state$batch_done,
        max = state$batch_total,
        `aria-label` = "Lookup progress"
      )
    }
  )
}

completion_message <- function(outcome) {
  if (inherits(outcome, "error")) {
    return(paste(
      "Lookup interrupted. Completed results are available.",
      conditionMessage(outcome)
    ))
  }
  if (identical(outcome$reason, "blocked")) {
    return(paste(
      "Holstein blocked three consecutive requests.",
      "Completed results are available; try the remaining IDs later."
    ))
  }
  "Lookup complete."
}
