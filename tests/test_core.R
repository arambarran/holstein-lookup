source("R/lookup.R")

# Decode coat colours without confusing them with birth or genotyping codes.
colours <- parse_search_response(paste0(
  '{"Data":[{"Colour":"B&W"},{"Colour":"R&W"},',
  '{"Colour":"OTHER"},{"Colour":""},{"Colour":null}]}'
))
stopifnot(identical(colours$Colour, c("Black & white", "Red & white", "OTHER", "", NA_character_)))

# Dates are calendar dates, independent of the machine's timezone and locale.
local({
  original_tz <- Sys.getenv("TZ", unset = NA_character_)
  on.exit(if (is.na(original_tz)) Sys.unsetenv("TZ") else Sys.setenv(TZ = original_tz))
  body <- paste0(
    '{"Data":[',
    '{"BirthDate":"/Date(1588219200000)/","DisplayBirthDate":"30 Apr 2020"},',
    '{"BirthDate":"/Date(1198818000000)/","DisplayBirthDate":"28 Dec 2007"},',
    '{"BirthDate":"/Date(-86400000)/"},',
    '{"BirthDate":"/Date(1582934400000+0000)/"},',
    '{"BirthDate":null},{"BirthDate":""},{"BirthDate":"2020-04-30"},',
    '{"BirthDate":"/Date(1588294800000)/","DisplayBirthDate":"30 Apr 2020"}]}'
  )
  expected <- c("2020-04-30", "2007-12-28", "1969-12-31", "2020-02-29",
                NA_character_, "", "2020-04-30", "2020-04-30")
  for (timezone in c("UTC", "America/Los_Angeles", "Pacific/Auckland")) {
    Sys.setenv(TZ = timezone)
    dates <- parse_search_response(body)
    stopifnot(identical(dates$BirthDate, expected))
    stopifnot(dates$DisplayBirthDate[[1]] == "30 Apr 2020")
  }
})

fixture_response <- function(url) {
  if (grepl("ReadAnimalSearchGrid", url)) {
    return('{"Data":[{"AnimalId":123,"Name":"TEST ANIMAL"}]}')
  }
  paste0(
    '<html><body>Registration Status: Registered ET GTSM ',
    'Sire: OTHER IVF GTM Dam: OTHER</body></html>'
  )
}
lookup <- create_lookup_client("COLLEGE ", 0, fixture_response)
result <- lookup("004464", "herd.csv")
stopifnot(
  result$animal_id == "004464",
  result$searched_id == "COLLEGE 004464",
  result$match_status == "unique",
  result$birth_codes == "ET",
  result$genotyping_code == "GTSM"
)
# Clients keep their own settings; creating another must not change the first.
other_lookup <- create_lookup_client("OTHER ", 0, fixture_response)
stopifnot(other_lookup("1", "x.csv")$searched_id == "OTHER 1")
stopifnot(lookup("1", "x.csv")$searched_id == "COLLEGE 1")

missing <- create_lookup_client(read_response = function(url) '{"Data":[]}')
stopifnot(missing("missing", "herd.csv")$match_status == "not_found")
blocked <- create_lookup_client(read_response = function(url) '<html>Cloudflare challenge</html>')
stopifnot(blocked("blocked", "herd.csv")$error_message == "Request was blocked by Cloudflare")
failed <- create_lookup_client(read_response = function(url) stop("HTTP 503 from Holstein lookup"))
stopifnot(failed("error", "herd.csv")$match_status == "error")

multiple_response <- function(url) {
  if (grepl("ReadAnimalSearchGrid", url)) {
    return('{"Data":[{"AnimalId":123},{"AnimalId":456}]}')
  }
  fixture_response(url)
}
multiple <- create_lookup_client(delay = 0, read_response = multiple_response)
stopifnot(nrow(multiple("1", "x.csv")) == 2)
cat("Shared lookup parser and client isolation checks passed.\n")
