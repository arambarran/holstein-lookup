# Asset URLs must change with their contents, including on an existing browser.
local({
  app <- new.env(parent = globalenv())
  source("app.R", local = app, chdir = TRUE)
  directory <- tempfile("lookup-assets-")
  dir.create(file.path(directory, "www"), recursive = TRUE)
  original_directory <- setwd(directory)
  on.exit({
    setwd(original_directory)
    unlink(directory, recursive = TRUE)
  })

  for (filename in c("app.css", "app.js")) {
    path <- file.path("www", filename)
    writeLines("first version", path)
    first <- app$asset_url(filename)
    stopifnot(startsWith(first, paste0(filename, "?v=")))
    stopifnot(identical(first, app$asset_url(filename)))
    writeLines("second version", path)
    stopifnot(!identical(first, app$asset_url(filename)))
  }

  for (name in c("upload", "table")) {
    icon <- app$lookup_icon(name)
    stopifnot(icon$attribs$width == "28", icon$attribs$height == "28")
  }
})
cat("Asset versioning and fallback icon dimensions passed.\n")

# Exercise normal Shiny directory startup, including automatic helper loading.
stopifnot(inherits(shiny::shinyAppDir("."), "shiny.appobj"))
