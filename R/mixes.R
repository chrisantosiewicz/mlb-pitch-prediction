# mixes.R ---------------------------------------------------------------------
# Pitcher pitch-mix estimates for every (pitcher, game, batter hand), using
# only information available before that game starts:
#
#   L1 prior mix     earlier seasons, recency-weighted, shrunk to the league mix
#                    for his hand and role (the Phase 1 baseline)
#   L2 current form  L1 updated with his pitches this season through his
#                    PREVIOUS game
#   L3 + platoon     L2 tilted by his usual split vs. this batter's hand
#
# Before L1 is built, Savant relabels are repaired: if a pitch he used to throw
# has vanished this season while a new pitch with the same velocity and
# movement has appeared, his history of the old label is credited to the new
# one. Each step uses only games already played.

# Relabel matching thresholds.
RELABEL_MIN_HIST_SHARE <- 0.05   # old pitch was a real part of his mix
RELABEL_MAX_NEW_HIST_SHARE <- 0.02  # new pitch was (almost) never thrown before
RELABEL_MIN_STD_PITCHES <- 30    # enough pitches this season to trust "vanished"
RELABEL_MIN_NEW_SHARE <- 0.05    # new pitch is a real part of this season's mix
RELABEL_MAX_VELO_DIFF <- 2.0     # mph
RELABEL_MAX_MOVE_DIFF <- 4 / 12  # ft (4 inches of combined movement)

# Mix-change flag: his season-to-date mix is statistically inconsistent with
# his prior mix.
MIX_CHANGE_MIN_PITCHES <- 50
MIX_CHANGE_P_VALUE <- 0.001
# With hundreds of pitches almost any drift is "significant", so the flag also
# needs a meaningful size: at least 20% of his pitches moved to other types
# (total variation distance).
MIX_CHANGE_MIN_TVD <- 0.20
# A "change" needs an established mix to change from: pitchers with little
# history are compared mostly against the league mix, which says nothing about
# whether HE changed.
MIX_CHANGE_MIN_HISTORY <- 200

CLEAN_GLOB <- "read_parquet('data/clean/pitches/*/*.parquet', hive_partitioning = true)"

# ---- SQL building blocks ------------------------------------------------------

# One row per pitcher appearance, numbered within the pitcher's season.
create_pitcher_games <- function(con) {
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE pitcher_games AS
    SELECT *, ROW_NUMBER() OVER (PARTITION BY pitcher, game_year
                                 ORDER BY game_date, game_pk) AS game_no
    FROM (SELECT pitcher, game_year, game_pk, MIN(game_date) AS game_date,
                 ANY_VALUE(p_throws) AS p_throws, BOOL_OR(is_starter) AS is_starter
          FROM %s GROUP BY pitcher, game_year, game_pk)", CLEAN_GLOB))
}

# Per pitcher-game-group: pitches and physics sums for that game alone.
create_game_group_stats <- function(con) {
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE game_group_stats AS
    SELECT pitcher, game_pk, pitch_group, stand,
           COUNT(*) AS n,
           COUNT(release_speed) AS n_velo, SUM(release_speed) AS sum_velo,
           COUNT(pfx_x) AS n_move, SUM(pfx_x) AS sum_pfx_x, SUM(pfx_z) AS sum_pfx_z
    FROM %s WHERE target_status = 'model'
    GROUP BY ALL", CLEAN_GLOB))
}

