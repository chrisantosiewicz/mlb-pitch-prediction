# 06_features.R ---------------------------------------------------------------
# One row per target pitch: context features + the pitcher-mix layers for that
# pitcher, game and batter hand + the mix-change and relabel flags.
# Writes data/features/features_<season>.parquet.

suppressPackageStartupMessages(library(dplyr))
source("R/constants.R")
source("R/clean.R")
source("R/features.R")

args <- commandArgs(trailingOnly = TRUE)
seasons <- if (length(args)) as.integer(args) else MODEL_SEASONS

con <- connect_duckdb()
for (s in seasons) {
  pitches <- DBI::dbGetQuery(con, feature_sql(s))

  mixes <- arrow::read_parquet(sprintf("data/features/mixes_%d.parquet", s)) |>
    tidyr::pivot_wider(id_cols = c(pitcher, game_pk, stand), names_from = pitch_group,
                       values_from = c(p1, p2, p3))
  flags <- arrow::read_parquet(sprintf("data/features/mix_flags_%d.parquet", s)) |>
    select(pitcher, game_pk, mix_changed, relabeled, mix_tvd = tvd,
           season_pitches_before = std_total, history_pitches = hist_total)

  out <- pitches |>
    left_join(mixes, by = c("pitcher", "game_pk", "stand")) |>
    left_join(flags, by = c("pitcher", "game_pk"))

  missing_mix <- sum(is.na(out$p3_FF))
  if (missing_mix > 0) stop(s, ": ", missing_mix, " pitches have no mix")
  arrow::write_parquet(out, sprintf("data/features/features_%d.parquet", s))
  message(sprintf("%d: %s pitches, %d columns", s, format(nrow(out), big.mark = ","), ncol(out)))
}
DBI::dbDisconnect(con, shutdown = TRUE)
