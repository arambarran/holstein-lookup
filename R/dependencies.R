check_dependencies <- function(packages) {
  installed <- vapply(packages, requireNamespace, logical(1), quietly = TRUE)
  if (any(!installed)) {
    stop("Install missing R packages: ", paste(packages[!installed], collapse = ", "))
  }
}
