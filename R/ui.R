# Page structure. Reactive content is supplied by server.R and result_views.R.

asset_url <- function(filename) {
  path <- file.path("www", filename)
  if (!file.exists(path)) {
    stop("Missing app asset: ", path, call. = FALSE)
  }
  # A content hash invalidates cached CSS/JS whenever a deployment changes it.
  paste0(filename, "?v=", unname(tools::md5sum(path)))
}

lookup_header <- function() {
  tags$header(
    class = "app-header",
    div(
      class = "header-inner",
      tags$a(
        href = "https://cgil.uoguelph.ca/",
        target = "_blank",
        rel = "noopener noreferrer",
        class = "logo-link",
        tags$img(src = "cgil.gif", alt = "CGIL", class = "cgil-logo")
      ),
      h1("Holstein Animal Lookup")
    )
  )
}

lookup_icon <- function(name) {
  paths <- switch(name,
    upload = c("M12 16V4m-4 4 4-4 4 4", "M4 16v4h16v-4"),
    table = c("M4 4h16v16H4z", "M4 9h16M9 9v11M4 14h16"),
    stop("Unknown lookup icon")
  )
  tags$svg(
    class = "lookup-icon", width = "28", height = "28",
    viewBox = "0 0 24 24", fill = "none",
    stroke = "currentColor", `stroke-width` = "1.5",
    `stroke-linecap` = "round", `stroke-linejoin` = "round",
    `aria-hidden` = "true", focusable = "false",
    lapply(paths, function(path) tags$path(d = path))
  )
}

upload_controls <- function() {
  div(
    class = "input-field upload-field",
    div(
      class = "upload-area",
      lookup_icon("upload"),
      tags$label(`for` = "csv", class = "upload-title", "Drop a CSV file here"),
      p(class = "upload-hint", "One file, up to 25 MB. IDs are kept as text."),
      fileInput(
        "csv", NULL,
        accept = c(".csv", "text/csv"),
        buttonLabel = "Choose file",
        placeholder = "No file selected"
      ),
      div(id = "upload-error", class = "inline-error", role = "alert")
    ),
    uiOutput("upload_info")
  )
}

search_controls <- function() {
  tagList(
    div(
      class = "input-field",
      selectInput("id_column", "Animal ID column", choices = c("Upload a CSV first" = "")),
      span(class = "field-help", "Select the column containing the animal IDs.")
    ),
    div(
      class = "input-field",
      textInput(
        "prefix",
        tagList("Search prefix ", span(class = "optional", "optional")),
        placeholder = "e.g. COLLEGE"
      ),
      span(class = "field-help", "Leave blank for full registration numbers.")
    )
  )
}

advanced_controls <- function() {
  tags$details(
    class = "advanced-controls",
    tags$summary("Advanced settings"),
    div(
      class = "advanced-fields",
      numericInput("limit", "Maximum IDs (0 = all)", value = 0, min = 0, step = 1),
      numericInput("delay", "Request delay (seconds)", value = 2, min = 0, step = 0.5)
    )
  )
}

lookup_form <- function() {
  tags$section(
    class = "input-section",
    `aria-labelledby` = "input-heading",
    tags$fieldset(
      id = "setup-fields",
      div(
        class = "section-heading",
        div(class = "section-title", span(class = "step-number", "1"),
            h2(id = "input-heading", "Prepare lookup")),
        div(
          class = "utility-links",
          downloadLink("template", "CSV template"),
          actionLink("example", "Example data")
        )
      ),
      div(
        class = "lookup-inputs",
        upload_controls(),
        div(
          class = "search-settings",
          div(class = "search-fields", search_controls()),
          uiOutput("search_preview"),
          advanced_controls()
        )
      ),
      conditionalPanel(
        "output.has_upload",
        tags$details(
          class = "input-preview",
          tags$summary("Preview first 5 rows"),
          tableOutput("preview")
        )
      ),
      div(
        class = "run-controls",
        span(class = "run-help", "Review your IDs and settings before starting."),
        actionButton("run", "Start lookup", class = "btn-primary", disabled = "disabled")
      )
    )
  )
}

result_controls <- function() {
  div(
    class = "result-controls",
    textInput("search", "Search results", placeholder = "Search all returned fields"),
    selectInput(
      "status", "Match status",
      choices = c("All statuses" = "all", stats::setNames(names(MATCH_LABELS), MATCH_LABELS))
    ),
    tags$details(
      class = "column-picker",
      tags$summary("Columns"),
      div(
        class = "column-menu",
        selectizeInput(
          "columns", "Visible columns",
          choices = character(),
          multiple = TRUE,
          options = list(plugins = list("remove_button"))
        ),
        p("Visible columns are included in the view export.")
      )
    )
  )
}

results_section <- function() {
  tags$section(
    class = "results-section",
    `aria-labelledby` = "results-heading",
    div(
      class = "section-heading results-heading",
      div(
        div(class = "section-title", span(class = "step-number", "2"),
            h2(id = "results-heading", "Review results")),
        uiOutput("results_caption")
      ),
      uiOutput("dataset_badge")
    ),
    conditionalPanel("output.has_results", uiOutput("stats"), result_controls()),
    uiOutput("empty_state"),
    reactable::reactableOutput("results"),
    conditionalPanel("output.has_results", uiOutput("exports"))
  )
}

lookup_ui <- function() {
  bslib::page_fluid(
    title = "Holstein Animal Lookup",
    theme = bslib::bs_theme(
      version = 5,
      bg = "#f6f7fa",
      fg = "#202b3d",
      primary = "#10196b",
      base_font = "system-ui",
      border_radius = "0.375rem"
    ),
    tags$head(
      tags$link(rel = "stylesheet", href = asset_url("app.css")),
      tags$script(src = asset_url("app.js"))
    ),
    lookup_header(),
    div(
      class = "app-shell",
      tags$main(lookup_form(), uiOutput("progress_panel"), results_section()),
      tags$footer(
        class = "app-footer",
        tags$a(
          "Holstein Canada",
          href = "https://www.holstein.ca/",
          target = "_blank",
          rel = "noopener noreferrer"
        ),
        span("Results are temporary. Export before closing this tab.")
      )
    )
  )
}
