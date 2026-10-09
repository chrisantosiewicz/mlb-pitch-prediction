# report_pdf.R ----------------------------------------------------------------
# The printable one-page advance report (US letter, landscape). Built from the
# same functions as the app (report.R), so the PDF and the app always agree.
# Used by the app's "Download PDF" button and by the pipeline's sample report.

KEY_COUNTS <- c("0-0", "1-0", "0-1", "2-0", "1-1", "0-2", "3-1", "2-2", "3-2")
PDF_BASE_SIZE <- 8.5

# Model call for each key count, previous pitches unknown (averaged).
key_count_table <- function(d, model, pitcher_id, batter_id, situation = DEFAULT_SITUATION) {
  purrr::map_dfr(KEY_COUNTS, function(cnt) {
    s <- utils::modifyList(situation, list(count = cnt, prev1 = "UNKNOWN", prev1_result = "UNKNOWN",
                                           prev2 = "UNKNOWN"))
    p <- predict_next_pitch(d, model, pitcher_id, batter_id, s)
    fam <- tapply(p$model, PITCH_FAMILY[p$pitch_group], sum)
    top <- p[order(-p$model), ][1:2, ]
    tibble::tibble(Count = cnt, Fastball = pct(fam[["FB"]]), Breaking = pct(fam[["BR"]]),
                   Offspeed = pct(fam[["OS"]]),
                   `Most likely` = sprintf("%s %s", PITCH_GROUP_NAMES[top$pitch_group[1]], pct(top$model[1])),
                   `Next` = sprintf("%s %s", PITCH_GROUP_NAMES[top$pitch_group[2]], pct(top$model[2])))
  })
}

pdf_table <- function(df, title, base = PDF_BASE_SIZE) {
  th <- gridExtra::ttheme_minimal(
    base_size = base - 1, padding = grid::unit(c(3, 2.2), "mm"),
    core = list(bg_params = list(fill = c("#f4f7fb", "white"), col = NA)),
    colhead = list(fg_params = list(fontface = "bold", col = "#1b4f72")))
  tg <- gridExtra::tableGrob(as.data.frame(df), rows = NULL, theme = th)
  patchwork::wrap_elements(full = tg) +
    ggplot2::labs(title = title) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = base + 1.5, colour = "#1b4f72"))
}

pdf_panel <- function(p, title, base = PDF_BASE_SIZE) {
  p + ggplot2::labs(title = title) +
    ggplot2::theme_minimal(base_size = base) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = base + 1.5, colour = "#1b4f72"),
                   plot.caption = ggplot2::element_text(colour = "grey45", size = base - 2),
                   panel.grid.minor = ggplot2::element_blank())
}

situation_text <- function(s) {
  prev <- if (s$count == "0-0") "first pitch" else if (s$prev1 == "UNKNOWN") "previous pitch unknown"
          else sprintf("after a %s (%s)", tolower(PITCH_GROUP_NAMES[[s$prev1]]),
                       if (s$prev1_result == "UNKNOWN") "result unknown" else s$prev1_result)
  sprintf("%s count, %s, %s out, runners: %s", s$count, prev, s$outs,
          ifelse(s$base_state == "___", "none", gsub("_", "-", s$base_state)))
}

build_report_page <- function(d, model, pitcher_id, batter_id, situation = DEFAULT_SITUATION) {
  m <- matchup(d, pitcher_id, batter_id)
  pred <- predict_next_pitch(d, model, pitcher_id, batter_id, situation)
  h2h <- head_to_head_summary(d, pitcher_id, batter_id)
  flags <- c(if (isTRUE(m$flags$mix_changed)) "MIX CHANGED THIS SEASON",
             if (isTRUE(m$flags$relabeled)) "PITCH RELABEL REPAIRED")

  title <- sprintf("ADVANCE REPORT  |  %s (%sHP, %s)  vs.  %s (bats %s, %s)",
                   toupper(m$pitcher$full_name), m$p_throws, m$pitcher$team,
                   toupper(m$batter$full_name), m$batter$bat_side, m$batter$team)
  subtitle <- paste0(
    sprintf("Statcast through %s  ·  mix & locations %s  ·  xwOBA %s  ·  ", d$meta$data_through,
            d$meta$report_season, paste(range(unlist(d$meta$outcome_seasons)), collapse = "-")),
    if (is.null(h2h)) "No head-to-head history"
    else sprintf("Head to head %s: %d PA, %d H, %d HR, %d K, %d BB, xwOBA %s",
                 h2h$Seasons, h2h$PA, h2h$H, h2h$HR, h2h$K, h2h$BB, h2h$xwOBA),
    if (length(flags)) paste0("  ·  ", paste(flags, collapse = "  ·  ")) else "")

  pred_panel <- pdf_panel(plot_prediction(pred, text_size = 2.6), "Predicted next pitch") +
    ggplot2::labs(subtitle = situation_text(situation)) +
    ggplot2::theme(plot.subtitle = ggplot2::element_text(size = PDF_BASE_SIZE - 1, colour = "grey30"))
  mix_panel <- pdf_panel(plot_count_mix(d, pitcher_id, m$stand, text_size = 2.4),
                         sprintf("Mix by count vs. %sHB", m$stand)) +
    ggplot2::theme(panel.grid = ggplot2::element_blank())
  key_panel <- pdf_table(key_count_table(d, model, pitcher_id, batter_id, situation), "Model by count")
  loc_panel <- pdf_panel(plot_locations(d, pitcher_id, m$stand, "All counts", max_types = 5),
                         "Where his pitches go (catcher's view)") +
    ggplot2::theme(axis.text = ggplot2::element_blank(), panel.grid = ggplot2::element_blank(),
                   strip.text = ggplot2::element_text(face = "bold", size = PDF_BASE_SIZE))
  xw_panel <- pdf_panel(plot_xwoba_by_pitch(d, pitcher_id, batter_id, text_size = 2.3),
                        "Expected outcomes by pitch type") +
    ggplot2::theme(legend.position = "top", panel.grid.major.y = ggplot2::element_blank())
  ars_panel <- pdf_table(arsenal_table(d, pitcher_id, m$stand), sprintf("Arsenal vs. %sHB", m$stand))
  plat_panel <- pdf_table(platoon_table(d, pitcher_id, batter_id), "Platoon splits")

  layout <- "
AAABBBBCCCC
DDDDDDDDDDD
EEEEFFFFGGG"
  patchwork::wrap_plots(A = pred_panel, B = mix_panel, C = key_panel, D = loc_panel,
                        E = xw_panel, F = ars_panel, G = plat_panel, design = layout,
                        heights = c(1.15, 0.8, 1)) +
    patchwork::plot_annotation(
      title = title, subtitle = subtitle,
      caption = "Next-pitch model: xgboost on 2023-25 Statcast, tested once on 2026 (log loss 1.283 vs. 1.580 for the pitcher's prior mix). Probabilities, not certainties.",
      theme = ggplot2::theme(
        plot.title = ggplot2::element_text(face = "bold", size = 13, colour = "#1b4f72"),
        plot.subtitle = ggplot2::element_text(size = 8, colour = "grey30"),
        plot.caption = ggplot2::element_text(size = 6.5, colour = "grey45")))
}

render_report_pdf <- function(d, model, pitcher_id, batter_id, file, situation = DEFAULT_SITUATION) {
  page <- build_report_page(d, model, pitcher_id, batter_id, situation)
  ggplot2::ggsave(file, page, width = 11, height = 8.5, device = grDevices::cairo_pdf)
  invisible(file)
}
