source("tools/holstein_lookup/R/lookup.R")

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
