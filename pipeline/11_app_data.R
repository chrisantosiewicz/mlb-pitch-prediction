# 11_app_data.R ---------------------------------------------------------------
# Precomputes the small tables the matchup app and PDF report read, so the
# app never touches the 3.5M-row pitch table. Writes app/data/*.parquet and
# copies the shared R files and final model into app/.

suppressPackageStartupMessages(library(dplyr))
source("R/constants.R")
source("R/clean.R")
source("R/players.R")
source("R/batter.R")
source("R/report_data.R")

REPORT_SEASON <- 2026
OUTCOME_SEASONS <- 2025:2026   # xwOBA tables use two seasons for sample size
APP_DATA <- "app/data"
dir.create(APP_DATA, recursive = TRUE, showWarnings = FALSE)

con <- connect_duckdb()
q <- function(sql) DBI::dbGetQuery(con, sql)
CLEAN <- "read_parquet('data/clean/pitches/*/*.parquet', hive_partitioning = true)"

# ---- players ----
season_players <- q(sprintf("
  SELECT pitcher AS player_id, 'P' AS role, ANY_VALUE(pitcher_team) AS team, COUNT(*) AS pitches
  FROM %s WHERE game_year = %d GROUP BY pitcher
  UNION ALL
  SELECT batter, 'B', ANY_VALUE(batter_team), COUNT(*)
  FROM %s WHERE game_year = %d GROUP BY batter", CLEAN, REPORT_SEASON, CLEAN, REPORT_SEASON))
people <- get_players(season_players$player_id)
players <- season_players |>
  left_join(people, by = "player_id") |>
  select(player_id, role, full_name, team, pitches, bat_side, pitch_hand, primary_position)
arrow::write_parquet(players, file.path(APP_DATA, "players.parquet"))

# ---- pitcher tables (report season) ----
arrow::write_parquet(q(pitcher_count_mix_sql(CLEAN, REPORT_SEASON)), file.path(APP_DATA, "pitcher_count_mix.parquet"))
arrow::write_parquet(q(pitcher_locations_sql(CLEAN, REPORT_SEASON)), file.path(APP_DATA, "pitcher_locations.parquet"))
arrow::write_parquet(q(pitcher_arsenal_sql(CLEAN, REPORT_SEASON)), file.path(APP_DATA, "pitcher_arsenal.parquet"))

# ---- outcome tables (two seasons, shrunk toward league) ----
outcomes <- q(outcome_events_sql(CLEAN, OUTCOME_SEASONS))
arrow::write_parquet(outcome_tables(outcomes), file.path(APP_DATA, "outcomes.parquet"))


# How often each previous-pitch result leads into each count (for averaging
# over an unknown previous pitch in the app).
prev_freq <- arrow::read_parquet(sprintf("data/features/features_%d.parquet", REPORT_SEASON),
                                 col_select = c("count_str", "prev1_result")) |>
  count(count_str, prev1_result) |>
  group_by(count_str) |>
  mutate(share = n / sum(n)) |>
  ungroup()
arrow::write_parquet(prev_freq, file.path(APP_DATA, "prev_result_freq.parquet"))
# ---- head to head (all seasons) ----
arrow::write_parquet(q(head_to_head_sql(CLEAN)), file.path(APP_DATA, "head_to_head.parquet"))

# ---- model state at the end of the report season ----
mix_state <- end_of_season_mix(REPORT_SEASON)
arrow::write_parquet(mix_state$mixes, file.path(APP_DATA, "mix_state.parquet"))
arrow::write_parquet(mix_state$flags, file.path(APP_DATA, "mix_flags.parquet"))
batter_state <- end_of_season_batter(jsonlite::read_json("models/batter.json")$tau)
arrow::write_parquet(batter_state, file.path(APP_DATA, "batter_state.parquet"))

meta <- list(
  report_season = REPORT_SEASON, outcome_seasons = OUTCOME_SEASONS,
  data_through = as.character(q(sprintf("SELECT MAX(game_date) AS d FROM %s WHERE game_year = %d",
                                        CLEAN, REPORT_SEASON))$d),
  app_model = jsonlite::read_json("models/final.json")$app_model,
  sz_top = q(sprintf("SELECT AVG(sz_top) AS v FROM %s WHERE game_year = %d", CLEAN, REPORT_SEASON))$v,
  sz_bot = q(sprintf("SELECT AVG(sz_bot) AS v FROM %s WHERE game_year = %d", CLEAN, REPORT_SEASON))$v,
  created = as.character(Sys.time())
)
jsonlite::write_json(meta, file.path(APP_DATA, "meta.json"), auto_unbox = TRUE, pretty = TRUE)
DBI::dbDisconnect(con, shutdown = TRUE)

# ---- app bundle: shared code + final model ----
dir.create("app/lib", showWarnings = FALSE)   # not app/R: Shiny auto-sources that folder alphabetically
invisible(file.copy(c("R/constants.R", "R/features.R", "R/boost_model.R", "R/report.R"), "app/lib", overwrite = TRUE))
dir.create("app/models", showWarnings = FALSE)
invisible(file.copy("models/final_xgboost.ubj", "app/models", overwrite = TRUE))

sizes <- file.info(list.files(APP_DATA, full.names = TRUE))$size
message(sprintf("App data written: %d files, %.1f MB", length(sizes), sum(sizes) / 1e6))
