# Local installation

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

## Access an app running on Signal

Start the app on Signal from the repository root:

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
