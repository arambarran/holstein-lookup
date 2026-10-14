# From the repository root: shiny::runApp("tools/holstein_lookup")
source("R/dependencies.R", local = TRUE)
check_dependencies(c(
  "shiny", "bslib", "reactable", "callr", "jsonlite", "readr", "dplyr", "tibble", "xml2"
))
if (utils::packageVersion("bslib") < "0.5.0") {
  stop("Please update bslib to version 0.5.0 or later.")
}
library(shiny)

for (file in c("data", "example", "jobs", "ui", "input_views", "result_views", "server")) {
  source(file.path("R", paste0(file, ".R")), local = TRUE)
}
options(shiny.maxRequestSize = 25 * 1024^2)

ui <- lookup_ui()
server <- create_lookup_server(normalizePath("."))
shinyApp(ui, server)
