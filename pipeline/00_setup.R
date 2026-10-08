# 00_setup.R -----------------------------------------------------------------
# One-time environment setup. Recreate on a new machine with renv::restore().

options(repos = c(
  CRAN = "https://cloud.r-project.org",
  sportsdataverse = "https://sportsdataverse.r-universe.dev"
))

if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
if (!file.exists("renv.lock")) renv::init(bare = TRUE, restart = FALSE)

pkgs <- c(
  # data
  "baseballr", "arrow", "duckdb", "DBI",
  # wrangling
  "dplyr", "tidyr", "readr", "purrr", "stringr", "lubridate", "glue", "jsonlite",
  # modeling
  "nnet", "glmnet", "xgboost",
  # plots, app, reports
  "ggplot2", "scales", "shiny", "bslib", "rsconnect", "quarto", "knitr", "rmarkdown",
  # testing
  "testthat"
)
renv::install(pkgs, prompt = FALSE)
renv::snapshot(type = "all", prompt = FALSE)
