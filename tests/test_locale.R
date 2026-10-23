# signal runs R with LC_ALL=C. UI labels must survive that locale.
local({
  original_locale <- Sys.getlocale("LC_CTYPE")
  on.exit(Sys.setlocale("LC_CTYPE", original_locale))
  Sys.setlocale("LC_CTYPE", "C")
  app <- new.env(parent = globalenv())
  source("app.R", local = app, chdir = TRUE)
  upload <- htmltools::renderTags(app$upload_controls())$html
  stopifnot(!grepl("&lt;[0-9a-f]{2}&gt;", upload))
})
cat("UI labels render correctly in the server locale.\n")
