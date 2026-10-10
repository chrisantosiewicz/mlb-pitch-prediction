source(file.path("..", "..", "R", "constants.R"))
source(file.path("..", "..", "R", "features.R"))
source(file.path("..", "..", "R", "boost_model.R"))
source(file.path("..", "..", "R", "report.R"))

test_that("previous-pitch results are consistent with the count", {
  expect_equal(possible_results("0-2"), c("called", "whiff", "foul"))
  expect_equal(possible_results("2-0"), "ball")
  expect_setequal(possible_results("1-1"), c("ball", "called", "whiff", "foul"))
})

test_that("switch hitters bat from the opposite side of the pitcher", {
  expect_equal(batter_stand("S", "R"), "L")
  expect_equal(batter_stand("S", "L"), "R")
  expect_equal(batter_stand("L", "L"), "L")
})

toy_report_data <- function() {
  list(
    players = tibble::tibble(player_id = c(1L, 2L), role = c("P", "B"), full_name = c("P", "B"),
                             team = "X", pitches = 1000, bat_side = c(NA, "R"), pitch_hand = c("R", NA),
                             primary_position = c("P", "C")),
    mix_state = tibble::tibble(pitcher = 1L, stand = "R", pitch_group = PITCH_GROUPS,
                               p1 = 1 / 8, p2 = 1 / 8, p3 = c(0.6, 0, 0, 0.3, 0, 0, 0.1, 0)),
    mix_flags = tibble::tibble(pitcher = 1L, mix_changed = FALSE, relabeled = FALSE),
    prev_result_freq = tibble::tibble(count_str = "1-1", prev1_result = c("ball", "called", "whiff", "foul"),
                                      n = c(40, 30, 20, 10), share = c(0.4, 0.3, 0.2, 0.1))
  )
}

test_that("an unknown previous pitch is averaged over his own pitches with weights summing to one", {
  s <- utils::modifyList(DEFAULT_SITUATION, list(count = "1-1"))
  combos <- expand_situation(toy_report_data(), 1L, 2L, s)
  expect_setequal(unique(combos$prev1), c("FF", "SL", "CH"))
  expect_equal(sum(combos$w), 1)
})

test_that("the first pitch of an at-bat has no previous pitch", {
  combos <- expand_situation(toy_report_data(), 1L, 2L, DEFAULT_SITUATION)
  expect_equal(combos$prev1, "NONE")
})

test_that("predictions keep only his own pitches and still add to one", {
  pred <- tibble::tibble(pitch_group = PITCH_GROUPS, model = c(0.5, 0.02, 0.01, 0.3, 0.02, 0.05, 0.1, 0),
                         usual = rep(1 / 8, 8))
  out <- restrict_to_repertoire(pred, c("FF", "SL", "CH"))
  expect_equal(sum(out$model), 1)
  expect_equal(sum(out$usual), 1)
  expect_true(all(out$model[!out$pitch_group %in% c("FF", "SL", "CH")] == 0))
  expect_equal(out$model[out$pitch_group == "FF"], 0.5 / 0.9)
})
