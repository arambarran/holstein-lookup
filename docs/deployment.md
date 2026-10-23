# Deploy to Posit Connect Cloud

Run these steps from the `holstein-lookup` repository root. The R app also needs
Python dependencies, so include `requirements.txt` and the Python helper when
publishing. The older deployment command that only bundled R and web assets
must be updated as shown below.

## Prepare your environment

In a Bash terminal:

```bash
git pull
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

In a fresh R terminal, install the packages in the [installation guide](setup.md), plus the
publishing package:

```r
install.packages(c("reticulate", "rsconnect"), repos = "https://cloud.r-project.org")
Sys.setenv(RETICULATE_PYTHON = normalizePath(".venv/bin/python"))
```

If you already initialized Python in this R session, restart R before selecting
an environment. Do not copy this local interpreter path into Connect Cloud's
Variables settings; the deployment supplies its own Python environment.

If your account is not connected yet:

```r
rsconnect::connectCloudUser(launch.browser = FALSE)
```

Open the printed link in your browser and follow the authentication prompts.

## Publish or update the test app

Run in the R terminal:

```r
app_files <- c(
  "app.R", "requirements.txt",
  list.files("R", pattern = "\\.(R|py)$", recursive = TRUE, full.names = TRUE),
  list.files("www", recursive = TRUE, full.names = TRUE)
)

rsconnect::deployApp(
  appName = "holstein-lookup-test",
  appPrimaryDoc = "app.R",
  appFiles = app_files,
  python = Sys.getenv("RETICULATE_PYTHON"),
  server = "connect.posit.cloud"
)
```

Use your existing app name if it differs. Keep the local `rsconnect/` deployment
records so future publishes can update the same app. They are excluded from Git.
The package list is installed during deployment; the app does not create a
Python environment or install dependencies while handling lookups.

For GitHub publishing, generate a manifest using the same file list instead:

```r
rsconnect::writeManifest(
  appPrimaryDoc = "app.R",
  appFiles = app_files,
  python = Sys.getenv("RETICULATE_PYTHON")
)
```

Commit `manifest.json` together with `requirements.txt` and the app files, then
select the repository, branch, and `app.R` in Connect Cloud. Regenerate the
manifest when dependencies or bundled files change.

## Verify the published app

Open the published URL and look up one known animal. Check both the match and
its returned details. Example data does not contact Holstein Canada.

If it fails, download **Errors**:

- An initialization error means the selected Python environment or dependencies
  need checking. Confirm the deployment included `requirements.txt` and
  `R/python/holstein_http.py`.
- `Cloudflare challenge` indicates a browser challenge. The error includes a Ray
  ID when available. The request is not retried automatically.
- HTTP 429 indicates rate limiting. Follow the reported `Retry-After` value before
  trying again.

A successful deployment does not guarantee that Holstein accepts requests from
its network. Export results before closing the app; session results are temporary.

References: [Shiny R deployment](https://docs.posit.co/connect-cloud/how-to/r/shiny-r.html),
[Posit's R/Python deployment guidance](https://forum.posit.co/t/publishing-content-that-uses-r-and-python-to-connect-cloud/210165).
