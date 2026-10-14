# Holstein Animal Lookup

Upload animal IDs to retrieve Holstein Canada records, inspect matches, and export
CSV results. Use the browser app for interactive work or the command-line tool for
repeatable batches. Both share the same lookup client.

## Browser app

The Shiny app provides a CSV upload, a search-prefix preview, live progress,
searchable results, selectable columns, and CSV downloads. It uses the same
Holstein request and parsing functions as the command-line tool.

Requires **R 4.1 or later**, **curl** on your `PATH`, and internet access for live
lookups. Install the packages once:

```bash
Rscript -e 'install.packages(c("shiny", "bslib", "reactable", "callr", "jsonlite", "readr", "dplyr", "tibble", "xml2"), repos = "https://cloud.r-project.org")'
```

From the repository root, launch the app:

```bash
Rscript -e 'shiny::runApp("tools/holstein_lookup", launch.browser = TRUE)'
```

In RStudio, you can also open `tools/holstein_lookup/app.R` and click **Run App**.
The UI uses `bslib` 0.5.0 or later and a current `reactable` release.

1. Choose **Example data** to try the table and downloads without making
   requests. These records are explicitly fictional and exports use an `example-`
   filename prefix.
2. Drop in a CSV (up to 25 MB), select its ID column, and inspect the preview.
   IDs stay as text, including leading zeros. Blank IDs are skipped and repeated
   IDs are searched once. Other input columns appear in the preview but are not
   joined into the returned results.
3. Optionally enter a prefix such as `COLLEGE`. The app adds the separating space
   automatically. Advanced settings control the ID limit and request delay.
4. Select **Start lookup**. Results appear as each ID finishes. Each browser
   session has its own background worker and temporary results.
5. Search any returned field, filter by match status, and open **Columns** to choose which fields to show. Click column headers to sort.
6. Download **All results** (all columns and outcomes, including errors),
   **Errors** (failed IDs and their error details), or **Export view** (all rows
   matching the filters, in table sort order, with only the selected columns).
   Exports cover every matching page, not just the currently visible page.

The match summary counts **animal IDs**, while the table counts **returned rows**:
an ID with multiple matches contributes one multiple-match count and several rows.
No match is chosen automatically.

**Stop lookup** preserves completed IDs. **Resume** processes the unprocessed IDs
from that batch with its original settings; **Retry failed** retries only errors.
The app stops after three consecutive detected access blocks. Starting a new lookup
replaces the current session's results. Download results before starting a new batch
or closing/reloading the tab: session data is temporary, and workers are terminated
when the session ends. Resume is available within the current session only.

The app runs locally by default. A shared deployment needs an R-capable Shiny host;
it cannot run as a static website. Holstein access restrictions and request delays
still apply. Concurrent sessions make independent requests.

### App checks

These checks use local fixtures and do not contact Holstein:

```bash
Rscript -e 'install.packages("testthat", repos = "https://cloud.r-project.org")'
Rscript tools/holstein_lookup/tests/run.R
```

## Code structure

Entry points only check dependencies, load their files, and start the app or CLI.
The files in `R/` contain ordinary functions; sourcing them does not start a lookup.

| File | Responsibility |
| --- | --- |
| `app.R` | Shiny entry point. |
| `holstein_lookup.R` | Command-line entry point. |
| `R/ui.R` | Static page layout and input controls. |
| `R/server.R` | Session state and upload/start/stop/resume/retry transitions. |
| `R/input_views.R` | Upload feedback and progress rendering. |
| `R/result_views.R` | Result table, column choices, and download handlers. |
| `R/data.R` | CSV reading, ID preparation, filtering, sorting, and result merging. |
| `R/lookup.R` | HTTP transport, response parsing, and configured lookup clients. |
| `R/jobs.R` | Background process lifecycle and incremental result snapshots. |
| `R/cli.R` | Argument parsing and command-line batch execution. |
| `R/example.R` | Clearly fictional example records. |
| `R/dependencies.R` | Shared dependency checks. |
| `www/app.css` / `www/app.js` | Styling and browser-only upload/locking behavior. |

The lookup client receives its prefix, delay, and HTTP reader explicitly. Tests
substitute the reader without changing globals. Each Shiny session owns a job and
a state object; the worker publishes completed IDs as atomic RDS snapshots.
Filtering and exports operate on those saved results without additional requests.
The CLI rewrites the accumulated CSV after each result so newly returned fields
cannot become misaligned with an older header.

The app uses the original [CGIL logo](https://cgil.uoguelph.ca/sites/cgil.uoguelph.ca/files/field_feature_image/Ccgil1.gif)
in `www/cgil.gif`, with its original colours and white background.

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
> detected access blocks; saved results remain available for a later rerun.
