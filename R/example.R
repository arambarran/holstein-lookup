# Fictional records for exploring the interface without contacting Holstein.

example_results <- function() {
  data.frame(
    animal_id = c("004464", "2034", "3107", "3107", "5182", "6021", "7309"),
    searched_id = paste("COLLEGE", c("004464", "2034", "3107", "3107", "5182", "6021", "7309")),
    input_source = "example.csv",
    match_count = c("1", "1", "2", "2", "1", "0", "0"),
    match_status = c("unique", "unique", "multiple", "multiple", "unique", "not_found", "error"),
    Name = c(
      "EXAMPLE MAPLE", "EXAMPLE CLOVER", "EXAMPLE WILLOW A",
      "EXAMPLE WILLOW B", "EXAMPLE HAZEL", "", ""
    ),
    RegistrationNumber = c("DEMO0001", "DEMO0002", "DEMO0003", "DEMO0004", "DEMO0005", "", ""),
    birth_codes = c("ET", "", "IVF", "ET", "", "", ""),
    genotyping_code = c("GTSM", "GT", "GTS", "GTSM", "GT", "", ""),
    error_message = c(rep("", 6), "Example: request timed out. Retry this ID later."),
    request_url = "",
    stringsAsFactors = FALSE
  )
}
