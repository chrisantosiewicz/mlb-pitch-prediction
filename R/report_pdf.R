# report_pdf.R ----------------------------------------------------------------
# The printable advance report: two portrait pages in one PDF.
#   Page 1 "The Game Plan": for any fan, readable in 30 seconds.
#   Page 2 "The Detail":    everything an analyst wants.
# Built from the same functions as the app (report.R, report_insights.R), so
# the PDF and the app always agree.

NAVY <- "#0b2545"
EDGE_COLORS <- c("Pitcher edge" = "#3661ad", "Even" = "#b4b4b4", "Hitter edge" = "#d82129",
                 "Not enough data" = "#e9ecef")
BASE <- 10   # base font size for the PDF (pt)

section_theme <- function(base = BASE) {
  ggplot2::theme_minimal(base_size = base) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = base + 3, colour = NAVY),
                   plot.subtitle = ggplot2::element_text(size = base, colour = "grey30"),
                   plot.caption = ggplot2::element_text(size = base - 2, colour = "grey45", hjust = 0),
                   plot.title.position = "plot", plot.caption.position = "plot",
                   panel.grid.minor = ggplot2::element_blank())
}

titled <- function(p, title, subtitle = NULL, caption = ggplot2::waiver()) {
  p + ggplot2::labs(title = title, subtitle = subtitle, caption = caption) + section_theme()
}

# Title drawn as part of the grob, so it can never overlap the body.
with_title <- function(body, title, extra = NULL) {
  top <- if (is.null(title)) NULL else
    grid::textGrob(title, x = 0, hjust = 0, gp = grid::gpar(fontsize = BASE + 3, fontface = "bold", col = NAVY))
  bottom <- if (is.null(extra)) NULL else
    grid::textGrob(extra, x = 0, hjust = 0, gp = grid::gpar(fontsize = BASE - 2, col = "grey45"))
  patchwork::wrap_elements(full = gridExtra::arrangeGrob(body, top = top, bottom = bottom,
                                                         padding = grid::unit(0.6, "line")))
}

text_panel <- function(lines, title = NULL, size = BASE + 0.5, bullet = TRUE, width = 105, extra = NULL) {
  wrapped <- vapply(lines, function(l) paste(strwrap(l, width = width), collapse = "\n   "), character(1))
  label <- paste0(if (bullet) "•  " else "", wrapped, collapse = "\n")
  g <- grid::textGrob(label, x = 0.01, y = 0.98, hjust = 0, vjust = 1,
                      gp = grid::gpar(fontsize = size, lineheight = 1.3, col = "#1d2733"))
  with_title(g, title, extra)
}

table_panel <- function(df, title, size = BASE - 1) {
  th <- gridExtra::ttheme_minimal(
    base_size = size, padding = grid::unit(c(3.2, 2), "mm"),
    core = list(bg_params = list(fill = c("#f4f7fb", "white"), col = NA)),
    colhead = list(fg_params = list(fontface = "bold", col = NAVY)))
  tg <- gridExtra::tableGrob(as.data.frame(df), rows = NULL, theme = th)
  # The title becomes the table's own first row, so the table's left edge sits
  # exactly under where the title text starts; the whole block hugs the left
  # and top of its cell.
  title_grob <- grid::textGrob(title, x = 0, hjust = 0,
                               gp = grid::gpar(fontsize = BASE + 3, fontface = "bold", col = NAVY))
  tg <- gtable::gtable_add_rows(tg, grid::unit(1.5, "line"), pos = 0)
  tg <- gtable::gtable_add_grob(tg, title_grob, t = 1, l = 1, r = ncol(tg), clip = "off")
  tg$vp <- grid::viewport(x = 0, y = 1, just = c("left", "top"),
                          width = sum(tg$widths), height = sum(tg$heights))
  patchwork::wrap_elements(full = tg)
}

