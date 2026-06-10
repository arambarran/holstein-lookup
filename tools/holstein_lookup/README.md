# Holstein Animal Lookup

Small R script for looking up Holstein Canada animal records from robot CSV
animal IDs. Requests include browser-style AJAX headers because Holstein may
reject the default R user agent.

By default, the script searches the raw animal ID. For example, animal ID `4464`
is searched as:

```text
https://www.holstein.ca/en/AIS/ReadAnimalSearchGrid?animalSearchString=4464
```

For Elora searches, pass `--search-prefix "COLLEGE "`. Then
animal ID `4464` is searched as:

```text
https://www.holstein.ca/en/AIS/ReadAnimalSearchGrid?animalSearchString=COLLEGE%204464
```

## Install

```r
install.packages(c("jsonlite", "httr2", "readr", "dplyr", "purrr", "tibble"))
```

## Run On Robot CSVs

```bash
Rscript tools/holstein_lookup/holstein_lookup.R \
  --input data/robot/mock \
  --id-column animal_id \
  --output data/holstein_lookup/mock_animal_lookup.csv \
  --delay-seconds 2 \
  --verbose
```

If `--input` is a directory, the script reads every `*.csv` file directly inside
that folder.

To search with the College prefix:

```bash
Rscript tools/holstein_lookup/holstein_lookup.R \
  --input data/robot/mock \
  --id-column animal_id \
  --search-prefix "COLLEGE " \
  --output data/holstein_lookup/college_animal_lookup.csv
```

## Run On A Plain ID List

Input CSV:

```text
animal_id
4464
2034
2041
```

Command:

```bash
Rscript tools/holstein_lookup/holstein_lookup.R \
  --input data/holstein_lookup/elora_ids.csv \
  --output data/holstein_lookup/elora_animal_lookup.csv
```

## Options

- `--input`: CSV file or directory of CSV files.
- `--output`: output CSV path.
- `--id-column`: ID column to read, default `animal_id`.
- `--search-prefix`: optional text to put before each ID, default empty.
- `--limit`: process only the first N unique IDs.
- `--delay-seconds`: wait between requests, default `2`.
- `--verbose`: print progress.

## Output

The output includes:

```text
animal_id,searched_id,input_source,match_count,match_status,error_message,request_url
```

Then it appends whatever fields Holstein returns.

Status meanings:

- `unique`: exactly one Holstein match.
- `multiple`: more than one match; inspect manually.
- `not_found`: request worked but returned no matches.
- `error`: request failed, was blocked, or returned non-JSON.