# Season-to-date counts and physics through the PREVIOUS game, for every
# pitcher-game x pitch group (zeros included).
season_to_date <- function(con) {
  DBI::dbGetQuery(con, "
    WITH grid AS (
      SELECT pg.pitcher, pg.game_year, pg.game_pk, pg.game_no, g.pitch_group
      FROM pitcher_games pg CROSS JOIN pitch_groups g),
    per_game AS (
      SELECT pitcher, game_pk, pitch_group,
             SUM(n) AS n, SUM(n_velo) AS n_velo, SUM(sum_velo) AS sum_velo,
             SUM(n_move) AS n_move, SUM(sum_pfx_x) AS sum_pfx_x, SUM(sum_pfx_z) AS sum_pfx_z
      FROM game_group_stats GROUP BY ALL)
    SELECT grid.pitcher, grid.game_year, grid.game_pk, grid.pitch_group,
      COALESCE(SUM(p.n) OVER w, 0) AS std_n,
      SUM(p.n_velo) OVER w AS std_n_velo, SUM(p.sum_velo) OVER w AS std_sum_velo,
      SUM(p.n_move) OVER w AS std_n_move,
      SUM(p.sum_pfx_x) OVER w AS std_sum_pfx_x, SUM(p.sum_pfx_z) OVER w AS std_sum_pfx_z
    FROM grid LEFT JOIN per_game p
      ON grid.pitcher = p.pitcher AND grid.game_pk = p.game_pk
     AND grid.pitch_group = p.pitch_group
    WINDOW w AS (PARTITION BY grid.pitcher, grid.game_year, grid.pitch_group
                 ORDER BY grid.game_no ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)")
}

# Season totals per pitcher x season x batter hand x group (history building block).
season_totals <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT g.pitcher, pg.game_year, g.stand, g.pitch_group,
           SUM(g.n) AS n, SUM(g.n_velo) AS n_velo, SUM(g.sum_velo) AS sum_velo,
           SUM(g.n_move) AS n_move, SUM(g.sum_pfx_x) AS sum_pfx_x, SUM(g.sum_pfx_z) AS sum_pfx_z
    FROM game_group_stats g JOIN pitcher_games pg
      ON g.pitcher = pg.pitcher AND g.game_pk = pg.game_pk
    GROUP BY ALL")
}

