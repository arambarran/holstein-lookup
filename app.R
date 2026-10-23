# From the repository root: shiny::runApp(".")
source("R/dependencies.R", local = TRUE, encoding = "UTF-8")
check_dependencies(c(
  "shiny", "bslib", "reactable", "callr", "reticulate", "jsonlite", "readr", "dplyr", "tibble", "xml2"
))
if (utils::packageVersion("bslib") < "0.5.0") {
  stop("Please update bslib to version 0.5.0 or later.")
}
library(shiny)

for (file in c("data", "example", "jobs", "ui", "input_views", "result_views", "server")) {
  source(file.path("R", paste0(file, ".R")), local = TRUE, encoding = "UTF-8")
}
options(shiny.maxRequestSize = 25 * 1024^2)

ui <- lookup_ui()
server <- create_lookup_server(normalizePath("."))
shinyApp(ui, server)
