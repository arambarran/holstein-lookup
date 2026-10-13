<p align="center">
  <img src="../../docs/assets/cgil.svg" alt="Centre for Genetic Improvement of Livestock" width="210" />
</p>

<h1 align="center">Holstein Animal Lookup</h1>

<p align="center">
  <strong>Animal IDs in. Holstein records out.</strong><br />
  Batch lookups with birth and genotyping codes, saved to CSV.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/R-script-276DC3?logo=r&logoColor=white" alt="R script" />
  <img src="https://img.shields.io/badge/CSV-input_%2F_output-168C87" alt="CSV input and output" />
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#options">Options</a> ·
  <a href="#output">Output</a> ·
  <a href="../../README.md">Repository</a>
</p>

---

Look up [Holstein Canada](https://www.holstein.ca/) animal records from one CSV
or a directory of CSV files, for any herd or project. The tool reads your ID column,
ignores other columns, and searches each unique ID once. It runs as a standalone
script with no database required.

## Quick start

Requires **R**, **curl** on your `PATH`, and access to the Holstein Canada website.
Run these commands from the repository root.

Install the R packages:

```bash
Rscript -e 'install.packages(
  c("jsonlite", "readr", "dplyr", "tibble", "xml2"),
  repos = "https://cloud.r-project.org"
)'
```

Create `input.csv` with an `animal_id` column:

```csv
animal_id
4464
2034
```

Run the lookup:

```bash
Rscript tools/holstein_lookup/holstein_lookup.R \
  --input input.csv \
  --output results.csv \
  --search-prefix "COLLEGE " \
  --verbose
```

This searches for `COLLEGE 4464` and `COLLEGE 2034`. Keep the trailing space in
`"COLLEGE "` so the prefix and ID are separated. For full registration numbers
such as `HOUSAM138974820`, put those in the CSV and omit `--search-prefix`.

## Options

| Option | Purpose |
| --- | --- |
| `--input` | CSV file or directory of CSV files. Required. |
| `--output` | Output CSV path. Required. |
| `--id-column` | ID column to read; defaults to `animal_id`. |
| `--search-prefix` | Text to prepend to each ID, e.g. `"COLLEGE "` for local IDs. |
| `--limit` | Process the first N unique IDs still awaiting lookup. |
| `--delay-seconds` | Request delay in seconds; defaults to `2`. |
| `--verbose` | Print the final output row count and path. |

## Output

The CSV includes Holstein's returned fields alongside these lookup fields:

| Fields | Contents |
| --- | --- |
| `animal_id`, `searched_id`, `input_source` | Original ID, search text including any prefix, and source filename. |
| `match_count`, `match_status` | Number of matches and lookup outcome. |
| `error_message`, `request_url` | Failure details and the search URL. |
| `birth_codes` | Codes from the animal's detail page, such as `ET`. |
| `genotyping_code` | Genotyping code from the detail page, such as `GTSM`. |

`match_status` is `unique` for one match, `multiple` for several, `not_found` for
no matches, or `error` when a request or detail-page lookup fails. Multiple matches
produce one row per matched animal.

Progress and failures print as the script runs, followed by a match-status summary.
Results are saved after each lookup. Failures go to `<output>.failed.csv` and are
retried when you rerun the same command.

> [!NOTE]
> Rerunning with the same output path skips IDs already saved in `searched_id`,
> including `not_found` results. Use a new output path to refresh existing records
> or replace an older export that lacks the birth and genotyping columns.

## Website access

> [!WARNING]
> Holstein Canada may block automated requests. Check `error_message` in the
> failed-results CSV if lookups fail. The script stops after three consecutive
> detected Cloudflare blocks; saved results remain available for a later rerun.
