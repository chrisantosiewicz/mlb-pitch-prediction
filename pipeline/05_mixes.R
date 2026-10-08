# 05_mixes.R ------------------------------------------------------------------
# Tunes the pitcher-mix layers on 2025, then builds them for every model season.
#   L1 prior mix (Phase 1 baseline settings), L2 current form, L3 + platoon tilt
# Writes models/mixes.json, data/features/mixes_<season>.parquet,
# data/features/mix_flags_<season>.parquet and docs/mix_results.md.

suppressPackageStartupMessages(library(dplyr))
source("R/constants.R")
source("R/clean.R")
source("R/cleaning_log.R")   # md_table()
source("R/mixes.R")

TUNE_SEASON <- 2025
TAU_STD_GRID <- c(5, 10, 25, 50, 100)
TAU_HAND_GRID <- c(100, 200, 400, 800, 1600)

baseline <- jsonlite::read_json("models/baseline.json")
con <- connect_duckdb()
parts <- load_mix_parts(con, MODEL_SEASONS)
actual <- actual_counts(con, TUNE_SEASON)
message("Loaded mix building blocks")

params_for <- function(tau_std, tau_hand, relabel = TRUE) {
  list(decay = baseline$decay, kappa = baseline$kappa,
       tau_std = tau_std, tau_hand = tau_hand, relabel = relabel)
}

# Tune L2 (tau_std) and L3 (tau_hand) on the tuning season.
grid <- tidyr::crossing(tau_std = TAU_STD_GRID, tau_hand = TAU_HAND_GRID)
grid$log_loss <- purrr::pmap_dbl(grid, function(tau_std, tau_hand) {
  m <- build_mixes(parts, TUNE_SEASON, params_for(tau_std, tau_hand))$mixes
  score_mix(m, actual, "p3")$log_loss
})
best <- slice_min(grid, log_loss, n = 1)
params <- params_for(best$tau_std, best$tau_hand)
message(sprintf("Best: tau_std = %s, tau_hand = %s", best$tau_std, best$tau_hand))

# The ladder on the tuning season, with and without relabel repair.
with_fix <- build_mixes(parts, TUNE_SEASON, params)
without_fix <- build_mixes(parts, TUNE_SEASON, modifyList(params, list(relabel = FALSE)))
ladder_row <- function(run, col, label) {
  bind_cols(tibble(layer = label), score_mix(run$mixes, actual, col),
            top1_mix(run$mixes, actual, col), score_mix_family(run$mixes, actual, col))
}
ladder <- bind_rows(
  ladder_row(without_fix, "p1", "L1 prior mix (Phase 1 baseline)"),
  ladder_row(with_fix, "p1", "L1 prior mix + relabel repair"),
  ladder_row(with_fix, "p2", "L2 + current form (season to date)"),
  ladder_row(with_fix, "p3", "L3 + platoon tilt vs. batter hand")
)

# Where relabel repair matters: pitches by pitcher-games that had a relabel.
relabeled_games <- distinct(with_fix$relabels, pitcher, game_pk)
relabel_effect <- bind_rows(
  score_mix(semi_join(without_fix$mixes, relabeled_games, by = c("pitcher", "game_pk")),
            semi_join(actual, relabeled_games, by = c("pitcher", "game_pk")), "p1") |>
    mutate(version = "L1 without repair"),
  score_mix(semi_join(with_fix$mixes, relabeled_games, by = c("pitcher", "game_pk")),
            semi_join(actual, relabeled_games, by = c("pitcher", "game_pk")), "p1") |>
    mutate(version = "L1 with repair")
)

names_lu <- DBI::dbGetQuery(con, sprintf(
  "SELECT DISTINCT pitcher, pitcher_name FROM %s WHERE game_year = %d", CLEAN_GLOB, TUNE_SEASON))
relabel_pitchers <- with_fix$relabels |>
  group_by(pitcher, from_group, to_group) |>
  summarise(games = n(), velo_diff = round(mean(velo_diff), 1),
            move_diff_in = round(12 * mean(move_diff), 1), .groups = "drop") |>
  left_join(names_lu, by = "pitcher") |>
  arrange(desc(games)) |>
  select(pitcher_name, from_group, to_group, games, velo_diff, move_diff_in)

