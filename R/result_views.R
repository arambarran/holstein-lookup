# Result presentation and downloads. Filtering/export rules live in data.R.

DEFAULT_HIDDEN_COLUMNS <- c("request_url", "input_source", "error_message", "match_count")

result_column_definitions <- function(columns) {
  labels <- c(
    animal_id = "Animal ID",
    searched_id = "Search term",
    input_source = "Source file",
    match_count = "Matches",
    match_status = "Match status",
    error_message = "Error details",
    request_url = "Request URL",
    birth_codes = "Birth codes",
    genotyping_code = "Genotyping code",
    Colour = "Coat colour"
  )
  definitions <- lapply(columns, function(column) {
    label <- if (column %in% names(labels)) labels[[column]] else column
    reactable::colDef(name = label)
  })
  names(definitions) <- columns
  if ("match_status" %in% columns) {
    definitions$match_status <- reactable::colDef(
      name = "Match status",
      minWidth = 130,
      cell = function(value) {
        span(class = paste("match-badge", value), gsub("_", " ", value))
      }
    )
  }
  definitions
}

result_table <- function(rows) {
  reactable::reactable(
    rows,
    columns = result_column_definitions(names(rows)),
    defaultColDef = reactable::colDef(minWidth = 150),
    defaultPageSize = 10,
    showPageSizeOptions = TRUE,
    pageSizeOptions = c(10, 25, 50, 100),
    highlight = TRUE,
    wrap = TRUE,
    paginationType = "simple",
    showSortable = TRUE,
    theme = reactable::reactableTheme(
      color = "#26334a",
      borderColor = "#e5e8ef",
      highlightColor = "#f5f7fc",
      headerStyle = list(background = "#f7f8fb", fontSize = "12px", fontWeight = 600),
      cellStyle = list(padding = "12px 14px", fontSize = "13px")
    ),
    language = reactable::reactableLang(noData = "No records match these filters.")
  )
}

match_summary <- function(rows) {
  counts <- status_counts(rows)
  div(
    class = "match-summary",
    lapply(names(MATCH_LABELS), function(status) {
      span(
        class = paste("match-count", status),
        strong(as.integer(counts[[status]])),
        MATCH_LABELS[[status]]
      )
    }),
    span(class = "count-note", "Counts by animal ID")
  )
}

export_controls <- function(row_count, has_columns) {
  div(
    class = "export-bar",
    div(
      strong(sprintf("%s %s in this view", row_count, if (row_count == 1) "record" else "records")),
      p("View export includes all filtered rows and visible columns.")
    ),
    div(
      class = "export-actions",
      downloadButton("export_all", "All results", class = "btn-sm"),
      downloadButton("export_errors", "Errors", class = "btn-sm"),
      if (has_columns) {
        downloadButton("export_view", "Export view", class = "btn-primary btn-sm")
      }
    )
  )
}

csv_download <- function(suffix, rows, is_example) {
  downloadHandler(
    filename = function() {
      prefix <- if (is_example()) "example-" else "holstein-"
      paste0(prefix, suffix, ".csv")
    },
    content = function(path) write_result_csv(rows(), path)
  )
}

register_result_outputs <- function(input, output, session, state) {
  known_columns <- character()
  known_dataset <- -1L

  # Keep user-selected fields when later responses introduce additional columns.
  observeEvent(state$rows, {
    columns <- names(state$rows)
    if (nrow(state$rows) == 0) {
      return()
    }
    if (state$dataset_id != known_dataset) {
      selected <- setdiff(columns, DEFAULT_HIDDEN_COLUMNS)
      updateTextInput(session, "search", value = "")
      updateSelectInput(session, "status", selected = "all")
    } else {
      selected <- c(input$columns, setdiff(columns, known_columns))
    }
    if (!identical(columns, known_columns) || state$dataset_id != known_dataset) {
      updateSelectizeInput(session, "columns", choices = columns, selected = selected)
    }
    known_columns <<- columns
    known_dataset <<- state$dataset_id
  })

  filtered <- reactive(filter_results(state$rows, input$status, input$search))
  visible_columns <- reactive(intersect(input$columns, names(state$rows)))

  output$has_results <- reactive(nrow(state$rows) > 0)
  outputOptions(output, "has_results", suspendWhenHidden = FALSE)
  output$stats <- renderUI(match_summary(state$rows))
  output$results_caption <- renderUI({
    if (nrow(state$rows) == 0) {
      return(NULL)
    }
    p(sprintf(
      "%s records from %s animal IDs",
      nrow(state$rows), length(unique(state$rows$searched_id))
    ))
  })
  output$dataset_badge <- renderUI({
    if (state$is_example) {
      return(span(class = "dataset-badge example-badge", "Example data"))
    }
    if (!is.null(state$settings)) {
      return(span(class = "dataset-badge", state$settings$filename))
    }
    NULL
  })
  output$results <- reactable::renderReactable({
    req(nrow(state$rows) > 0)
    columns <- visible_columns()
    validate(need(length(columns) > 0, "Choose at least one column to display results."))
    result_table(filtered()[, columns, drop = FALSE])
  })
  output$empty_state <- renderUI({
    if (nrow(state$rows) > 0) {
      return(NULL)
    }
    title <- if (state$running) "Waiting for the first result" else "No results yet"
    instruction <- if (state$running) {
      "Completed records will appear here while the batch runs."
    } else {
      "Upload a CSV, select the ID column, and start a lookup."
    }
    div(class = "empty-state", lookup_icon("table"), h3(title), p(instruction))
  })
  output$exports <- renderUI({
    req(nrow(state$rows) > 0)
    export_controls(nrow(filtered()), length(visible_columns()) > 0)
  })
  output$export_all <- csv_download("all-results", reactive(state$rows), reactive(state$is_example))
  output$export_errors <- csv_download(
    "errors", reactive(filter_results(state$rows, "error")), reactive(state$is_example)
  )
  output$export_view <- csv_download(
    "view",
    function() {
      sorted <- reactable::getReactableState("results", "sorted")
      export_view(filtered(), visible_columns(), sorted)
    },
    reactive(state$is_example)
  )
  list(filtered = filtered, visible_columns = visible_columns)
}
