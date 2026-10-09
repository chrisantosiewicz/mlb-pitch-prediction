# run_all.R -------------------------------------------------------------------
# Rebuilds everything from scratch, in order. Each step only reads what the
# previous step wrote.
#   Rscript run_all.R

steps <- c(
  "pipeline/01_pull.R",        # Savant -> data/raw/        (skips days already pulled)
  "pipeline/02_clean.R",       # data/raw -> data/clean/   + docs/cleaning_log.md
  "pipeline/03_dictionary.R",  # docs/data_dictionary.md
  "pipeline/04_baseline.R",    # models/baseline.json      + docs/baseline_results.md
  "pipeline/05_mixes.R",       # pitcher-mix layers        + docs/mix_results.md
  "pipeline/06_features.R",    # data/features/features_<season>.parquet
  "pipeline/07_logistic.R",    # models/logistic_*.rds     + docs/logistic_results.md
  "pipeline/08_batter.R",      # batter layer              + models/batter.json
  "pipeline/09_tune_models.R", # batter layer check, xgboost rounds -> models/tuning.json
  "pipeline/10_test_2026.R",   # one-time 2026 test        + docs/test_results.md
  "pipeline/11_app_data.R"     # app/data tables + app bundle (then: shiny::runApp("app"))
)

for (step in steps) {
  message("\n>>> ", step)
  status <- system2(file.path(R.home("bin"), "Rscript"), step)
  if (status != 0) stop(step, " failed with status ", status)
}
testthat::test_dir("tests/testthat")
