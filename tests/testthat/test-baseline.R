source(file.path("..", "..", "R", "constants.R"))
source(file.path("..", "..", "R", "baseline.R"))

toy_targets <- function() {
  tibble::tibble(
    game_year = c(rep(2023L, 10), rep(2024L, 10), rep(2025L, 4)),
    pitcher = c(rep(1L, 10), rep(1L, 10), 1L, 1L, 2L, 2L),
    pitcher_name = "x",
    p_throws = "R",
    is_starter = TRUE,
    pitch_group = c(rep("FF", 10), rep("SL", 10), "FF", "SL", "FF", "CU")
  )
}

test_that("recency weights give last season 1 and decay further back", {
  w <- season_weights(2023:2024, 2025, decay = 0.5)
  expect_equal(unname(w[c("2023", "2024")]), c(0.5, 1))
})

test_that("baseline never uses the season it scores", {
  targets <- toy_targets()
  # Changing 2025 pitches must not change the 2025 probabilities.
  a <- evaluate_baseline(targets, 2023:2024, 2025, kappa = 10, decay = 0.5)$probs
  targets$pitch_group[targets$game_year == 2025] <- "CH"
  b <- evaluate_baseline(targets, 2023:2024, 2025, kappa = 10, decay = 0.5)$probs
  expect_equal(a$prob, b$prob)
})

test_that("probabilities sum to one for every pitcher", {
  probs <- evaluate_baseline(toy_targets(), 2023:2024, 2025, kappa = 10, decay = 0.5)$probs
  sums <- tapply(probs$prob, probs$pitcher, sum)
  expect_equal(as.numeric(sums), rep(1, length(sums)))
})

test_that("a pitcher with no history gets the league prior", {
  res <- evaluate_baseline(toy_targets(), 2023:2024, 2025, kappa = 10, decay = 0.5)
  newcomer <- dplyr::filter(res$probs, pitcher == 2L)
  expect_equal(newcomer$prob, newcomer$m)
})

test_that("shrinkage formula matches (n + kappa * m) / (N + kappa)", {
  res <- evaluate_baseline(toy_targets(), 2023:2024, 2025, kappa = 10, decay = 1)
  p1 <- dplyr::filter(res$probs, pitcher == 1L, pitch_group == "SL")
  expect_equal(p1$prob, (10 + 10 * p1$m) / (20 + 10))
})

test_that("unseen pitch types still get positive probability", {
  probs <- evaluate_baseline(toy_targets(), 2023:2024, 2025, kappa = 10, decay = 0.5)$probs
  expect_true(all(probs$prob > 0))
})