# Head-to-head box shown beside the takeaways on page 1.
h2h_box <- function(h2h) {
  lines <- if (is.null(h2h)) "No head-to-head history" else c(
    sprintf("%d PA  (%s)", h2h$PA, h2h$Seasons),
    sprintf("%d H  ·  %d HR", h2h$H, h2h$HR),
    sprintf("%d K  ·  %d BB", h2h$K, h2h$BB),
    sprintf("xwOBA %s", h2h$xwOBA))
  # Geometry in points: the title's midline sits exactly halfway between the
  # top of the box and the top of the first stats line.
  n <- length(lines)
  body_size <- BASE + 1
  line_pt <- body_size * 1.4
  title_gap <- 48                      # box top -> top of first stats line
  bottom_pad <- 14
  box_pt <- title_gap + n * line_pt + bottom_pad
  pt <- function(x) grid::unit(x, "pt")
  top <- grid::unit(0.5, "npc") + pt(box_pt / 2)
  g <- grid::gTree(children = grid::gList(
    grid::roundrectGrob(width = grid::unit(0.92, "npc"), height = pt(box_pt), r = pt(4),
                        gp = grid::gpar(fill = NAVY, col = NA)),
    grid::textGrob("HEAD TO HEAD", y = top - pt(title_gap / 2), vjust = 0.5,
                   gp = grid::gpar(fontsize = BASE + 4, fontface = "bold", col = "white")),
    grid::textGrob(paste(lines, collapse = "\n"), y = top - pt(title_gap), vjust = 1,
                   gp = grid::gpar(fontsize = body_size, col = "white", lineheight = 1.4))))
  patchwork::wrap_elements(full = g)
}

# ---- page 1 pieces ----

plot_situations <- function(sm) {
  sm <- dplyr::mutate(sm,
    situation = factor(situation, levels = rev(names(SITUATIONS))),
    family = factor(family, levels = rev(PITCH_FAMILIES)),
    label = ifelse(!is.na(share) & share >= 0.08, pct(share), ""))
  side <- dplyr::distinct(sm, situation, total, top_pitch, top_share) |>
    dplyr::mutate(note = ifelse(total < MIN_SITUATION_PITCHES, "Small sample",
                                sprintf("Top pitch:\n%s %s", PITCH_GROUP_NAMES[top_pitch], pct(top_share))))
  sizes <- stats::setNames(sprintf("%s\n%d pitches", side$situation, side$total), side$situation)
  ggplot2::ggplot(sm, ggplot2::aes(share, situation, fill = family)) +
    ggplot2::geom_col(width = 0.62) +
    ggplot2::geom_text(ggplot2::aes(label = label), position = ggplot2::position_stack(vjust = 0.5),
                       colour = "white", size = 3.4, fontface = "bold") +
    ggplot2::geom_text(data = side, ggplot2::aes(x = 1.02, y = situation, label = note), inherit.aes = FALSE,
                       hjust = 0, size = 3, colour = "grey30") +
    ggplot2::scale_fill_manual(values = FAMILY_COLORS, labels = PITCH_FAMILY_NAMES,
                               breaks = PITCH_FAMILIES) +
    ggplot2::scale_x_continuous(limits = c(0, 1.55), breaks = NULL, expand = c(0, 0)) +
    ggplot2::scale_y_discrete(labels = sizes) +
    ggplot2::labs(x = NULL, y = NULL, fill = NULL) +
    ggplot2::theme(legend.position = "top", legend.justification = "left", panel.grid = ggplot2::element_blank())
}

plot_edges <- function(edges) {
  df <- edges |>
    dplyr::mutate(pitch = factor(PITCH_GROUP_NAMES[pitch_group], levels = rev(PITCH_GROUP_NAMES[pitch_group])),
                  edge = factor(edge, levels = names(EDGE_COLORS)),
                  edge_label = ifelse(edge == "Not enough data", "Not enough data yet",
                                      sprintf("%s: projected %s vs. %s avg", edge, woba_fmt(projected),
                                              woba_fmt(league_xwoba))),
                  facts = sprintf("%s of pitches  ·  %.1f mph", pct(usage), velo))
  ggplot2::ggplot(df, ggplot2::aes(y = pitch)) +
    ggplot2::geom_point(ggplot2::aes(x = 0, colour = pitch_group), size = 4.5) +
    ggplot2::geom_text(ggplot2::aes(x = 0.15, label = pitch), hjust = 0, fontface = "bold", size = 3.6) +
    ggplot2::geom_text(ggplot2::aes(x = 1.45, label = facts), hjust = 0, size = 3.3, colour = "grey30") +
    ggplot2::geom_tile(ggplot2::aes(x = 4.15, fill = edge), width = 2.5, height = 0.78) +
    ggplot2::geom_text(ggplot2::aes(x = 4.15, label = edge_label,
                                    colour = I(ifelse(edge %in% c("Even", "Not enough data"), "#1d2733", "white"))),
                       size = 3.1) +
    ggplot2::scale_colour_manual(values = PITCH_COLORS, guide = "none") +
    ggplot2::scale_fill_manual(values = EDGE_COLORS, guide = "none", drop = FALSE) +
    ggplot2::scale_x_continuous(limits = c(-0.2, 5.45), expand = c(0, 0)) +
    ggplot2::labs(x = NULL, y = NULL) +
    ggplot2::theme_void(base_size = BASE)
}

