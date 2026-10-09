# report_data.R ---------------------------------------------------------------
# Builders for the small tables behind the matchup report (app and PDF).

# xwOBA by pitch type is shrunk toward the league value for that pitch type
# and handedness matchup: this many plate appearances of league average are
# blended in, so a hitter with 12 PAs ending on splitters isn't shown at .700.
XWOBA_SHRINK_PA <- 60

SWING_DESCRIPTIONS <- c("swinging_strike", "swinging_strike_blocked", "foul", "foul_tip",
                        "hit_into_play", "foul_bunt", "missed_bunt", "bunt_foul_tip")
WHIFF_DESCRIPTIONS <- c("swinging_strike", "swinging_strike_blocked", "missed_bunt")

sql_in <- function(x) paste0("'", x, "'", collapse = ", ")

pitcher_count_mix_sql <- function(clean, season) {
  sprintf("
    SELECT pitcher, stand, count_str, pitch_group, COUNT(*) AS n
    FROM %s WHERE game_year = %d AND target_status = 'model'
    GROUP BY ALL", clean, season)
}

pitcher_locations_sql <- function(clean, season) {
  sprintf("
    SELECT pitcher, stand, pitch_group,
           CAST(balls AS TINYINT) AS balls, CAST(strikes AS TINYINT) AS strikes,
           CAST(ROUND(plate_x, 2) AS FLOAT) AS plate_x, CAST(ROUND(plate_z, 2) AS FLOAT) AS plate_z
    FROM %s
    WHERE game_year = %d AND target_status = 'model'
      AND plate_x IS NOT NULL AND plate_z IS NOT NULL", clean, season)
}

pitcher_arsenal_sql <- function(clean, season) {
  sprintf("
    SELECT pitcher, stand, pitch_group, COUNT(*) AS n,
           AVG(release_speed) AS velo, AVG(release_spin_rate) AS spin,
           AVG(pfx_x) * 12 AS h_break_in, AVG(pfx_z) * 12 AS v_break_in,
           SUM(COALESCE(description IN (%s), FALSE)::INT) AS swings,
           SUM(COALESCE(description IN (%s), FALSE)::INT) AS whiffs,
           SUM((zone BETWEEN 1 AND 9)::INT) AS in_zone,
           SUM((zone > 9 AND description IN (%s))::INT) AS chases,
           SUM((zone > 9)::INT) AS out_zone
    FROM %s WHERE game_year = %d AND target_status = 'model'
    GROUP BY ALL", sql_in(SWING_DESCRIPTIONS), sql_in(WHIFF_DESCRIPTIONS),
          sql_in(SWING_DESCRIPTIONS), clean, season)
}

# One row per pitch with the outcome pieces needed for xwOBA, K/BB and whiffs.
# xwOBA per PA follows Savant: batted balls use the expected value from exit
# velocity and launch angle; walks, strikeouts and HBP use their actual value.
outcome_events_sql <- function(clean, seasons) {
  sprintf("
    SELECT pitcher, batter, p_throws, stand, pitch_group,
           COALESCE(description IN (%s), FALSE)::INT AS swing,
           COALESCE(description IN (%s), FALSE)::INT AS whiff,
           COALESCE(woba_denom = 1, FALSE)::INT AS pa_end,
           CASE WHEN woba_denom = 1 THEN
             COALESCE(CASE WHEN type = 'X' THEN estimated_woba_using_speedangle END, woba_value)
           END AS xwoba,
           COALESCE(events IN ('strikeout', 'strikeout_double_play'), FALSE)::INT AS k,
           COALESCE(events IN ('walk', 'intent_walk'), FALSE)::INT AS bb
    FROM %s
    WHERE game_year IN (%s) AND target_status = 'model'",
          sql_in(SWING_DESCRIPTIONS), sql_in(WHIFF_DESCRIPTIONS), clean, paste(seasons, collapse = ", "))
}

summarise_outcomes <- function(df, ...) {
  df |>
    dplyr::group_by(...) |>
    dplyr::summarise(pitches = dplyr::n(), swings = sum(swing), whiffs = sum(whiff),
                     pa = sum(pa_end), xwoba_sum = sum(xwoba, na.rm = TRUE),
                     k = sum(k), bb = sum(bb), .groups = "drop")
}

# Long table: each player's results by pitch type vs. each opposing hand,
# from both sides (batter facing pitch types; pitcher throwing them).
outcome_tables <- function(events) {
  by_group <- function(df) dplyr::bind_rows(df, dplyr::mutate(df, pitch_group = "ALL"))
  ev <- by_group(events)

  league <- summarise_outcomes(ev, p_throws, stand, pitch_group) |>
    dplyr::transmute(p_throws, stand, pitch_group, league_xwoba = xwoba_sum / pa)

  batter <- summarise_outcomes(ev, batter, p_throws, stand, pitch_group) |>
    dplyr::left_join(league, by = c("p_throws", "stand", "pitch_group")) |>
    dplyr::mutate(league_w = pmax(pa, 1), league_sum = league_xwoba * league_w) |>
    dplyr::group_by(batter, p_throws, pitch_group) |>   # switch hitters: pool both sides
    dplyr::summarise(dplyr::across(c(pitches, swings, whiffs, pa, xwoba_sum, k, bb, league_sum, league_w), sum),
                     .groups = "drop") |>
    dplyr::mutate(league_xwoba = league_sum / league_w) |>
    dplyr::transmute(side = "batter", player_id = batter, opp_hand = p_throws, pitch_group,
                     pitches, swings, whiffs, pa, xwoba_sum, k, bb, league_xwoba)
  pitcher <- summarise_outcomes(ev, pitcher, p_throws, stand, pitch_group) |>
    dplyr::left_join(league, by = c("p_throws", "stand", "pitch_group")) |>
    dplyr::transmute(side = "pitcher", player_id = pitcher, opp_hand = stand, pitch_group,
                     pitches, swings, whiffs, pa, xwoba_sum, k, bb, league_xwoba)

  dplyr::bind_rows(batter, pitcher) |>
    dplyr::mutate(xwoba = ifelse(pa > 0, xwoba_sum / pa, NA_real_),
                  xwoba_shrunk = (xwoba_sum + XWOBA_SHRINK_PA * league_xwoba) / (pa + XWOBA_SHRINK_PA),
                  whiff_rate = ifelse(swings > 0, whiffs / swings, NA_real_),
                  k_rate = ifelse(pa > 0, k / pa, NA_real_),
                  bb_rate = ifelse(pa > 0, bb / pa, NA_real_)) |>
    dplyr::select(-xwoba_sum)
}

head_to_head_sql <- function(clean) {
  sprintf("
    SELECT pitcher, batter, pitch_group, MIN(game_year) AS first_year, MAX(game_year) AS last_year,
           COUNT(*) AS pitches,
           SUM(COALESCE(woba_denom = 1, FALSE)::INT) AS pa,
           SUM(CASE WHEN woba_denom = 1 THEN
                 COALESCE(CASE WHEN type = 'X' THEN estimated_woba_using_speedangle END, woba_value) END) AS xwoba_sum,
           SUM(COALESCE(events IN ('strikeout', 'strikeout_double_play'), FALSE)::INT) AS k,
           SUM(COALESCE(events IN ('walk', 'intent_walk'), FALSE)::INT) AS bb,
           SUM(COALESCE(events IN ('single', 'double', 'triple', 'home_run'), FALSE)::INT) AS hits,
           SUM(COALESCE(events = 'home_run', FALSE)::INT) AS hr
    FROM %s WHERE target_status = 'model'
    GROUP BY ALL", clean)
}

# Each pitcher's mix as of the end of the season: the layers from his last
# game, updated with that game's pitches too (what a scout would use next).
end_of_season_mix <- function(season) {
  params <- jsonlite::read_json("models/mixes.json")
  mixes <- arrow::read_parquet(sprintf("data/features/mixes_%d.parquet", season))
  flags <- arrow::read_parquet(sprintf("data/features/mix_flags_%d.parquet", season))
  games <- arrow::read_parquet(sprintf("data/features/features_%d.parquet", season),
                               col_select = c("pitcher", "game_pk", "game_date", "pitch_group"))
  last_game <- games |>
    dplyr::distinct(pitcher, game_pk, game_date) |>
    dplyr::group_by(pitcher) |>
    dplyr::slice_max(game_date, n = 1, with_ties = FALSE) |>
    dplyr::ungroup()
  season_counts <- games |>
    dplyr::count(pitcher, pitch_group, name = "season_n") |>
    tidyr::complete(pitcher, pitch_group = PITCH_GROUPS, fill = list(season_n = 0))

  state <- mixes |>
    dplyr::semi_join(last_game, by = c("pitcher", "game_pk")) |>
    dplyr::left_join(season_counts, by = c("pitcher", "pitch_group")) |>
    dplyr::mutate(season_n = dplyr::coalesce(season_n, 0)) |>
    dplyr::group_by(pitcher, stand) |>
    dplyr::mutate(p2_end = (season_n + params$tau_std * p1) / (sum(season_n) + params$tau_std),
                  p3_end = p2_end * p3 / p2,
                  p3_end = p3_end / sum(p3_end)) |>
    dplyr::ungroup() |>
    dplyr::select(pitcher, stand, pitch_group, p1, p2 = p2_end, p3 = p3_end)

  season_totals <- dplyr::summarise(dplyr::group_by(season_counts, pitcher), season_total = sum(season_n))
  flag_state <- flags |>
    dplyr::semi_join(last_game, by = c("pitcher", "game_pk")) |>
    dplyr::left_join(season_totals, by = "pitcher") |>
    dplyr::transmute(pitcher, mix_changed, relabeled, mix_tvd = tvd,
                     season_pitches_before = season_total, history_pitches = hist_total)
  list(mixes = state, flags = flag_state)
}

# Each batter's tilt after all games through the end of the season.
end_of_season_batter <- function(tau) {
  obs <- paste0("SUM((pitch_group = '", PITCH_GROUPS, "')::INT) AS o_", PITCH_GROUPS, collapse = ", ")
  exp <- paste0("SUM(p3_", PITCH_GROUPS, ") AS e_", PITCH_GROUPS, collapse = ", ")
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  totals <- DBI::dbGetQuery(con, sprintf(
    "SELECT batter, NULL::INTEGER AS game_pk, MAX(game_year) AS game_year, %s, %s
     FROM read_parquet('data/features/features_*.parquet') GROUP BY batter", obs, exp))
  batter_adjustments(totals, tau) |> dplyr::select(-game_pk, -game_year)
}
