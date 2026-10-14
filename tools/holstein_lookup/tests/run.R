# Run from the repository root: Rscript tools/holstein_lookup/tests/run.R
for (name in c("data", "core", "jobs", "cli", "server", "worker")) {
  source(file.path("tools/holstein_lookup/tests", paste0("test_", name, ".R")))
}