# League mix by hand and role from seasons before `season` (the shrinkage target).
league_prior <- function(con, season) {
  DBI::dbGetQuery(con, sprintf("
    SELECT pg.p_throws, CASE WHEN pg.is_starter THEN 'SP' ELSE 'RP' END AS role,
           g.pitch_group, SUM(g.n) AS n
    FROM game_group_stats g JOIN pitcher_games pg
      ON g.pitcher = pg.pitcher AND g.game_pk = pg.game_pk
    WHERE pg.game_year < %d GROUP BY ALL", season)) |>
    tidyr::complete(p_throws, role, pitch_group = PITCH_GROUPS, fill = list(n = 0)) |>
    dplyr::group_by(p_throws, role) |>
    dplyr::mutate(m = (n + 1) / sum(n + 1)) |>
    dplyr::ungroup() |>
    dplyr::select(-n)
}

# ---- History and relabels -----------------------------------------------------

# Recency-weighted history from seasons before `season`, by hand and overall.
weighted_history <- function(totals, season, decay) {
  totals |>
    dplyr::filter(game_year < season) |>
    dplyr::mutate(w = decay^(season - 1 - game_year)) |>
    dplyr::group_by(pitcher, stand, pitch_group) |>
    dplyr::summarise(dplyr::across(c(n, n_velo, sum_velo, n_move, sum_pfx_x, sum_pfx_z),
                                   ~ sum(w * .x, na.rm = TRUE)), .groups = "drop")
}

# Finds relabels for every pitcher-game. Returns (pitcher, game_pk, from_group, to_group).
detect_relabels <- function(hist_overall, std) {
  hist_share <- hist_overall |>
    dplyr::group_by(pitcher) |>
    dplyr::mutate(hist_share = n / sum(n)) |>
    dplyr::ungroup()
  std_share <- std |>
    dplyr::group_by(pitcher, game_pk) |>
    dplyr::mutate(std_total = sum(std_n), std_share = std_n / pmax(std_total, 1)) |>
    dplyr::ungroup() |>
    dplyr::filter(std_total >= RELABEL_MIN_STD_PITCHES)

  candidates <- std_share |>
    dplyr::left_join(dplyr::select(hist_share, pitcher, pitch_group, hist_share,
                                   h_velo = velo, h_pfx_x = pfx_x, h_pfx_z = pfx_z),
                     by = c("pitcher", "pitch_group")) |>
    dplyr::mutate(hist_share = dplyr::coalesce(hist_share, 0))

  vanished <- candidates |>
    dplyr::filter(hist_share >= RELABEL_MIN_HIST_SHARE, std_n == 0) |>
    dplyr::select(pitcher, game_pk, from_group = pitch_group, h_velo, h_pfx_x, h_pfx_z)
  appeared <- candidates |>
    dplyr::filter(hist_share < RELABEL_MAX_NEW_HIST_SHARE, std_share >= RELABEL_MIN_NEW_SHARE) |>
    dplyr::mutate(s_velo = std_sum_velo / std_n_velo,
                  s_pfx_x = std_sum_pfx_x / std_n_move, s_pfx_z = std_sum_pfx_z / std_n_move) |>
    dplyr::select(pitcher, game_pk, to_group = pitch_group, s_velo, s_pfx_x, s_pfx_z)

  vanished |>
    dplyr::inner_join(appeared, by = c("pitcher", "game_pk"), relationship = "many-to-many") |>
    dplyr::mutate(velo_diff = abs(h_velo - s_velo),
                  move_diff = sqrt((h_pfx_x - s_pfx_x)^2 + (h_pfx_z - s_pfx_z)^2)) |>
    dplyr::filter(velo_diff <= RELABEL_MAX_VELO_DIFF, move_diff <= RELABEL_MAX_MOVE_DIFF) |>
    # each old and each new label is used at most once: keep the closest match
    dplyr::arrange(move_diff) |>
    dplyr::distinct(pitcher, game_pk, from_group, .keep_all = TRUE) |>
    dplyr::distinct(pitcher, game_pk, to_group, .keep_all = TRUE) |>
    dplyr::select(pitcher, game_pk, from_group, to_group, velo_diff, move_diff)
}

# Applies relabels to history counts keyed by (pitcher, game_pk, [stand], group).
apply_relabels <- function(hist_by_game, relabels) {
  if (!nrow(relabels)) return(hist_by_game)
  moved <- hist_by_game |>
    dplyr::inner_join(dplyr::select(relabels, pitcher, game_pk, from_group, to_group),
                      by = c("pitcher", "game_pk", "pitch_group" = "from_group"))
  keys <- intersect(c("pitcher", "game_pk", "stand"), names(hist_by_game))
  credit <- moved |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(keys, "to_group")))) |>
    dplyr::summarise(add = sum(h_n), .groups = "drop") |>
    dplyr::rename(pitch_group = to_group)
  hist_by_game |>
    dplyr::left_join(dplyr::transmute(moved, dplyr::across(dplyr::all_of(keys)), pitch_group,
                                      zero_out = TRUE),
                     by = c(keys, "pitch_group")) |>
    dplyr::left_join(credit, by = c(keys, "pitch_group")) |>
    dplyr::mutate(h_n = dplyr::if_else(dplyr::coalesce(zero_out, FALSE), 0, h_n) +
                    dplyr::coalesce(add, 0)) |>
    dplyr::select(-zero_out, -add)
}

# ---- Mix ladder ---------------------------------------------------------------

shrink <- function(n, N, kappa, target) (n + kappa * target) / (N + kappa)

normalize_by <- function(df, col, ...) {
  df |>
    dplyr::group_by(...) |>
    dplyr::mutate("{col}" := .data[[col]] / sum(.data[[col]])) |>
    dplyr::ungroup()
}

