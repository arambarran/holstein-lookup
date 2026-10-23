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

Requires R 4.1+, Python 3.10+, and network access to Holstein Canada. Run commands
from the repository root.

Install the lookup packages:

```bash
Rscript -e 'install.packages(c("reticulate", "jsonlite", "readr", "dplyr", "tibble", "xml2"), repos = "https://cloud.r-project.org")'
```

Install the Python dependency in a local environment:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
export RETICULATE_PYTHON="$(pwd)/.venv/bin/python"
```

Set `RETICULATE_PYTHON` before starting R. In an existing R console, before its
first Python call, use `Sys.setenv(RETICULATE_PYTHON = normalizePath(".venv/bin/python"))`.

For the Shiny app, also install:

```bash
Rscript -e 'install.packages(c("shiny", "bslib", "reactable", "callr"), repos = "https://cloud.r-project.org")'
```

<details>
<summary>R setup on signal</summary>

If R reports a missing `libgfortran.so.5`, run these before starting either tool:

```bash
export LD_LIBRARY_PATH="/usr/local/MATLAB_Runtime/R2023b/sys/os/glnxa64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LC_ALL=C
```

</details>

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

Run the app locally with the command below, or follow the
[Posit Connect Cloud deployment guide](docs/deployment.md) to publish a shared URL.

```bash
Rscript -e 'shiny::runApp(".", host="127.0.0.1", port=3838, launch.browser=FALSE)'
```

Open <http://127.0.0.1:3838> on the same machine. If running on signal, keep the
app running and open an SSH tunnel from your laptop, replacing `USER` with your
university username:

```bash
ssh -N -L 3838:127.0.0.1:3838 USER@signal.aps.uoguelph.ca
```

Then open the same browser address on your laptop.

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

## Tests

Run the offline R checks from the repository root:

```bash
Rscript tests/run.R
.venv/bin/python -m unittest discover -s tests -p 'test_*.py'
```

With the app running locally and `@playwright/test` installed, run the browser
checks with `node tests/browser.cjs`.
