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

# Inning-by-inning chart per game: in-game model vs. original vs. usual mix.
saveRDS(results, "data/live/ingame_comparison_results.rds")
for (g in unique(results$game)) {
  feed <- fetch_feed(g)
  teams <- feed$gameData$teams
  title <- sprintf("%s at %s, %s", teams$away$name, teams$home$name, feed$gameData$datetime$officialDate)
  by_inning <- results |>
    dplyr::filter(game == g) |>
    dplyr::mutate(inning = as.integer(inning)) |>
    dplyr::group_by(inning) |>
    dplyr::summarise(`In-game model` = mean(hit), `Original model` = mean(hit_old), `His usual mix` = mean(hit_usual),
                     n = dplyr::n(), .groups = "drop") |>
    tidyr::pivot_longer(c(`In-game model`, `Original model`, `His usual mix`), names_to = "who", values_to = "hit") |>
    dplyr::mutate(who = factor(who, levels = c("In-game model", "Original model", "His usual mix")))
  overall <- results |> dplyr::filter(game == g) |>
    dplyr::summarise(a = mean(hit), b = mean(hit_old), c = mean(hit_usual))
  chart <- ggplot2::ggplot(by_inning, ggplot2::aes(factor(inning), hit, fill = who)) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.8), width = 0.75) +
    ggplot2::scale_fill_manual(values = c("In-game model" = "#c8102e", "Original model" = "#0b2545",
                                          "His usual mix" = "#9aa8b8")) +
    ggplot2::scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
    ggplot2::labs(title = title,
                  subtitle = sprintf("Exact pitch called right, by inning. Whole game: in-game model %s, original %s, usual mix %s",
                                     pct(overall$a), pct(overall$b), pct(overall$c)),
                  x = "Inning", y = NULL, fill = NULL) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(legend.position = "top", plot.title = ggplot2::element_text(face = "bold", colour = "#0b2545"),
                   panel.grid.major.x = ggplot2::element_blank())
  ggplot2::ggsave(sprintf("docs/live/%s_ingame.png", g), chart, width = 9, height = 5, dpi = 150, bg = "white")
}