# G-test of season-to-date counts against the prior mix.
mix_change_test <- function(df) {
  df |>
    dplyr::group_by(pitcher, game_pk) |>
    dplyr::summarise(
      std_total = sum(std_n), hist_total = dplyr::first(hist_total),
      g_stat = 2 * sum(ifelse(std_n > 0, std_n * log(std_n / (std_total * p1)), 0)),
      tvd = 0.5 * sum(abs(std_n / pmax(std_total, 1) - p1)),
      .groups = "drop") |>
    dplyr::mutate(p_value = stats::pchisq(g_stat, df = length(PITCH_GROUPS) - 1, lower.tail = FALSE),
                  mix_changed = std_total >= MIX_CHANGE_MIN_PITCHES & p_value < MIX_CHANGE_P_VALUE &
                    tvd >= MIX_CHANGE_MIN_TVD & hist_total >= MIX_CHANGE_MIN_HISTORY)
}

# Builds L1/L2/L3 mixes for one scored season. Returns one row per
# (pitcher, game_pk, stand, pitch_group) plus a per-game flags table.
build_mixes <- function(parts, season, params) {
  pg <- dplyr::filter(parts$pitcher_games, game_year == season) |>
    dplyr::mutate(role = ifelse(is_starter, "SP", "RP"))
  std <- dplyr::filter(parts$std, game_year == season)
  prior <- parts$league_priors[[as.character(season)]]

  hist_hand <- weighted_history(parts$totals, season, params$decay)
  hist_overall <- hist_hand |>
    dplyr::group_by(pitcher, pitch_group) |>
    dplyr::summarise(dplyr::across(c(n, n_velo, sum_velo, n_move, sum_pfx_x, sum_pfx_z), sum),
                     .groups = "drop") |>
    dplyr::mutate(velo = sum_velo / n_velo, pfx_x = sum_pfx_x / n_move, pfx_z = sum_pfx_z / n_move)

  relabels <- if (isTRUE(params$relabel)) detect_relabels(hist_overall, std)
              else tibble::tibble(pitcher = integer(), game_pk = integer(),
                                  from_group = character(), to_group = character())

  # History per pitcher-game (so relabels can differ game to game), overall and by hand.
  grid <- pg |> dplyr::select(pitcher, game_pk, p_throws, role) |>
    tidyr::crossing(pitch_group = PITCH_GROUPS)
  h_overall <- grid |>
    dplyr::left_join(dplyr::select(hist_overall, pitcher, pitch_group, h_n = n),
                     by = c("pitcher", "pitch_group")) |>
    dplyr::mutate(h_n = dplyr::coalesce(h_n, 0)) |>
    apply_relabels(relabels)
  h_hand <- grid |>
    tidyr::crossing(stand = c("L", "R")) |>
    dplyr::left_join(dplyr::select(hist_hand, pitcher, stand, pitch_group, h_n = n),
                     by = c("pitcher", "stand", "pitch_group")) |>
    dplyr::mutate(h_n = dplyr::coalesce(h_n, 0)) |>
    apply_relabels(relabels)

  # L1: prior mix, shrunk toward the league mix for his hand and role.
  l1 <- h_overall |>
    dplyr::left_join(prior, by = c("p_throws", "role", "pitch_group")) |>
    dplyr::group_by(pitcher, game_pk) |>
    dplyr::mutate(hist_total = sum(h_n), p1 = shrink(h_n, hist_total, params$kappa, m)) |>
    dplyr::ungroup()

  # L2: current form = L1 updated with this season's pitches through last game.
  l2 <- l1 |>
    dplyr::left_join(dplyr::select(std, pitcher, game_pk, pitch_group, std_n),
                     by = c("pitcher", "game_pk", "pitch_group")) |>
    dplyr::mutate(std_n = dplyr::coalesce(std_n, 0)) |>
    dplyr::group_by(pitcher, game_pk) |>
    dplyr::mutate(p2 = shrink(std_n, sum(std_n), params$tau_std, p1)) |>
    dplyr::ungroup()

  # L3: tilt L2 by his historical split vs. this batter hand (shrunk toward L1).
  l3 <- h_hand |>
    dplyr::select(pitcher, game_pk, stand, pitch_group, hh_n = h_n) |>
    dplyr::left_join(dplyr::select(l2, pitcher, game_pk, pitch_group, p1, p2, hist_total),
                     by = c("pitcher", "game_pk", "pitch_group")) |>
    dplyr::group_by(pitcher, game_pk, stand) |>
    dplyr::mutate(p_hand = shrink(hh_n, sum(hh_n), params$tau_hand, p1),
                  p3 = p2 * p_hand / p1) |>
    dplyr::ungroup() |>
    normalize_by("p3", pitcher, game_pk, stand)

  flags <- mix_change_test(l2) |>
    dplyr::left_join(dplyr::count(relabels, pitcher, game_pk, name = "n_relabels"),
                     by = c("pitcher", "game_pk")) |>
    dplyr::mutate(relabeled = dplyr::coalesce(n_relabels, 0L) > 0) |>
    dplyr::select(-n_relabels)

  list(mixes = dplyr::select(l3, pitcher, game_pk, stand, pitch_group, p1, p2, p3),
       flags = flags, relabels = relabels)
}

