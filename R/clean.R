# clean.R ---------------------------------------------------------------------
# Raw Statcast text -> one typed row per pitch. Each step is a SQL view so the
# row count after every step can be logged (docs/cleaning_log.md).

connect_duckdb <- function() {
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  DBI::dbExecute(con, "SET preserve_insertion_order = false")
  con
}

raw_glob <- function(seasons) {
  paste0("['", paste0("data/raw/season=", seasons, "/*.parquet", collapse = "', '"), "']")
}

# Columns kept in the clean table, with their SQL type. Everything Savant sends
# is documented in docs/data_dictionary.md, including the columns dropped here.
CLEAN_COLUMNS <- c(
  # identifiers
  game_pk = "INTEGER", game_date = "DATE", game_year = "INTEGER", game_type = "VARCHAR",
  home_team = "VARCHAR", away_team = "VARCHAR",
  pitcher = "INTEGER", batter = "INTEGER", player_name = "VARCHAR",
  at_bat_number = "INTEGER", pitch_number = "INTEGER",
  # game state before the pitch (allowed as model features)
  inning = "INTEGER", inning_topbot = "VARCHAR", outs_when_up = "INTEGER",
  balls = "INTEGER", strikes = "INTEGER",
  on_1b = "INTEGER", on_2b = "INTEGER", on_3b = "INTEGER",
  stand = "VARCHAR", p_throws = "VARCHAR",
  bat_score = "INTEGER", fld_score = "INTEGER",
  n_thruorder_pitcher = "INTEGER", n_priorpa_thisgame_player_at_bat = "INTEGER",
  pitcher_days_since_prev_game = "INTEGER",
  if_fielding_alignment = "VARCHAR", of_fielding_alignment = "VARCHAR",
  age_pit = "INTEGER", age_bat = "INTEGER",
  # the pitch itself (known only after release: target and report fields)
  pitch_type = "VARCHAR", pitch_name = "VARCHAR",
  release_speed = "DOUBLE", effective_speed = "DOUBLE", release_spin_rate = "DOUBLE",
  spin_axis = "DOUBLE", pfx_x = "DOUBLE", pfx_z = "DOUBLE",
  release_pos_x = "DOUBLE", release_pos_z = "DOUBLE", release_extension = "DOUBLE",
  arm_angle = "DOUBLE", plate_x = "DOUBLE", plate_z = "DOUBLE", zone = "INTEGER",
  sz_top = "DOUBLE", sz_bot = "DOUBLE",
  # outcome (report fields only)
  type = "VARCHAR", description = "VARCHAR", events = "VARCHAR", bb_type = "VARCHAR",
  launch_speed = "DOUBLE", launch_angle = "DOUBLE",
  estimated_ba_using_speedangle = "DOUBLE", estimated_woba_using_speedangle = "DOUBLE",
  woba_value = "DOUBLE", woba_denom = "DOUBLE", delta_run_exp = "DOUBLE",
  bat_speed = "DOUBLE", swing_length = "DOUBLE"
)

typed_select_sql <- function(available) {
  cols <- names(CLEAN_COLUMNS)
  exprs <- vapply(cols, function(col) {
    type <- CLEAN_COLUMNS[[col]]
    if (!col %in% available) return(sprintf("CAST(NULL AS %s) AS %s", type, col))
    # Savant writes missing values as empty strings or the text 'NA'.
    src <- sprintf("NULLIF(NULLIF(TRIM(%s), ''), 'NA')", col)
    if (type == "VARCHAR") sprintf("%s AS %s", src, col)
    else if (type == "INTEGER") sprintf("CAST(TRY_CAST(%s AS DOUBLE) AS INTEGER) AS %s", src, col)
    else sprintf("TRY_CAST(%s AS %s) AS %s", src, type, col)
  }, character(1))
  paste(exprs, collapse = ",\n  ")
}

