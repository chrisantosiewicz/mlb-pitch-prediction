# 02_clean.R ------------------------------------------------------------------
# Raw Statcast -> data/clean/pitches/game_year=YYYY/*.parquet
# Also writes docs/cleaning_log.md with row counts after every step.

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
})
source("R/constants.R")
source("R/players.R")
source("R/clean.R")
source("R/pull.R")       # SEASON_WINDOWS
source("R/schedule.R")

con <- connect_duckdb()
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

# 1. Player reference table (names, positions) for every pitcher seen.
pitcher_ids <- DBI::dbGetQuery(con, sprintf(
  "SELECT DISTINCT TRY_CAST(pitcher AS INTEGER) AS id
   FROM read_parquet(%s, union_by_name = true, hive_partitioning = false)", raw_glob(SEASONS)))$id
players <- get_players(pitcher_ids)
duckdb::duckdb_register(con, "players", players)
duckdb::duckdb_register(con, "pitch_group_map", PITCH_GROUP_MAP)
message("Players: ", nrow(players), " pitchers looked up")

# 2. Cleaning steps as views, then counts after each step by season.
steps <- build_clean_views(con, SEASONS)
step_counts <- purrr::imap_dfr(steps, function(s, key) {
  DBI::dbGetQuery(con, glue(
    "SELECT game_year, COUNT(*) AS n FROM {s$view} GROUP BY game_year")) |>
    mutate(step = key, what = s$what)
})

# 3. Materialize the final table once, then write it partitioned by season.
invisible(DBI::dbExecute(con, paste("CREATE OR REPLACE TABLE clean AS", final_clean_sql())))
unlink("data/clean/pitches", recursive = TRUE)
dir.create("data/clean", recursive = TRUE, showWarnings = FALSE)
invisible(DBI::dbExecute(con,
  "COPY clean TO 'data/clean/pitches'
   (FORMAT PARQUET, PARTITION_BY (game_year), COMPRESSION ZSTD)"))

q <- function(sql) DBI::dbGetQuery(con, sql)

target_counts <- q("SELECT game_year, target_status, COUNT(*) AS n
                    FROM clean GROUP BY ALL ORDER BY ALL")
rare_types <- q("SELECT COALESCE(pitch_type, '(missing)') AS pitch_type,
                        COALESCE(description, '') AS description,
                        target_status, COUNT(*) AS n
                 FROM clean WHERE target_status <> 'model'
                 GROUP BY ALL ORDER BY n DESC LIMIT 15")
group_mix <- q("SELECT game_year, pitch_group, COUNT(*) AS n FROM clean
                WHERE target_status = 'model' GROUP BY ALL")
position_players <- q("SELECT p.full_name, p.primary_position, COUNT(*) AS pitches
                       FROM s4_valid s JOIN players p ON s.pitcher = p.player_id
                       WHERE p.position_type NOT IN ('Pitcher', 'Two-Way Player')
                       GROUP BY ALL ORDER BY pitches DESC LIMIT 10")
unmatched_pitchers <- q("SELECT COUNT(DISTINCT s.pitcher) AS n FROM s4_valid s
                         LEFT JOIN players p ON s.pitcher = p.player_id
                         WHERE p.player_id IS NULL")$n

# Savant's times-through-order field vs. one derived from the pitcher's own PA
# count in the game (TTO = 1 for PAs 1-9, 2 for 10-18, ...).
tto_check <- q("
  SELECT game_year,
         AVG((n_thruorder_pitcher IS NULL)::INT) AS savant_missing,
         AVG((n_thruorder_pitcher = LEAST(CAST(FLOOR((pitcher_game_pa_no - 1) / 9) + 1 AS INT), 4))::INT)
           AS agree_with_pa_count
  FROM clean GROUP BY game_year ORDER BY game_year")

# Slider/sweeper relabeling check: pitchers whose sweeper share of their
# slider+sweeper total moved by 50+ points between consecutive seasons.
sweeper_shift <- q("
  WITH s AS (
    SELECT pitcher, pitcher_name, game_year,
           SUM((pitch_group = 'ST')::INT) AS st,
           SUM((pitch_group IN ('SL', 'ST'))::INT) AS slst
    FROM clean WHERE target_status = 'model' GROUP BY ALL HAVING slst >= 200)
  SELECT a.pitcher_name, a.game_year AS from_year, b.game_year AS to_year,
         ROUND(a.st / a.slst, 2) AS sweeper_share_before,
         ROUND(b.st / b.slst, 2) AS sweeper_share_after
  FROM s a JOIN s b ON a.pitcher = b.pitcher AND b.game_year = a.game_year + 1
  WHERE ABS(b.st / b.slst - a.st / a.slst) >= 0.5
  ORDER BY ABS(b.st / b.slst - a.st / a.slst) DESC")

# Completeness: every completed game on the MLB schedule should be present.
schedule_check <- missing_games(SEASON_WINDOWS[as.character(SEASONS)],
                                q("SELECT DISTINCT game_pk FROM clean")$game_pk)
schedule_summary <- schedule_check |>
  group_by(season) |>
  summarise(scheduled_games = n(), games_in_data = sum(in_data),
            missing = sum(!in_data), .groups = "drop") |>
  mutate(season = as.character(season))
missing_list <- schedule_check |>
  filter(!in_data) |>
  transmute(season = as.character(season), game_date = as.character(game_date),
            game_pk = as.character(game_pk))

saveRDS(list(schedule_summary = schedule_summary, missing_list = missing_list,
             step_counts = step_counts, target_counts = target_counts,
             rare_types = rare_types, group_mix = group_mix,
             position_players = position_players, tto_check = tto_check,
             sweeper_shift = sweeper_shift, unmatched_pitchers = unmatched_pitchers),
        "data/clean/cleaning_summary.rds")

source("R/cleaning_log.R")
write_cleaning_log(readRDS("data/clean/cleaning_summary.rds"), "docs/cleaning_log.md")
message("Clean rows: ", q("SELECT COUNT(*) AS n FROM clean")$n)
