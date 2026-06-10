# Holstein Animal Lookup

Look up Holstein Canada animal records from a CSV of animal IDs.

## Install

```r
install.packages(c("jsonlite", "httr2", "readr", "dplyr", "purrr", "tibble"))
```

## Input

The input can be one CSV file or a directory of CSV files. The script reads the
ID column only and ignores other columns.

Default ID column:

```csv
animal_id
4464
2034
```

## Run

```bash
Rscript tools/holstein_lookup/holstein_lookup.R \
  --input path/to/input.csv \
  --output path/to/output.csv \
  --search-prefix "COLLEGE " \
  --verbose
```

## Options

- `--input`: CSV file or directory of CSV files. Required.
- `--output`: output CSV path.
- `--id-column`: ID column to read, default `animal_id`.
- `--search-prefix`: optional text to put before each ID.
- `--limit`: process only the first N unique IDs.
- `--delay-seconds`: wait between requests, default `2`.
- `--verbose`: print progress.

## Output

The output includes:

```text
animal_id,searched_id,input_source,match_count,match_status,error_message,request_url
```

It also appends whatever fields Holstein returns.

- `unique`: exactly one match.
- `multiple`: more than one match.
- `not_found`: request worked but returned no matches.
- `error`: request failed, was blocked, or returned non-JSON.
