# Run from the repository root: Rscript tests/run.R
for (name in c("data", "core", "jobs", "cli", "locale", "assets", "server", "worker")) {
  source(file.path("tests", paste0("test_", name, ".R")))
}
