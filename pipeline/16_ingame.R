# 16_ingame.R -----------------------------------------------------------------
# In-game adaptation features: how many of each pitch type the pitcher has
# thrown so far in THIS game (before the current pitch), overall and over his
# last 15 pitches. Writes data/features/ingame_<season>.parquet keyed by
# (pa_id, pitch_number). Only pitches earlier in the same game are counted.

source("R/constants.R")
source("R/clean.R")

RECENT_WINDOW <- 15

con <- connect_duckdb()
for (s in MODEL_SEASONS) {
  counts <- paste0(
    "COALESCE(SUM((pitch_group = '", PITCH_GROUPS, "')::INT) OVER so_far, 0) AS gtd_", PITCH_GROUPS, ",\n",
    "COALESCE(SUM((pitch_group = '", PITCH_GROUPS, "')::INT) OVER recent, 0) AS rec_", PITCH_GROUPS, collapse = ",\n")
  sql <- sprintf("
    WITH base AS (
      SELECT pa_id, pitch_number, game_pk, pitcher, pitcher_game_pitch_no,
             CASE WHEN target_status = 'model' THEN pitch_group END AS pitch_group, target_status
      FROM read_parquet('data/clean/pitches/*/*.parquet', hive_partitioning = true)
      WHERE game_year = %d)
    SELECT pa_id, pitch_number, %s
    FROM base
    WINDOW so_far AS (PARTITION BY game_pk, pitcher ORDER BY pitcher_game_pitch_no
                      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
           recent AS (PARTITION BY game_pk, pitcher ORDER BY pitcher_game_pitch_no
                      ROWS BETWEEN %d PRECEDING AND 1 PRECEDING)
    QUALIFY target_status = 'model'", s, counts, RECENT_WINDOW)
  out <- DBI::dbGetQuery(con, sql)
  arrow::write_parquet(out, sprintf("data/features/ingame_%d.parquet", s))
  message(s, ": ", nrow(out), " pitches")
}
DBI::dbDisconnect(con, shutdown = TRUE)
