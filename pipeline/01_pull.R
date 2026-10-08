# 01_pull.R -------------------------------------------------------------------
# Initial backfill of 2023-2026. Safe to re-run: days already on disk are skipped.
#   Rscript pipeline/01_pull.R            # all seasons
#   Rscript pipeline/01_pull.R 2025       # one season

source("R/pull.R")

args <- commandArgs(trailingOnly = TRUE)
seasons <- if (length(args)) args else names(SEASON_WINDOWS)

for (s in seasons) {
  message("== Season ", s, " ==")
  pull_range(SEASON_WINDOWS[[s]][1], SEASON_WINDOWS[[s]][2])
}
message("Done.")