# Builds the chain of views. Returns a list of step name -> view name, in order,
# with a plain-language description for the cleaning log.
build_clean_views <- function(con, seasons) {
  DBI::dbExecute(con, sprintf(
    "CREATE OR REPLACE VIEW raw AS
     SELECT * FROM read_parquet(%s, union_by_name = true, hive_partitioning = false)", raw_glob(seasons)))
  available <- DBI::dbListFields(con, "raw")

  DBI::dbExecute(con, sprintf(
    "CREATE OR REPLACE VIEW s1_typed AS
     SELECT %s, TRY_CAST(pulled_at AS VARCHAR) AS pulled_at FROM raw",
    typed_select_sql(available)))

  DBI::dbExecute(con,
    "CREATE OR REPLACE VIEW s2_regular AS
     SELECT * FROM s1_typed WHERE game_type = 'R'")

  # The same pitch can appear twice if a day was re-pulled; keep the newest copy.
  DBI::dbExecute(con,
    "CREATE OR REPLACE VIEW s3_dedup AS
     SELECT * EXCLUDE (rn) FROM (
       SELECT *, ROW_NUMBER() OVER (
         PARTITION BY game_pk, at_bat_number, pitch_number
         ORDER BY pulled_at DESC) AS rn
       FROM s2_regular)
     WHERE rn = 1")

  DBI::dbExecute(con,
    "CREATE OR REPLACE VIEW s4_valid AS
     SELECT * FROM s3_dedup
     WHERE pitcher IS NOT NULL AND batter IS NOT NULL
       AND balls BETWEEN 0 AND 3 AND strikes BETWEEN 0 AND 2
       AND outs_when_up BETWEEN 0 AND 2")

  DBI::dbExecute(con, sprintf(
    "CREATE OR REPLACE VIEW s5_no_position_players AS
     SELECT s.* FROM s4_valid s
     LEFT JOIN players p ON s.pitcher = p.player_id
     WHERE p.position_type IN (%s)",
    paste0("'", PITCHER_POSITION_TYPES, "'", collapse = ", ")))

  list(
    raw = list(view = "s1_typed", what = "All pitches pulled from Savant (all game types)"),
    regular = list(view = "s2_regular", what = "Kept regular-season games only (`game_type = 'R'`); drops spring training, exhibitions and postseason"),
    dedup = list(view = "s3_dedup", what = "Removed duplicate pitches (same game, PA and pitch number), keeping the most recent pull"),
    valid = list(view = "s4_valid", what = "Removed rows with a missing pitcher or batter, or an impossible count or out total"),
    no_pos = list(view = "s5_no_position_players", what = "Removed pitches thrown by position players (MLB Stats API primary position is not Pitcher or Two-Way Player)")
  )
}

# Final table: derived fields and the model-target flag.
final_clean_sql <- function() {
  non_desc <- paste0("'", NON_PITCH_DESCRIPTIONS, "'", collapse = ", ")
  non_type <- paste0("'", NON_PITCH_TYPES, "'", collapse = ", ")
  sprintf("
  SELECT *,
    -- The starter is whoever threw his team's first pitch of the game. This is
    -- known before the game begins, so it is safe to use as a feature.
    (pitcher = FIRST_VALUE(pitcher) OVER (
       PARTITION BY game_pk, pitcher_team ORDER BY at_bat_number, pitch_number)) AS is_starter
  FROM (
  SELECT
    s.*,
    p.full_name AS pitcher_name,
    s.player_name AS batter_name,
    g.pitch_group,
    g.pitch_group_name,
    CASE WHEN s.inning_topbot = 'Top' THEN s.home_team ELSE s.away_team END AS pitcher_team,
    CASE WHEN s.inning_topbot = 'Top' THEN s.away_team ELSE s.home_team END AS batter_team,
    s.balls || '-' || s.strikes AS count_str,
    (s.on_1b IS NOT NULL)::INT + (s.on_2b IS NOT NULL)::INT + (s.on_3b IS NOT NULL)::INT AS runners_on,
    CASE WHEN s.on_1b IS NOT NULL THEN '1' ELSE '_' END ||
    CASE WHEN s.on_2b IS NOT NULL THEN '2' ELSE '_' END ||
    CASE WHEN s.on_3b IS NOT NULL THEN '3' ELSE '_' END AS base_state,
    s.fld_score - s.bat_score AS score_diff,
    s.game_pk::BIGINT * 1000 + s.at_bat_number AS pa_id,
    ROW_NUMBER() OVER (PARTITION BY s.game_pk, s.pitcher
                       ORDER BY s.at_bat_number, s.pitch_number) AS pitcher_game_pitch_no,
    DENSE_RANK() OVER (PARTITION BY s.game_pk, s.pitcher
                       ORDER BY s.at_bat_number) AS pitcher_game_pa_no,
    CASE
      WHEN s.description IN (%s) THEN 'non_pitch'
      WHEN s.pitch_type IN (%s) THEN 'non_pitch'
      WHEN s.pitch_type IS NULL THEN 'unclassified'
      WHEN g.pitch_group IS NULL THEN 'rare_type'
      ELSE 'model'
    END AS target_status
  FROM s5_no_position_players s
  LEFT JOIN players p ON s.pitcher = p.player_id
  LEFT JOIN pitch_group_map g ON s.pitch_type = g.pitch_type
  )", non_desc, non_type)
}
