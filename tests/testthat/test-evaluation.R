source(file.path("..", "..", "R", "constants.R"))
source(file.path("..", "..", "R", "context_model.R"))
source(file.path("..", "..", "R", "evaluation.R"))
source(file.path("..", "..", "R", "batter.R"))

toy_probs <- function(n, p_ff) {
  m <- matrix((1 - p_ff) / 7, nrow = n, ncol = 8, dimnames = list(NULL, PITCH_GROUPS))
  m[, "FF"] <- p_ff
  m
}

test_that("per-pitch log loss averages to the overall log loss", {
  p <- toy_probs(4, 0.5)
  y <- factor(c("FF", "SL", "FF", "CH"), levels = PITCH_GROUPS)
  expect_equal(mean(pitch_log_loss(p, y)), log_loss(p, y))
})

test_that("bootstrap interval excludes zero when one model is clearly better", {
  set.seed(1)
  y <- factor(sample(c("FF", "SL"), 2000, replace = TRUE, prob = c(0.7, 0.3)), levels = PITCH_GROUPS)
  game <- rep(1:200, each = 10)
  good <- pitch_log_loss(toy_probs(2000, 0.7), y)
  bad <- pitch_log_loss(toy_probs(2000, 0.3), y)
  b <- bootstrap_difference(good, bad, game, draws = 200)
  expect_lt(b$upper, 0)
})

test_that("a perfectly calibrated forecast has near-zero calibration error", {
  set.seed(2)
  y <- factor(ifelse(runif(20000) < 0.6, "FF", "SL"), levels = PITCH_GROUPS)
  ece <- calibration_error(calibration_table(toy_probs(20000, 0.6), y))
  expect_lt(ece$ece[ece$class == "FF"], 0.02)
})

test_that("batter tilt is zero for a hitter with no history and probabilities stay normalized", {
  hist <- tibble::tibble(batter = 1:2, game_pk = 1L, game_year = 2025L)
  for (k in PITCH_GROUPS) {
    hist[[paste0("o_", k)]] <- c(0, if (k == "ST") 30 else 10)
    hist[[paste0("e_", k)]] <- c(0, 12)
  }
  adj <- batter_adjustments(hist, tau = 100)
  expect_true(all(unlist(adj[1, paste0("badj_", PITCH_GROUPS)]) == 0))
  expect_gt(adj$badj_ST[2], 0)
  tilted <- apply_batter_tilt(toy_probs(2, 0.5), adj[paste0("badj_", PITCH_GROUPS)])
  expect_equal(as.numeric(rowSums(tilted)), c(1, 1))
})