# ---- page 2 pieces ----

plot_percentiles <- function(rows) {
  if (!nrow(rows)) return(ggplot2::ggplot() + ggplot2::annotate("text", x = 0, y = 0, size = 3.2,
                                                                label = "Not enough PA for percentile rankings") +
                            ggplot2::theme_void())
  rows <- dplyr::mutate(rows, metric = factor(metric, levels = rev(metric)), col = percentile_color(pctl))
  ggplot2::ggplot(rows, ggplot2::aes(y = metric)) +
    ggplot2::geom_segment(ggplot2::aes(x = 0, xend = 100, yend = metric), colour = "#e3e7ec", linewidth = 2.2,
                          lineend = "round") +
    ggplot2::geom_segment(ggplot2::aes(x = 0, xend = pctl, yend = metric, colour = I(col)), linewidth = 2.2,
                          alpha = 0.55, lineend = "round") +
    ggplot2::geom_point(ggplot2::aes(x = pctl, fill = I(col)), shape = 21, colour = "white", size = 6.5, stroke = 1) +
    ggplot2::geom_text(ggplot2::aes(x = pctl, label = pctl), colour = "white", size = 2.6, fontface = "bold") +
    ggplot2::geom_text(ggplot2::aes(x = 108, label = value), hjust = 0, size = 3, colour = "grey30") +
    ggplot2::scale_x_continuous(limits = c(-4, 125), breaks = NULL) +
    ggplot2::labs(x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_size = BASE) +
    ggplot2::theme(panel.grid = ggplot2::element_blank(), axis.text.y = ggplot2::element_text(face = "bold"))
}

plot_model_by_count <- function(probs) {
  df <- probs |>
    dplyr::mutate(family = factor(PITCH_FAMILY[pitch_group], levels = rev(PITCH_FAMILIES))) |>
    dplyr::group_by(count, family) |>
    dplyr::summarise(p = sum(model), .groups = "drop") |>
    dplyr::mutate(count = factor(count, levels = rev(KEY_COUNTS)))
  ggplot2::ggplot(df, ggplot2::aes(p, count, fill = family)) +
    ggplot2::geom_col(width = 0.7) +
    ggplot2::geom_text(ggplot2::aes(label = ifelse(p >= 0.1, pct(p), "")),
                       position = ggplot2::position_stack(vjust = 0.5), colour = "white", size = 2.8) +
    ggplot2::scale_fill_manual(values = FAMILY_COLORS, labels = PITCH_FAMILY_NAMES, breaks = PITCH_FAMILIES) +
    ggplot2::scale_x_continuous(labels = scales::percent, expand = c(0, 0)) +
    ggplot2::labs(x = NULL, y = "Count", fill = NULL) +
    ggplot2::theme(legend.position = "top", legend.justification = "left",
                   panel.grid.major.y = ggplot2::element_blank())
}

GLOSSARY <- c(
  "xwOBA: damage a hitter does, from quality of contact, walks and strikeouts (league about .320, elite .400). Whiff%: misses per swing. Chase%: swings at pitches outside the zone. Break: movement in inches vs. a spinless pitch. Percentiles: vs. all players with 150+ PA in 2025-26; red = better.",
  "The model: gradient boosting trained on 2023-25 Statcast, tested once on all of 2026. It starts from the pitcher's own mix and learns how count, previous pitches and matchup shift it. When it says 40%, that pitch came about 40% of the time in testing. Probabilities, not certainties."
)

