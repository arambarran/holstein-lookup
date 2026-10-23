<p align="center">
  <img src="docs/assets/cgil.svg" alt="CGIL" width="180" />
</p>

<h1 align="center">Holstein Animal Lookup</h1>

<p align="center">
  Animal records, birth codes, and genotyping codes from <a href="https://www.holstein.ca/">Holstein Canada</a>.<br />
  Look up IDs and export CSV results using the command-line tool or Shiny app.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/R-4.1%2B-276DC3?logo=r&amp;logoColor=white" alt="R 4.1+" />
</p>

<p align="center">
  <a href="#setup">Setup</a> ·
  <a href="#command-line">Command line</a> ·
  <a href="#shiny-app">Shiny app</a> ·
  <a href="#reading-results">Results</a> ·
  <a href="https://github.com/arambarran/cgil">Herdstream</a>
</p>

---

## Setup

To run the tool on your computer, follow the [installation guide](docs/setup.md).
Then use the command-line tool or start the Shiny app below.

## Command line

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

Optional flags: `--id-column COLUMN`, `--limit N`, and `--delay-seconds N`
(default: 2). `--input` also accepts a directory of CSV files.

For a CSV without a header, add `--no-header`. The first row is treated as data,
and IDs are read from the first column (`X1`) by default. Use `--id-column X2`
for the second column, `X3` for the third, and so on. For example:

```bash
Rscript holstein_lookup.R --input input.csv --output results.csv --no-header
```

When reading a directory, the header setting applies to every CSV in it.
Files with headers remain the default and use the `animal_id` column unless
you specify `--id-column`.

Results are saved after each lookup. Errors go to `results.csv.failed.csv`.
Rerun the same command to retry failures and skip completed IDs; use a new output
filename to refresh previous results.

## Shiny app

If you have a shared app link, open it in your browser. To run the app locally
after installation:

```bash
Rscript -e 'shiny::runApp(".", host="127.0.0.1", port=3838, launch.browser=FALSE)'
```

Open <http://127.0.0.1:3838> in your browser.

Upload a CSV. If it has no header, uncheck **File has a header**; the first row
will be kept as data and columns will be named `X1`, `X2`, etc. You can change
this setting after uploading to refresh the preview without uploading again.
Select the ID column, optionally enter a prefix such as `COLLEGE`, and select
**Start lookup**. Filter results and choose columns, then download
**All results**, **Errors**, or **Export view**. Export before closing the tab or
starting another batch. **Example data** lets you try the UI without live requests.

## Reading results

`match_status` is `unique`, `multiple`, `not_found`, or `error`. Multiple matches
produce separate rows. A blank birth or genotyping code means no recognized code
was extracted; it does not confirm the animal's reproductive or testing history.

If a lookup fails, check `error_message` in the results or download **Errors**
from the app.
