source(file.path("..", "..", "R", "constants.R"))
source(file.path("..", "..", "R", "mixes.R"))

# One pitcher whose slider (history) has vanished this season while a "sweeper"
# with nearly identical velocity and movement has appeared.
toy_history <- function() {
  tibble::tibble(
    pitcher = 1L,
    pitch_group = c("FF", "SL", "ST"),
    n = c(600, 400, 0),
    velo = c(95, 85, NA), pfx_x = c(-0.8, 0.9, NA), pfx_z = c(1.3, 0.2, NA)
  )
}
toy_std <- function(st_velo = 85.5) {
  tibble::tibble(
    pitcher = 1L, game_pk = 10L,
    pitch_group = c("FF", "SL", "ST"),
    std_n = c(60, 0, 40),
    std_n_velo = c(60, 0, 40), std_sum_velo = c(60 * 95, NA, 40 * st_velo),
    std_n_move = c(60, 0, 40), std_sum_pfx_x = c(60 * -0.8, NA, 40 * 0.95),
    std_sum_pfx_z = c(60 * 1.3, NA, 40 * 0.22)
  )
}

test_that("a vanished pitch is matched to a physically identical new label", {
  r <- detect_relabels(toy_history(), toy_std())
  expect_equal(nrow(r), 1)
  expect_equal(r$from_group, "SL")
  expect_equal(r$to_group, "ST")
})

test_that("a genuinely different new pitch is not treated as a relabel", {
  r <- detect_relabels(toy_history(), toy_std(st_velo = 80))  # 5 mph slower
  expect_equal(nrow(r), 0)
})

test_that("no relabel is declared before enough pitches this season", {
  std <- toy_std()
  std$std_n <- c(15, 0, 10)
  expect_equal(nrow(detect_relabels(toy_history(), std)), 0)
})

test_that("applying a relabel moves the old label's history to the new one", {
  hist <- tibble::tibble(pitcher = 1L, game_pk = 10L, pitch_group = c("FF", "SL", "ST"),
                         h_n = c(600, 400, 0))
  rel <- tibble::tibble(pitcher = 1L, game_pk = 10L, from_group = "SL", to_group = "ST")
  out <- apply_relabels(hist, rel)
  expect_equal(out$h_n[out$pitch_group == "SL"], 0)
  expect_equal(out$h_n[out$pitch_group == "ST"], 400)
  expect_equal(sum(out$h_n), 1000)
})

test_that("shrinkage moves a thin sample most of the way to the target", {
  expect_equal(shrink(n = 1, N = 1, kappa = 99, target = 0.5), 0.505)
  expect_equal(shrink(n = 900, N = 1000, kappa = 0, target = 0.5), 0.9)
})
