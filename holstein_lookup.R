#!/usr/bin/env Rscript
# Command-line entry point; resolve imports relative to the script, not the shell.
script_argument <- grep("^--file=", commandArgs(), value = TRUE)[[1]]
script_directory <- dirname(normalizePath(sub("^--file=", "", script_argument)))

for (file in c("dependencies", "data", "lookup", "jobs", "cli")) {
  source(file.path(script_directory, "R", paste0(file, ".R")))
}
check_dependencies(c("jsonlite", "readr", "dplyr", "tibble", "xml2"))
run_cli(parse_cli_options(commandArgs(trailingOnly = TRUE)))
