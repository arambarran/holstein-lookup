<p align="center">
  <img src="docs/assets/cgil.svg" alt="CGIL" width="180" />
</p>

<h1 align="center">Holstein Animal Lookup</h1>

<p align="center">
  Animal records, birth codes, and genotyping codes from <a href="https://www.holstein.ca/">Holstein Canada</a>.<br />
  Upload a CSV in the Shiny app or use the command-line tool to look up IDs and export results.
</p>

<p align="center">
  <a href="#shiny-app">Shiny app</a> ·
  <a href="#command-line-tool">Command-line tool</a> ·
  <a href="#reading-results">Results</a> ·
  <a href="https://github.com/arambarran/cgil">Herdstream</a>
</p>

---

## Shiny app

**[Open Holstein Animal Lookup](https://01a166d7-adce-7871-f37f-4d258d9ec893.share.connect.posit.cloud/)** — no installation or account required.

1. Upload your CSV and select the animal ID column. For a headerless file, uncheck
   **File has a header**; columns are named `X1`, `X2`, etc., and the first row is kept.
2. Enter a search prefix such as `COLLEGE` for local IDs, or leave it blank for
   full registration numbers. Check the preview, then select **Start lookup**.
3. Filter results and choose columns. Download **All results**, **Errors**, or
   **Export view** for the filtered rows and selected columns.

Export before closing the tab or starting another batch. **CSV template** provides
a sample input file; **Example data** lets you try the app without running a lookup.

## Command-line tool

Follow the [installation guide](docs/setup.md) to run the tool on your computer.

Create `input.csv`:

```csv
animal_id
HOUSAM138974820
```

Run the lookup:

```bash
Rscript holstein_lookup.R \
  --input input.csv \
  --output results.csv \
  --verbose
```

For local IDs such as `4464`, add `--search-prefix "COLLEGE "` (including the
trailing space). Omit the prefix for full registration numbers.

For a headerless CSV, add `--no-header`. IDs are read from the first column (`X1`)
by default; use `--id-column X2` for the second column.

```bash
Rscript holstein_lookup.R --input input.csv --output results.csv --no-header
```

- `--id-column COLUMN`: choose another ID column; the default is `animal_id` for files with headers.
- `--limit N`: look up at most N IDs.
- `--delay-seconds N`: set the pause between lookups (default: 2 seconds).
- `--input DIRECTORY`: read all CSV files in a folder; the header setting applies to all files.

Results are saved after each lookup. Errors go to `results.csv.failed.csv`.
Rerun the same command to retry failures and skip completed IDs; use a new output
filename to refresh previous results.

## Reading results

`match_status` is `unique`, `multiple`, `not_found`, or `error`. Multiple matches
produce separate rows. A blank birth or genotyping code means no recognized code
was extracted; it does not confirm the animal's reproductive or testing history.

If a lookup fails, check `error_message` in the results or download **Errors**
from the app.
