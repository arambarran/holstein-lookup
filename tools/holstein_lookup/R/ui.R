# Page structure. Reactive content is supplied by server.R and result_views.R.

lookup_header <- function() {
  tags$header(
    class = "app-header",
    tags$a(
      href = "https://cgil.uoguelph.ca/",
      target = "_blank",
      rel = "noopener noreferrer",
      class = "logo-link",
      tags$img(src = "cgil.gif", alt = "CGIL", class = "cgil-logo")
    ),
    h1("Holstein Animal Lookup")
  )
}

upload_controls <- function() {
  div(
    class = "input-field upload-field",
    tags$label(`for` = "csv", class = "control-label", "CSV file"),
    div(
      class = "upload-area",
      fileInput(
        "csv", NULL,
        accept = c(".csv", "text/csv"),
        buttonLabel = "Browse…",
        placeholder = "Drop a CSV file here"
      )
    ),
    span(class = "field-help", "Maximum 25 MB. IDs are read as text.")
  )
}

search_controls <- function() {
  tagList(
    div(
      class = "input-field",
      selectInput("id_column", "Animal ID column", choices = character()),
      span(class = "field-help", "Select the column containing your IDs.")
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
        h2(id = "input-heading", "Input"),
        div(
          class = "utility-links",
          downloadLink("template", "CSV template"),
          actionLink("example", "Example data")
        )
      ),
      div(class = "lookup-inputs", upload_controls(), search_controls()),
      div(
        class = "input-summary",
        uiOutput("upload_info"),
        uiOutput("search_preview")
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
        advanced_controls(),
        actionButton("run", "Start lookup", class = "btn-primary")
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
      div(h2(id = "results-heading", "Results"), uiOutput("results_caption")),
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
      bg = "#ffffff",
      fg = "#202b3d",
      primary = "#10196b",
      base_font = "system-ui",
      border_radius = "0.25rem"
    ),
    tags$head(
      tags$link(rel = "stylesheet", href = "app.css"),
      tags$script(src = "app.js")
    ),
    div(
      class = "app-shell",
      lookup_header(),
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
