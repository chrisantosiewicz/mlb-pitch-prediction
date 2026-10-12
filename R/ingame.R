# ingame.R --------------------------------------------------------------------
# In-game layer: the pitcher's mix updated with what he has thrown so far in
# this game. Starts from his usual mix (L3) and moves toward today's mix as
# pitches accumulate:
#
#   p_game_k = (today_k + tau_game * p3_k) / (today_total + tau_game)
#
# tau_game is "how many pitches of his usual mix today's evidence has to
# outweigh", tuned on 2025.

INGAME_GROUPS <- function(prefix) paste0(prefix, PITCH_GROUPS)

load_ingame <- function(seasons) {
  dplyr::bind_rows(lapply(seasons, function(s) arrow::read_parquet(sprintf("data/features/ingame_%d.parquet", s))))
}

ingame_mix <- function(df, tau_game) {
  p3 <- as.matrix(df[INGAME_GROUPS("p3_")])
  today <- as.matrix(df[INGAME_GROUPS("gtd_")])
  out <- if (is.infinite(tau_game)) p3 else (today + tau_game * p3) / (rowSums(today) + tau_game)
  colnames(out) <- PITCH_GROUPS
  out
}

# Extra tree inputs: today's share of each pitch vs. his usual share, overall
# and over his last 15 pitches, plus how many pitches he's thrown today.
ingame_features <- function(df) {
  p3 <- as.matrix(df[INGAME_GROUPS("p3_")])
  today <- as.matrix(df[INGAME_GROUPS("gtd_")])
  recent <- as.matrix(df[INGAME_GROUPS("rec_")])
  n_today <- rowSums(today); n_recent <- rowSums(recent)
  tilt <- today / pmax(n_today, 1) - p3
  tilt[n_today == 0, ] <- 0
  rtilt <- recent / pmax(n_recent, 1) - p3
  rtilt[n_recent == 0, ] <- 0
  colnames(tilt) <- paste0("tilt_", PITCH_GROUPS)
  colnames(rtilt) <- paste0("rtilt_", PITCH_GROUPS)
  cbind(tilt, rtilt, today_n = n_today)
}

# Live/replay prediction with the in-game model. `r` is one pre-pitch row from
# game_pitches() (it carries gtd_* and rec_* counts); same averaging over
# unknown earlier pitches as predict_next_pitch().
predict_row_ingame <- function(d, model, r, tau_game) {
  known <- r$pitcher %in% d$players$player_id[d$players$role == "P"] &&
    r$batter %in% d$players$player_id[d$players$role == "B"]
  if (!known) return(NULL)
  s <- situation_from_row(r)
  combos <- expand_situation(d, r$pitcher, r$batter, s)
  base <- situation_row(d, r$pitcher, r$batter,
                        utils::modifyList(s, list(prev1 = combos$prev1[1], prev1_result = combos$prev1_result[1],
                                                  prev2 = combos$prev2[1])))
  for (k in PITCH_GROUPS) {
    base[[paste0("gtd_", k)]] <- r[[paste0("gtd_", k)]]
    base[[paste0("rec_", k)]] <- r[[paste0("rec_", k)]]
  }
  rows <- base[rep(1, nrow(combos)), ]
  rows$prev1_group <- combos$prev1; rows$prev1_result <- combos$prev1_result; rows$prev2_group <- combos$prev2
  rows <- prepare_factors(dplyr::mutate(rows, dplyr::across(c(prev1_group, prev1_result, prev2_group), as.character)))
  offset <- log(pmax(ingame_mix(rows, tau_game), 1e-6)) + as.matrix(rows[paste0("badj_", PITCH_GROUPS)])
  x <- cbind(boost_matrix(rows), Matrix::Matrix(ingame_features(rows), sparse = TRUE))
  dm <- xgboost::xgb.DMatrix(x, base_margin = offset)
  p <- predict_boost(model, dm)
  w <- combos$w / sum(combos$w)
  tibble::tibble(pitch_group = PITCH_GROUPS, model = as.numeric(colSums(p * w)),
                 usual = as.numeric(as.matrix(rows[1, paste0("p3_", PITCH_GROUPS)])))
}
