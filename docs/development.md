# Development

Follow the [local installation guide](setup.md) before working on the project.

## Tests

Run the offline R checks from the repository root:

```bash
Rscript tests/run.R
.venv/bin/python -m unittest discover -s tests -p 'test_*.py'
```

With the app running locally and `@playwright/test` installed, run the browser
checks with `node tests/browser.cjs`.

## Deployment

See the [Posit Connect Cloud deployment guide](deployment.md).
