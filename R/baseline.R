# baseline.R ------------------------------------------------------------------
# The baseline every model has to beat: predict each pitch from the pitcher's
# overall pitch mix, ignoring count, batter and situation.
#
# Shrinkage (empirical Bayes). A pitcher's mix is a weighted blend of what he
# threw in earlier seasons and the league mix for pitchers like him (same
# throwing hand, starting vs. relieving):
#
#   p_k = (n_k + kappa * m_k) / (N + kappa)
#
# n_k = his recency-weighted count of pitch k, N = his total, m_k = the league
# mix for his group, kappa = how many "pretend pitches" of league mix he starts
# with. With 2,000 pitches of history kappa barely matters; with 20 it decides
# almost everything. kappa and the recency weight are tuned on the tuning
# season, never on the test season.

# Model-target pitches with the columns the baseline needs.
load_targets <- function(con, seasons) {
  DBI::dbGetQuery(con, sprintf(
    "SELECT game_year, pitcher, pitcher_name, p_throws, is_starter, pitch_group
     FROM read_parquet('data/clean/pitches/*/*.parquet', hive_partitioning = true)
     WHERE target_status = 'model' AND game_year IN (%s)",
    paste(seasons, collapse = ", ")))
}

role_of <- function(is_starter) ifelse(is_starter, "SP", "RP")

# Recency weights: the season just before the scored one counts 1, the one
# before that `decay`, then decay^2, ...
season_weights <- function(train_seasons, score_season, decay) {
  stats::setNames(decay^(score_season - 1 - train_seasons), train_seasons)
}

# League mix by throwing hand and role, from the training seasons.
group_prior <- function(train) {
  train |>
    dplyr::mutate(role = role_of(is_starter)) |>
    dplyr::count(p_throws, role, pitch_group) |>
    tidyr::complete(p_throws, role, pitch_group = PITCH_GROUPS, fill = list(n = 0)) |>
    dplyr::group_by(p_throws, role) |>
    dplyr::mutate(m = (n + 1) / sum(n + 1)) |>   # +1 so no group is exactly zero
    dplyr::ungroup() |>
    dplyr::select(p_throws, role, pitch_group, m)
}

# Each pitcher's recency-weighted pitch counts from the training seasons.
pitcher_history <- function(train, weights) {
  train |>
    dplyr::mutate(w = weights[as.character(game_year)]) |>
    dplyr::group_by(pitcher, pitch_group) |>
    dplyr::summarise(n = sum(w), .groups = "drop")
}

# Probability table for every (pitcher, hand, role) that appears in `score`.
baseline_probs <- function(score_keys, history, prior, kappa) {
  score_keys |>
    tidyr::crossing(pitch_group = PITCH_GROUPS) |>
    dplyr::left_join(prior, by = c("p_throws", "role", "pitch_group")) |>
    dplyr::left_join(history, by = c("pitcher", "pitch_group")) |>
    dplyr::mutate(n = dplyr::coalesce(n, 0)) |>
    dplyr::group_by(pitcher, p_throws, role) |>
    dplyr::mutate(N = sum(n),
                  prob = if (is.infinite(kappa)) m else (n + kappa * m) / (N + kappa),
                  prob = prob / sum(prob)) |>
    dplyr::ungroup()
}

# Scores a probability table against the pitches actually thrown. Works on
# counts, so it never needs one row per pitch.
score_probs <- function(probs, actual_counts) {
  joined <- actual_counts |>
    dplyr::left_join(dplyr::select(probs, pitcher, p_throws, role, pitch_group, prob),
                     by = c("pitcher", "p_throws", "role", "pitch_group"))
  top1 <- probs |>
    dplyr::group_by(pitcher, p_throws, role) |>
    dplyr::slice_max(prob, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(pitcher, p_throws, role, top_group = pitch_group)
  joined |>
    dplyr::left_join(top1, by = c("pitcher", "p_throws", "role")) |>
    dplyr::mutate(loss = -n * log(prob), hit = n * (pitch_group == top_group))
}

summarise_scores <- function(scored, ...) {
  scored |>
    dplyr::group_by(...) |>
    dplyr::summarise(pitches = sum(n), log_loss = sum(loss) / sum(n),
                     top1 = sum(hit) / sum(n), .groups = "drop")
}

# Fits on `train_seasons` and scores `score_season` for one (kappa, decay).
evaluate_baseline <- function(targets, train_seasons, score_season, kappa, decay) {
  train <- dplyr::filter(targets, game_year %in% train_seasons)
  score <- dplyr::filter(targets, game_year == score_season) |>
    dplyr::mutate(role = role_of(is_starter))
  actual <- dplyr::count(score, pitcher, p_throws, role, pitch_group)
  keys <- dplyr::distinct(actual, pitcher, p_throws, role)

  probs <- baseline_probs(keys, pitcher_history(train, season_weights(train_seasons, score_season, decay)),
                          group_prior(train), kappa)
  list(probs = probs, scored = score_probs(probs, actual))
}
