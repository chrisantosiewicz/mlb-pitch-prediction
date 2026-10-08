# batter.R --------------------------------------------------------------------
# Batter layer: how pitchers attack THIS hitter compared with what their own
# mixes would predict.
#
# For every earlier pitch a batter has seen (games before this one only), we
# know what was thrown (O_k) and what the pitcher's mix layer L3 expected
# (E_k = sum of L3 probabilities). The adjustment for pitch k is
#
#   adj_k = log( (O_k + tau * q_k) / (E_k + tau * q_k) ),   q_k = E_k / E_total
#
# so a hitter who has seen 8% more sweepers than expected gets a positive
# sweeper tilt, and a hitter with little history gets almost none (tau is a
# pseudo-count of "pitches exactly as expected").

batter_history <- function(con) {
  obs <- paste0("SUM((pitch_group = '", PITCH_GROUPS, "')::INT) AS o_", PITCH_GROUPS, collapse = ",\n")
  exp <- paste0("SUM(p3_", PITCH_GROUPS, ") AS e_", PITCH_GROUPS, collapse = ",\n")
  cols <- c(paste0("o_", PITCH_GROUPS), paste0("e_", PITCH_GROUPS))
  cum <- paste0("COALESCE(SUM(", cols, ") OVER w, 0) AS ", cols, collapse = ",\n")
  DBI::dbGetQuery(con, sprintf("
    WITH per_game AS (
      SELECT batter, game_pk, game_year, MIN(game_date) AS game_date, %s, %s
      FROM read_parquet('data/features/features_*.parquet')
      GROUP BY batter, game_pk, game_year)
    SELECT batter, game_pk, game_year, %s
    FROM per_game
    WINDOW w AS (PARTITION BY batter ORDER BY game_date, game_pk
                 ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)", obs, exp, cum))
}

batter_adjustments <- function(hist, tau) {
  O <- as.matrix(hist[paste0("o_", PITCH_GROUPS)])
  E <- as.matrix(hist[paste0("e_", PITCH_GROUPS)])
  e_total <- rowSums(E)
  q <- E / pmax(e_total, 1e-9)
  adj <- log((O + tau * q + 1e-9) / (E + tau * q + 1e-9))
  adj[e_total == 0, ] <- 0
  colnames(adj) <- paste0("badj_", PITCH_GROUPS)
  dplyr::bind_cols(hist[c("batter", "game_pk", "game_year")], tibble::as_tibble(adj),
                   batter_pitches_seen = rowSums(O))
}

# Applies the tilt to a probability matrix and renormalizes.
apply_batter_tilt <- function(p8, adj) {
  out <- p8 * exp(as.matrix(adj))
  out / rowSums(out)
}
