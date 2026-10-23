source('R/lookup.R')

# Resolve the helper beside lookup.R, even when the caller changes directories.
stopifnot(file.exists(file.path(LOOKUP_MODULE_DIRECTORY, 'holstein_http.py')))
created <- 0L
requested <- character()
factory <- function(directory) {
  stopifnot(file.exists(file.path(directory, 'holstein_http.py')))
  created <<- created + 1L
  list(fetch = function(url) {
    requested <<- c(requested, url)
    list(status = 200L, body = 'fixture body', challenge = FALSE, ray_id = '', retry_after = '')
  })
}
reader <- create_response_reader(client_factory = factory)
stopifnot(created == 0L)
original_directory <- getwd()
setwd(tempdir())
stopifnot(reader('search') == 'fixture body', reader('detail') == 'fixture body')
setwd(original_directory)
stopifnot(created == 1L, identical(requested, c('search', 'detail')))
cat('Lazy transport initialization and session reuse checks passed.\n')
