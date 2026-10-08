# features.R ------------------------------------------------------------------
# Pitch-level context features. Every feature is known before the pitch:
# the count, the game state, and what happened on EARLIER pitches. Sequence
# features are built from all pitches (including automatic balls and rare
# types), so "the previous pitch" is always the actual previous pitch.

# Result of the previous pitch, as a hitter or catcher would describe it.
PREV_RESULT_SQL <- "
  CASE
    WHEN description IN ('ball', 'blocked_ball', 'pitchout', 'automatic_ball', 'intent_ball') THEN 'ball'
    WHEN description IN ('called_strike', 'automatic_strike') THEN 'called'
    WHEN description IN ('swinging_strike', 'swinging_strike_blocked', 'foul_tip', 'missed_bunt') THEN 'whiff'
    WHEN description IN ('foul', 'foul_bunt', 'bunt_foul_tip', 'foul_pitchout') THEN 'foul'
    ELSE 'other'
  END"

feature_sql <- function(season) {
  sprintf("
  WITH base AS (
    SELECT *,
      CASE WHEN target_status = 'model' THEN pitch_group ELSE 'OTHER' END AS seq_group,
      %s AS result,
      CASE WHEN pitch_group IN ('FF', 'SI', 'FC') THEN 1 ELSE 0 END AS is_fb,
      CASE WHEN pitch_group IN ('SL', 'ST', 'CU') THEN 1 ELSE 0 END AS is_br,
      CASE WHEN pitch_group IN ('CH', 'FS') THEN 1 ELSE 0 END AS is_os
    FROM read_parquet('data/clean/pitches/*/*.parquet', hive_partitioning = true)
    WHERE game_year = %d),
  seq AS (
    SELECT *,
      COALESCE(LAG(seq_group, 1) OVER pa, 'NONE') AS prev1_group,
      COALESCE(LAG(result, 1) OVER pa, 'none') AS prev1_result,
      COALESCE(LAG(seq_group, 2) OVER pa, 'NONE') AS prev2_group,
      -- this pitcher's mix earlier in this game, before this pitch
      COALESCE(SUM(is_fb) OVER today, 0) AS gtd_fb,
      COALESCE(SUM(is_br) OVER today, 0) AS gtd_br,
      COALESCE(SUM(is_os) OVER today, 0) AS gtd_os
    FROM base
    WINDOW pa AS (PARTITION BY pa_id ORDER BY pitch_number),
           today AS (PARTITION BY game_pk, pitcher ORDER BY pitcher_game_pitch_no
                     ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING))
  SELECT
    game_year, game_date, game_pk, pa_id, pitch_number, pitcher, pitcher_name, batter,
    stand, p_throws, pitch_group,
    count_str,
    (stand = p_throws) AS same_hand,
    prev1_group, prev1_result, prev2_group,
    base_state, outs_when_up AS outs,
    CASE WHEN inning <= 3 THEN '1-3' WHEN inning <= 6 THEN '4-6'
         WHEN inning <= 9 THEN '7-9' ELSE '10+' END AS inning_bkt,
    CASE WHEN score_diff <= -4 THEN 'down4+' WHEN score_diff <= -2 THEN 'down2-3'
         WHEN score_diff = -1 THEN 'down1' WHEN score_diff = 0 THEN 'tied'
         WHEN score_diff = 1 THEN 'up1' WHEN score_diff <= 3 THEN 'up2-3' ELSE 'up4+' END AS score_bkt,
    LEAST(n_thruorder_pitcher, 3) AS tto,
    CASE WHEN pitcher_game_pitch_no <= 25 THEN '1-25' WHEN pitcher_game_pitch_no <= 50 THEN '26-50'
         WHEN pitcher_game_pitch_no <= 75 THEN '51-75' WHEN pitcher_game_pitch_no <= 100 THEN '76-100'
         ELSE '100+' END AS pitch_count_bkt,
    is_starter,
    gtd_fb + gtd_br + gtd_os AS gtd_n,
    CASE WHEN gtd_fb + gtd_br + gtd_os > 0 THEN gtd_fb / (gtd_fb + gtd_br + gtd_os) ELSE 0 END AS gtd_fb_share,
    CASE WHEN gtd_fb + gtd_br + gtd_os > 0 THEN gtd_br / (gtd_fb + gtd_br + gtd_os) ELSE 0 END AS gtd_br_share
  FROM seq
  WHERE target_status = 'model'", PREV_RESULT_SQL, season)
}

FEATURE_FORMULA <- ~ count_str * same_hand +
  prev1_group * prev1_result + prev2_group +
  base_state + outs + inning_bkt + score_bkt + tto + pitch_count_bkt + is_starter +
  gtd_fb_share + gtd_br_share + gtd_any +
  mix_changed + relabeled

FACTOR_LEVELS <- list(
  count_str = c("0-0", "0-1", "0-2", "1-0", "1-1", "1-2", "2-0", "2-1", "2-2", "3-0", "3-1", "3-2"),
  prev1_group = c("NONE", PITCH_GROUPS, "OTHER"),
  prev2_group = c("NONE", PITCH_GROUPS, "OTHER"),
  prev1_result = c("none", "ball", "called", "whiff", "foul", "other"),
  base_state = c("___", "1__", "_2_", "__3", "12_", "1_3", "_23", "123"),
  inning_bkt = c("1-3", "4-6", "7-9", "10+"),
  score_bkt = c("tied", "down4+", "down2-3", "down1", "up1", "up2-3", "up4+"),
  pitch_count_bkt = c("1-25", "26-50", "51-75", "76-100", "100+")
)

prepare_factors <- function(df) {
  for (col in names(FACTOR_LEVELS)) df[[col]] <- factor(df[[col]], levels = FACTOR_LEVELS[[col]])
  df$outs <- factor(df$outs, levels = 0:2)
  df$tto <- factor(df$tto, levels = 1:3)
  df$gtd_any <- df$gtd_n > 0
  df
}

model_matrix <- function(df) {
  Matrix::sparse.model.matrix(FEATURE_FORMULA, data = df)[, -1, drop = FALSE]
}