situation_text <- function(s) {
  prev <- if (s$count == "0-0") "first pitch of the at-bat" else if (s$prev1 == "UNKNOWN") "earlier pitches unknown"
          else sprintf("after a %s (%s)", tolower(PITCH_GROUP_NAMES[[s$prev1]]),
                       if (s$prev1_result == "UNKNOWN") "result unknown" else RESULT_TEXT[[s$prev1_result]])
  sprintf("%s count, %s", s$count, prev)
}
RESULT_TEXT <- c(ball = "ball", called = "called strike", whiff = "swing and miss", foul = "foul")

# ---- pages ----

build_page1 <- function(d, model, pitcher_id, batter_id, situation, first_pitch) {
  m <- matchup(d, pitcher_id, batter_id)
  pred <- predict_next_pitch(d, model, pitcher_id, batter_id, situation)
  fam <- tapply(pred$model, PITCH_FAMILY[pred$pitch_group], sum)
  h2h <- head_to_head_summary(d, pitcher_id, batter_id)
  flags <- c(if (isTRUE(m$flags$mix_changed)) "His pitch mix has changed a lot this season.",
             if (isTRUE(m$flags$relabeled)) "One of his pitches was relabeled by Statcast this season.")
  keys <- text_panel(c(key_takeaways(d, pitcher_id, batter_id, first_pitch), flags),
                     title = "Three things to know", width = 74, size = BASE)
  h2h_panel <- h2h_box(h2h)
  pred_panel <- titled(plot_prediction(pred, text_size = 3.3), sprintf("If it's %s...", situation$count),
                       subtitle = sprintf("Fastball %s · Breaking %s · Offspeed %s", pct(fam[["FB"]]),
                                          pct(fam[["BR"]]), pct(fam[["OS"]])),
                       caption = paste0(situation_text(situation),
                                        ". Bar = model; tick = his usual mix vs. this side.")) +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank())
  sit_panel <- titled(plot_situations(situation_mix(d, pitcher_id, m$stand)), "What he throws when...",
                      subtitle = sprintf("2026, vs. %s", hand_word(m$stand))) +
    ggplot2::theme(legend.position = "top", legend.justification = "left", panel.grid = ggplot2::element_blank(),
                   axis.text.y = ggplot2::element_text(face = "bold", size = BASE))
  edge_panel <- titled(plot_edges(pitch_edges(d, pitcher_id, batter_id)), "Pitch-by-pitch edge",
                       subtitle = sprintf("Combines how %s hits each pitch type and how %s's version of it performs (2025-26 xwOBA)",
                                          sub(".* ", "", m$batter$full_name), sub(".* ", "", m$pitcher$full_name))) +
    ggplot2::theme(panel.grid = ggplot2::element_blank(), axis.text = ggplot2::element_blank())
  loc_panel <- titled(plot_locations(d, pitcher_id, m$stand, "All counts", max_types = 3),
                      "Where his top three pitches go",
                      caption = "Catcher's view. Darker = more pitches. Public data shows where the ball ended up, not where the catcher set up.") +
    ggplot2::theme(axis.text = ggplot2::element_blank(), panel.grid = ggplot2::element_blank(),
                   strip.text = ggplot2::element_text(face = "bold", size = BASE))

  # 10 columns: the takeaways take 6, the head-to-head box 4.
  design <- "
AAAAAAHHHH
BBBBBCCCCC
DDDDDDDDDD
EEEEEEEEEE"
  patchwork::wrap_plots(A = keys, H = h2h_panel, B = pred_panel, C = sit_panel, D = edge_panel, E = loc_panel,
                        design = design, heights = c(1.1, 1.2, 0.95, 1.05)) +
    patchwork::plot_annotation(
      title = sprintf("%s  vs.  %s", m$pitcher$full_name, m$batter$full_name),
      subtitle = sprintf("THE GAME PLAN  ·  %sHP, %s  vs.  bats %s, %s  ·  Statcast through %s",
                         m$p_throws, m$pitcher$team, m$batter$bat_side, m$batter$team, d$meta$data_through),
      theme = ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = 22, colour = NAVY),
                             plot.subtitle = ggplot2::element_text(size = BASE, colour = "#c8102e", face = "bold")))
}

