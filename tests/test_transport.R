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

# Only transient failures are retried. Preserve diagnostics for exported errors.
http_response <- function(status = 200L, challenge = FALSE, ray_id = '', retry_after = '') {
  list(status = status, challenge = challenge, ray_id = ray_id,
       retry_after = retry_after, body = 'ok')
}
for (response in list(
  http_response(403L, TRUE, 'test-ray'), http_response(200L, TRUE),
  http_response(403L), http_response(429L, retry_after = '120'), http_response(404L)
)) {
  attempts <- 0L
  failure <- tryCatch(read_response_body_with_retry('fixture', function(url) {
    attempts <<- attempts + 1L
    response_body(response)
  }, sleep = function(seconds) stop('Must not sleep for a permanent error')), error = identity)
  stopifnot(inherits(failure, 'error'), attempts == 1L)
}
challenge <- tryCatch(response_body(http_response(403L, TRUE, 'test-ray')), error = identity)
stopifnot(grepl('Cloudflare challenge', conditionMessage(challenge), fixed=TRUE))
stopifnot(grepl('test-ray', conditionMessage(challenge), fixed=TRUE))
limited <- tryCatch(response_body(http_response(429L, retry_after='120')), error=identity)
stopifnot(grepl('Retry-After: 120', conditionMessage(limited), fixed=TRUE))

attempts <- 0L
pauses <- numeric()
reader <- function(url) {
  attempts <<- attempts + 1L
  response_body(http_response(if (attempts < 3L) 503L else 200L))
}
result <- read_response_body_with_retry('fixture', reader, sleep=function(seconds) {
  pauses <<- c(pauses, seconds)
})
stopifnot(result == 'ok', attempts == 3L, identical(pauses, c(2, 4)))

for (retryable in c(TRUE, FALSE)) {
  attempts <- 0L
  failure <- tryCatch(read_response_body_with_retry('fixture', function(url) {
    attempts <<- attempts + 1L
    response_body(list(error='Timeout', retryable=retryable))
  }, sleep=function(seconds) NULL), error=identity)
  stopifnot(inherits(failure, 'error'), attempts == if (retryable) 3L else 1L)
}
attempts <- 0L
failure <- tryCatch(read_response_body_with_retry('fixture', function(url) {
  attempts <<- attempts + 1L
  stop('Python dependency missing')
}, sleep=function(seconds) NULL), error=identity)
stopifnot(attempts == 1L, conditionMessage(failure) == 'Python dependency missing')
cat('Challenge diagnostics and selective retry checks passed.\n')

# Exercise the actual reticulate/Python boundary with an offline HTTP fixture.
reticulate::import_from_path('holstein_http', path=LOOKUP_MODULE_DIRECTORY)
reticulate::py_run_string(paste(
  'import holstein_http',
  'from types import SimpleNamespace',
  'class FixtureSession:',
  '    calls = 0',
  '    def get(self, url, timeout):',
  '        self.calls += 1',
  '        if url == "challenge":',
  '            return SimpleNamespace(status_code=403, text="blocked", headers={"cf-mitigated":"challenge", "cf-ray":"bridge-ray"})',
  '        return SimpleNamespace(status_code=200, text="fixture body", headers={})',
  'transport_fixture = holstein_http.LookupHTTPClient()',
  'transport_fixture.session.close()',
  'transport_fixture.session = FixtureSession()',
  sep='\n'
))
bridge <- create_response_reader(client_factory=function(directory) reticulate::py$transport_fixture)
stopifnot(bridge('success') == 'fixture body')
failure <- tryCatch(read_response_body_with_retry('challenge', bridge,
  sleep=function(seconds) stop('Unexpected retry')), error=identity)
stopifnot(grepl('bridge-ray', conditionMessage(failure), fixed=TRUE))
stopifnot(reticulate::py$transport_fixture$session$calls == 2L)
reticulate::py_run_string('del transport_fixture')
cat('R/Python bridge response and challenge checks passed.\n')