flags <- with_fix$flags
flag_summary <- tibble(
  `pitcher-games` = nrow(flags),
  `with 50+ pitches so far` = sum(flags$std_total >= MIX_CHANGE_MIN_PITCHES),
  `flagged mix change` = sum(flags$mix_changed),
  `relabel repaired` = sum(flags$relabeled)
)

# Build and save every model season with the tuned settings.
dir.create("data/features", recursive = TRUE, showWarnings = FALSE)
for (s in MODEL_SEASONS) {
  run <- if (s == TUNE_SEASON) with_fix else build_mixes(parts, s, params)
  arrow::write_parquet(run$mixes, sprintf("data/features/mixes_%d.parquet", s))
  arrow::write_parquet(run$flags, sprintf("data/features/mix_flags_%d.parquet", s))
  message("Mixes built for ", s)
}
DBI::dbDisconnect(con, shutdown = TRUE)

jsonlite::write_json(c(params, list(
  mix_change = list(min_pitches = MIX_CHANGE_MIN_PITCHES, p_value = MIX_CHANGE_P_VALUE, min_tvd = MIX_CHANGE_MIN_TVD),
  relabel_rules = list(min_hist_share = RELABEL_MIN_HIST_SHARE, max_new_hist_share = RELABEL_MAX_NEW_HIST_SHARE,
                       min_std_pitches = RELABEL_MIN_STD_PITCHES, min_new_share = RELABEL_MIN_NEW_SHARE,
                       max_velo_diff_mph = RELABEL_MAX_VELO_DIFF, max_move_diff_in = 12 * RELABEL_MAX_MOVE_DIFF),
  tuned_on = TUNE_SEASON, created = as.character(Sys.time()))),
  "models/mixes.json", auto_unbox = TRUE, pretty = TRUE)

fmt <- function(df) mutate(df,
  across(any_of(c("log_loss", "family_log_loss")), ~ sprintf("%.3f", .x)),
  across(any_of(c("top1")), ~ sprintf("%.1f%%", 100 * .x)))

grid_table <- grid |>
  mutate(log_loss = sprintf("%.4f", log_loss)) |>
  tidyr::pivot_wider(names_from = tau_hand, values_from = log_loss, names_prefix = "tau_hand ")

writeLines(c(
  "# Pitcher-mix layers (tuning season)",
  "",
  sprintf("*Generated by `pipeline/05_mixes.R` on %s. Scored on %s pitches using only earlier games.*", Sys.Date(), TUNE_SEASON),
  "",
  "Each layer is a pitch-mix estimate for one pitcher, in one game, against one batter hand. None of them looks at the count or the situation: that's the job of the context model in `logistic_results.md`.",
  "",
  "## The ladder",
  "",
  md_table(fmt(ladder)),
  "",
  "*Family log loss and accuracy collapse the 8 pitches into fastball (FF, SI, FC), breaking (SL, ST, CU) and offspeed (CH, FS).*",
  "",
  sprintf("Tuned settings: current form starts from **%s pitches' worth** of his prior mix (tau_std), and the platoon tilt starts from **%s pitches' worth** of his overall mix (tau_hand).",
          best$tau_std, best$tau_hand),
  "",
  "## Relabel repair",
  "",
  "A relabel is detected before a game when a pitch that was at least 5% of his history has not appeared this season (30+ pitches in), while a pitch he almost never threw (under 2%) now makes up 5%+, and the two have nearly the same velocity (within 2 mph) and movement (within 4 inches). His history of the old label is then credited to the new one. Only earlier games are used.",
  "",
  md_table(flag_summary),
  "",
  "Effect on the pitcher-games where a relabel was repaired:",
  "",
  md_table(fmt(relabel_effect)),
  "",
  "Pitchers repaired most often:",
  "",
  md_table(utils::head(relabel_pitchers, 20)),
  "",
  "## Mix-change flag",
  "",
  sprintf("A pitcher-game is flagged when he has an established history (%d+ weighted pitches) and his season-to-date mix (%d+ pitches) is both statistically inconsistent with his prior mix (G-test, p < %s) and meaningfully different (at least %d%% of his pitches moved to other types). The flag is a model input and is shown in the app.", MIX_CHANGE_MIN_HISTORY, MIX_CHANGE_MIN_PITCHES, MIX_CHANGE_P_VALUE, round(100 * MIX_CHANGE_MIN_TVD)),
  "",
  "## Tuning grid (log loss of L3)",
  "",
  md_table(grid_table),
  ""
), "docs/mix_results.md")
message("Wrote docs/mix_results.md")