build_page2 <- function(d, model, pitcher_id, batter_id, situation, probs) {
  m <- matchup(d, pitcher_id, batter_id)
  pc <- percentile_rankings(d)
  p_pct <- titled(plot_percentiles(dplyr::filter(pc$pitcher, player_id == pitcher_id)),
                  paste(m$pitcher$full_name, "percentiles"))
  b_pct <- titled(plot_percentiles(dplyr::filter(pc$batter, player_id == batter_id)),
                  paste(m$batter$full_name, "percentiles"))
  mix_panel <- titled(plot_count_mix(d, pitcher_id, m$stand, text_size = 2.5, min_n = 30),
                      sprintf("Actual mix by count vs. %sHB, 2026", m$stand),
                      caption = "Faded rows: fewer than 30 pitches. Right column: pitches in that count.") +
    ggplot2::theme(axis.text.x = ggplot2::element_text(size = BASE - 2.5)) +
    ggplot2::theme(panel.grid = ggplot2::element_blank())
  model_panel <- titled(plot_model_by_count(probs), "Model by count",
                        caption = "Earlier pitches unknown, averaged over his usual mix.")
  loc_panel <- titled(plot_locations(d, pitcher_id, m$stand, "All counts", max_types = 6, short_labels = TRUE),
                      "All pitch locations", caption = NULL) +
    ggplot2::theme(axis.text = ggplot2::element_blank(), panel.grid = ggplot2::element_blank(),
                   strip.text = ggplot2::element_text(face = "bold", size = BASE - 1.5))
  xw_panel <- titled(plot_xwoba_by_pitch(d, pitcher_id, batter_id, text_size = 2.7, compact = TRUE),
                     "Expected outcomes by pitch type") +
    ggplot2::theme(legend.position = "right", panel.grid.major.y = ggplot2::element_blank(),
                   legend.text = ggplot2::element_text(size = BASE - 1))
  ars <- arsenal_table(d, pitcher_id, m$stand) |>
    dplyr::rename(`H-brk` = `H-brk"`, `V-brk` = `V-brk"`, Whiff = `Whiff%`, Chase = `Chase%`, N = Pitches)
  ars_panel <- table_panel(ars, sprintf("Arsenal vs. %sHB", m$stand), size = BASE - 2.5)
  plat <- platoon_table(d, pitcher_id, batter_id) |> dplyr::mutate(Player = sub(".* ", "", Player))
  plat_panel <- table_panel(plat, "Platoon splits (2025-26)", size = BASE - 2.5)
  gloss <- text_panel(GLOSSARY, title = "How to read this", size = BASE - 2.5, width = 150)

  # 20 columns so the two tables can share a row at different widths.
  design <- "
AAAAAAAAAABBBBBBBBBB
CCCCCCCCCCDDDDDDDDDD
EEEEEEEEEEEEEEEEEEEE
FFFFFFFFFFFFFFFFFFFF
GGGGGGGGGGGHHHHHHHHH
IIIIIIIIIIIIIIIIIIII"
  patchwork::wrap_plots(A = p_pct, B = b_pct, C = mix_panel, D = model_panel, E = loc_panel, F = xw_panel,
                        G = ars_panel, H = plat_panel, I = gloss, design = design,
                        heights = c(1.4, 1.7, 0.95, 1.5, 1.75, 0.95)) +
    patchwork::plot_annotation(
      title = "THE DETAIL",
      subtitle = sprintf("%s vs. %s  ·  pitch mix and locations: 2026  ·  outcomes: 2025-26",
                         m$pitcher$full_name, m$batter$full_name),
      theme = ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = 16, colour = "#c8102e"),
                             plot.subtitle = ggplot2::element_text(size = BASE, colour = "grey30")))
}

build_report_pages <- function(d, model, pitcher_id, batter_id, situation = DEFAULT_SITUATION) {
  probs <- key_count_probs(d, model, pitcher_id, batter_id, situation)
  first_pitch <- dplyr::filter(probs, count == "0-0")
  list(page1 = build_page1(d, model, pitcher_id, batter_id, situation, first_pitch),
       page2 = build_page2(d, model, pitcher_id, batter_id, situation, probs))
}

render_report_pdf <- function(d, model, pitcher_id, batter_id, file, situation = DEFAULT_SITUATION) {
  pages <- build_report_pages(d, model, pitcher_id, batter_id, situation)
  grDevices::cairo_pdf(file, width = 8.5, height = 11, onefile = TRUE)
  on.exit(grDevices::dev.off())
  print(pages$page1)
  print(pages$page2)
  invisible(file)
}