# Loads everything build_mixes() needs in one pass over the clean data.
load_mix_parts <- function(con, scored_seasons) {
  duckdb::duckdb_register(con, "pitch_groups", tibble::tibble(pitch_group = PITCH_GROUPS))
  create_pitcher_games(con)
  create_game_group_stats(con)
  list(
    pitcher_games = DBI::dbGetQuery(con, "SELECT * FROM pitcher_games"),
    std = season_to_date(con),
    totals = season_totals(con),
    league_priors = stats::setNames(lapply(scored_seasons, function(s) league_prior(con, s)),
                                    scored_seasons)
  )
}

# Actual pitches thrown per (pitcher, game, batter hand, group): for scoring mixes.
actual_counts <- function(con, season) {
  DBI::dbGetQuery(con, sprintf("
    SELECT pitcher, game_pk, stand, pitch_group, COUNT(*) AS n
    FROM %s WHERE target_status = 'model' AND game_year = %d
    GROUP BY ALL", CLEAN_GLOB, season))
}

score_mix <- function(mixes, actual, col) {
  actual |>
    dplyr::left_join(dplyr::select(mixes, pitcher, game_pk, stand, pitch_group, prob = dplyr::all_of(col)),
                     by = c("pitcher", "game_pk", "stand", "pitch_group")) |>
    dplyr::summarise(pitches = sum(n), log_loss = -sum(n * log(prob)) / sum(n))
}

score_mix_family <- function(mixes, actual, col) {
  fam <- function(df) dplyr::mutate(df, family = PITCH_FAMILY[pitch_group])
  probs <- fam(dplyr::select(mixes, pitcher, game_pk, stand, pitch_group, prob = dplyr::all_of(col))) |>
    dplyr::group_by(pitcher, game_pk, stand, family) |>
    dplyr::summarise(prob = sum(prob), .groups = "drop")
  fam(actual) |>
    dplyr::group_by(pitcher, game_pk, stand, family) |>
    dplyr::summarise(n = sum(n), .groups = "drop") |>
    dplyr::left_join(probs, by = c("pitcher", "game_pk", "stand", "family")) |>
    dplyr::summarise(family_log_loss = -sum(n * log(prob)) / sum(n))
}

# Top-1 accuracy of a mix column (most likely pitch for that pitcher-game-hand).
top1_mix <- function(mixes, actual, col) {
  best <- mixes |>
    dplyr::group_by(pitcher, game_pk, stand) |>
    dplyr::slice_max(.data[[col]], n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(pitcher, game_pk, stand, top = pitch_group)
  actual |>
    dplyr::left_join(best, by = c("pitcher", "game_pk", "stand")) |>
    dplyr::summarise(top1 = sum(n * (pitch_group == top)) / sum(n))
}
