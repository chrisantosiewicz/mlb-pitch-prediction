source(file.path("..", "..", "R", "constants.R"))
source(file.path("..", "..", "R", "features.R"))
source(file.path("..", "..", "R", "boost_model.R"))
source(file.path("..", "..", "R", "report.R"))
source(file.path("..", "..", "R", "report_insights.R"))

toy_data <- function(batter_xwoba = c(FF = 0.400, SL = 0.250)) {
  groups <- names(batter_xwoba)
  list(
    players = tibble::tibble(player_id = c(1L, 2L), role = c("P", "B"), full_name = c("Ace Pitcher", "Big Hitter"),
                             team = "X", pitches = 1000, bat_side = c(NA, "R"), pitch_hand = c("R", NA),
                             primary_position = c("P", "C")),
    mix_flags = tibble::tibble(pitcher = 1L, mix_changed = FALSE, relabeled = FALSE),
    count_mix = tidyr::expand_grid(pitcher = 1L, stand = "R", count_str = FACTOR_LEVELS$count_str,
                                   pitch_group = groups) |>
      dplyr::mutate(n = ifelse(pitch_group == "FF", 30, 10)),
    arsenal = tibble::tibble(pitcher = 1L, stand = "R", pitch_group = groups, n = c(300, 100), velo = c(95, 85)),
    outcomes = dplyr::bind_rows(
      tibble::tibble(side = "batter", player_id = 2L, opp_hand = "R", pitch_group = groups,
                     pa = 100L, xwoba_shrunk = unname(batter_xwoba), league_xwoba = 0.320),
      tibble::tibble(side = "pitcher", player_id = 1L, opp_hand = "R", pitch_group = groups,
                     pa = 100L, xwoba_shrunk = 0.320, league_xwoba = 0.320))
  )
}

test_that("edge combines hitter and pitcher relative to league", {
  e <- pitch_edges(toy_data(), 1L, 2L)
  expect_equal(e$edge[e$pitch_group == "FF"], "Hitter edge")
  expect_equal(e$edge[e$pitch_group == "SL"], "Pitcher edge")
  expect_equal(e$projected[e$pitch_group == "FF"], 0.400)
})

test_that("thin samples are labeled instead of called", {
  d <- toy_data()
  d$outcomes$pa[d$outcomes$side == "batter" & d$outcomes$pitch_group == "SL"] <- 5L
  e <- pitch_edges(d, 1L, 2L)
  expect_equal(e$edge[e$pitch_group == "SL"], "Not enough data")
})

test_that("takeaways name best and worst pitch only when they really differ", {
  fp <- tibble::tibble(pitch_group = PITCH_GROUPS, model = c(0.6, 0, 0, 0.4, 0, 0, 0, 0))
  differ <- key_takeaways(toy_data(), 1L, 2L, fp)
  expect_true(any(grepl("best damage against four-seams", differ)))
  same <- key_takeaways(toy_data(c(FF = 0.330, SL = 0.320)), 1L, 2L, fp)
  expect_true(any(grepl("about equally well", same)))
})

test_that("the first-pitch takeaway reports the model's call", {
  fp <- tibble::tibble(pitch_group = PITCH_GROUPS, model = c(0.6, 0, 0, 0.4, 0, 0, 0, 0))
  out <- key_takeaways(toy_data(), 1L, 2L, fp)
  expect_true(any(grepl("First pitch: the model expects a fastball 60%", out)))
})
