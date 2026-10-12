# 19_compare_live.R -----------------------------------------------------------
# Replays postseason games with the in-game model and compares with the
# original model's predictions (logged live for Game 5, replayed for Game 4).
#   Rscript pipeline/19_compare_live.R 849832 849831

suppressPackageStartupMessages(library(dplyr))
for (f in c("constants", "features", "boost_model", "report", "live", "live_report", "ingame", "cleaning_log")) {
  source(file.path("R", paste0(f, ".R")))
}
pct <- function(x, digits = 1) sprintf(paste0("%.", digits, "f%%"), 100 * x)

d <- load_report_data("app/data")
model <- xgboost::xgb.load("models/final_xgboost_ingame.ubj")
tau <- jsonlite::read_json("models/ingame_tuning.json")$tau_game

results <- purrr::map_dfr(commandArgs(trailingOnly = TRUE), function(game_pk) {
  feed <- fetch_feed(game_pk)
  pitches <- game_pitches(feed)
  old <- readr::read_csv(sprintf("data/live/%s_predictions.csv", game_pk), show_col_types = FALSE,
                         col_types = readr::cols(.default = "c")) |>
    score_logged(pitches) |>
    select(key, hit_old = hit, ll_old = log_loss, family_old = family_hit)
  new <- purrr::map_dfr(seq_len(nrow(pitches)), function(i) {
    r <- pitches[i, ]
    pred <- predict_row_ingame(d, model, r, tau)
    sc <- score_prediction(pred, r$actual)
    if (is.null(sc)) return(NULL)
    dplyr::bind_cols(tibble::tibble(key = paste(r$at_bat, r$pitch_number, sep = "-"), pitcher_name = r$pitcher_name,
                                    starter = r$starter, inning = r$inning, actual = r$actual), sc)
  })
  inner_join(new, old, by = "key") |> mutate(game = game_pk)
})

summ <- function(df) tibble(pitches = nrow(df), `original model` = pct(mean(df$hit_old)),
                            `in-game model` = pct(mean(df$hit)), `usual mix` = pct(mean(df$hit_usual)),
                            `original log loss` = sprintf("%.3f", mean(df$ll_old)),
                            `in-game log loss` = sprintf("%.3f", mean(df$log_loss)))
by_game <- results |> group_by(game) |> group_modify(~ summ(.x)) |> ungroup()
by_role <- results |> group_by(game, role = ifelse(starter, "starter", "reliever")) |> group_modify(~ summ(.x)) |> ungroup()
by_pitcher <- results |> group_by(game, pitcher_name) |> group_modify(~ summ(.x)) |> ungroup() |> arrange(game, desc(pitches))
curves <- results |> filter(actual == "CU") |> group_by(game) |>
  summarise(curveballs = n(), `original model` = pct(mean(hit_old)), `in-game model` = pct(mean(hit)), .groups = "drop")

dir.create("docs/live", showWarnings = FALSE)
writeLines(c("# In-game adaptation: postseason replays", "",
             "*Original model vs. the in-game model (adapts to what the pitcher has thrown earlier in the same game). Neither game was used in training. Pitches are predicted from their pre-pitch state only.*", "",
             "## By game", "", md_table(by_game), "",
             "## Starters vs. relievers", "", md_table(by_role), "",
             "## Curveballs", "", md_table(curves), "",
             "## By pitcher", "", md_table(by_pitcher), ""),
           "docs/live/ingame_comparison.md")
print(by_game); print(by_role); print(curves)
