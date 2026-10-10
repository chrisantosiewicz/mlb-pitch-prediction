# live_report.R ---------------------------------------------------------------
# Scores logged predictions against what was thrown and writes a game report.

score_logged <- function(log_tbl, pitches) {
  actual <- pitches |>
    dplyr::transmute(key = paste(at_bat, pitch_number, sep = "-"), actual, actual_code)
  probs <- log_tbl |>
    dplyr::mutate(dplyr::across(dplyr::starts_with(c("p_", "u_")), as.numeric)) |>
    dplyr::inner_join(actual, by = "key") |>
    dplyr::filter(!is.na(actual), actual != "OTHER")
  if (!nrow(probs)) return(probs)
  scored <- purrr::map_dfr(seq_len(nrow(probs)), function(i) {
    r <- probs[i, ]
    pred <- tibble::tibble(pitch_group = PITCH_GROUPS,
                           model = unlist(r[paste0("p_", PITCH_GROUPS)]),
                           usual = unlist(r[paste0("u_", PITCH_GROUPS)]))
    score_prediction(pred, r$actual)
  })
  dplyr::bind_cols(probs, scored)
}

write_live_report <- function(game_pk, feed, pitches, log_tbl) {
  s <- score_logged(log_tbl, pitches)
  dir.create("docs/live", recursive = TRUE, showWarnings = FALSE)
  if (!nrow(s)) { message("Nothing to score yet."); return(invisible(NULL)) }
  teams <- feed$gameData$teams
  title <- sprintf("%s at %s, %s", teams$away$name, teams$home$name, feed$gameData$datetime$officialDate)

  summary <- tibble::tibble(
    pitches = nrow(s),
    `predicted live` = sum(s$mode == "live"),
    `model top-1` = pct(mean(s$hit), 1), `his usual mix top-1` = pct(mean(s$hit_usual), 1),
    `model family` = pct(mean(s$family_hit), 1), `usual mix family` = pct(mean(s$family_hit_usual), 1),
    `model log loss` = sprintf("%.3f", mean(s$log_loss)), `usual mix log loss` = sprintf("%.3f", mean(s$log_loss_usual)))

  by_pitcher <- s |>
    dplyr::group_by(pitcher_name) |>
    dplyr::summarise(pitches = dplyr::n(), `model top-1` = pct(mean(hit)), `usual top-1` = pct(mean(hit_usual)),
                     `model log loss` = sprintf("%.2f", mean(log_loss)), .groups = "drop") |>
    dplyr::arrange(dplyr::desc(pitches))

  by_inning <- s |>
    dplyr::mutate(inning = as.integer(inning)) |>
    dplyr::group_by(inning) |>
    dplyr::summarise(model = mean(hit), usual = mean(hit_usual), n = dplyr::n(), .groups = "drop")
  chart <- ggplot2::ggplot(tidyr::pivot_longer(by_inning, c(model, usual), names_to = "who", values_to = "hit"),
                           ggplot2::aes(factor(inning), hit, fill = who)) +
    ggplot2::geom_col(position = "dodge", width = 0.7) +
    ggplot2::scale_fill_manual(values = c(model = "#c8102e", usual = "#9aa8b8"),
                               labels = c(model = "Model", usual = "His usual mix")) +
    ggplot2::scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
    ggplot2::labs(title = title, subtitle = "Share of pitches where the most likely pitch was the one thrown, by inning",
                  x = "Inning", y = NULL, fill = NULL) +
    ggplot2::theme_minimal(base_size = 11) + ggplot2::theme(legend.position = "top")
  chart_path <- sprintf("docs/live/%s.png", game_pk)
  ggplot2::ggsave(chart_path, chart, width = 8, height = 4.5, dpi = 150, bg = "white")

  best <- s |> dplyr::filter(hit) |> dplyr::slice_max(as.numeric(predicted_prob), n = 5, with_ties = FALSE)
  worst <- s |> dplyr::slice_max(log_loss, n = 5, with_ties = FALSE)
  calls <- function(df) df |>
    dplyr::transmute(inning = paste(half, inning), pitcher = pitcher_name, batter = batter_name, count,
                     predicted = sprintf("%s %s", PITCH_GROUP_NAMES[predicted], pct(as.numeric(predicted_prob))),
                     thrown = PITCH_GROUP_NAMES[actual])

  writeLines(c(
    sprintf("# Live test: %s", title), "",
    sprintf("*Game %s. Every prediction uses only what was known before the pitch. %d of %d predictions were logged live, before the pitch was thrown; the rest were backfilled from the pre-pitch state.*",
            game_pk, sum(s$mode == "live"), nrow(s)), "",
    md_table(summary), "",
    sprintf("![](%s.png)", game_pk), "",
    "## By pitcher", "", md_table(by_pitcher), "",
    "## Most confident correct calls", "", md_table(calls(best)), "",
    "## Biggest misses", "", md_table(calls(worst)), "",
    "*Caveat: the model was trained on regular-season games; one game is a small sample.*", ""),
    sprintf("docs/live/%s.md", game_pk))
  message(sprintf("Scored %d pitches: model top-1 %s vs usual mix %s", nrow(s), summary$`model top-1`,
                  summary$`his usual mix top-1`))
  invisible(s)
}
