# report.R --------------------------------------------------------------------
# Every piece of the one-page matchup report. The Shiny app and the PDF both
# call these functions, so they can never disagree. Requires constants.R,
# features.R and boost_model.R to be sourced first.

PITCH_COLORS <- c(FF = "#D22D49", SI = "#FE9D00", FC = "#933F2C", SL = "#C9C21B",
                  ST = "#DDB33A", CU = "#00A8C5", CH = "#1DBE3A", FS = "#3BACAC")
FAMILY_COLORS <- c(FB = "#D22D49", BR = "#00A8C5", OS = "#1DBE3A")
PLATE_HALF_WIDTH <- 17 / 2 / 12   # ft
MIN_USAGE_SHOWN <- 0.02           # pitch types under 2% usage are hidden

COUNT_BUCKETS <- list(
  "All counts" = NULL,
  "First pitch" = "0-0",
  "Pitcher ahead" = c("0-1", "0-2", "1-2"),
  "Even" = c("1-1", "2-2"),
  "Hitter ahead" = c("1-0", "2-0", "2-1", "3-0", "3-1"),
  "Two strikes" = c("0-2", "1-2", "2-2", "3-2")
)

# ---- data ----

load_report_data <- function(dir = "data") {
  rd <- function(name) arrow::read_parquet(file.path(dir, paste0(name, ".parquet")))
  list(
    players = rd("players"), count_mix = rd("pitcher_count_mix"), locations = rd("pitcher_locations"),
    arsenal = rd("pitcher_arsenal"), outcomes = rd("outcomes"), h2h = rd("head_to_head"),
    mix_state = rd("mix_state"), mix_flags = rd("mix_flags"), batter_state = rd("batter_state"),
    prev_result_freq = rd("prev_result_freq"),
    meta = jsonlite::read_json(file.path(dir, "meta.json"))
  )
}

player_row <- function(d, id, role) dplyr::filter(d$players, player_id == id, role == !!role) |> utils::head(1)

# Which side a hitter bats from against this pitcher (switch hitters flip).
batter_stand <- function(bat_side, p_throws) {
  if (identical(bat_side, "S")) ifelse(p_throws == "R", "L", "R") else bat_side
}

matchup <- function(d, pitcher_id, batter_id) {
  p <- player_row(d, pitcher_id, "P")
  b <- player_row(d, batter_id, "B")
  list(pitcher = p, batter = b, p_throws = p$pitch_hand,
       stand = batter_stand(b$bat_side, p$pitch_hand),
       flags = dplyr::filter(d$mix_flags, pitcher == pitcher_id))
}

shown_groups <- function(d, pitcher_id, stand) {
  d$count_mix |>
    dplyr::filter(pitcher == pitcher_id, stand == !!stand) |>
    dplyr::count(pitch_group, wt = n) |>
    dplyr::mutate(share = n / sum(n)) |>
    dplyr::filter(share >= MIN_USAGE_SHOWN) |>
    dplyr::arrange(dplyr::desc(share)) |>
    dplyr::pull(pitch_group)
}

pct <- function(x, digits = 0) ifelse(is.na(x), "-", sprintf(paste0("%.", digits, "f%%"), 100 * x))
woba_fmt <- function(x) ifelse(is.na(x), "-", sub("^0", "", sprintf("%.3f", x)))

# ---- pitch mix by count ----

count_mix_table <- function(d, pitcher_id, stand, family = FALSE) {
  df <- dplyr::filter(d$count_mix, pitcher == pitcher_id, stand == !!stand)
  if (family) df <- dplyr::mutate(df, pitch_group = PITCH_FAMILY[pitch_group])
  levels_used <- if (family) PITCH_FAMILIES else intersect(PITCH_GROUPS, shown_groups(d, pitcher_id, stand))
  df |>
    dplyr::filter(pitch_group %in% levels_used) |>
    dplyr::count(count_str, pitch_group, wt = n) |>
    tidyr::complete(count_str = FACTOR_LEVELS$count_str, pitch_group = levels_used, fill = list(n = 0)) |>
    dplyr::group_by(count_str) |>
    dplyr::mutate(total = sum(n), share = ifelse(total > 0, n / total, NA_real_)) |>
    dplyr::ungroup() |>
    dplyr::mutate(count_str = factor(count_str, levels = rev(FACTOR_LEVELS$count_str)),
                  pitch_group = factor(pitch_group, levels = levels_used))
}

plot_count_mix <- function(d, pitcher_id, stand, family = FALSE) {
  df <- count_mix_table(d, pitcher_id, stand, family)
  labels <- if (family) PITCH_FAMILY_NAMES else PITCH_GROUP_NAMES
  totals <- dplyr::distinct(df, count_str, total)
  ggplot2::ggplot(df, ggplot2::aes(pitch_group, count_str, fill = share)) +
    ggplot2::geom_tile(colour = "white", linewidth = 0.6) +
    ggplot2::geom_text(ggplot2::aes(label = ifelse(is.na(share) | share < 0.005, "", pct(share))), size = 3.2) +
    ggplot2::geom_text(data = totals, ggplot2::aes(x = length(levels(df$pitch_group)) + 0.75, y = count_str,
                                                   label = total), inherit.aes = FALSE, size = 2.8,
                       colour = "grey45", hjust = 0) +
    ggplot2::scale_fill_gradient(low = "#f4f7fb", high = "#1b6ca8", limits = c(0, 1), na.value = "grey95",
                                 guide = "none") +
    ggplot2::scale_x_discrete(labels = labels, position = "top", expand = ggplot2::expansion(add = c(0.5, 1))) +
    ggplot2::labs(x = NULL, y = "Count", caption = "Right column: pitches in that count") +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(panel.grid = ggplot2::element_blank(), plot.caption = ggplot2::element_text(colour = "grey45"))
}

# ---- location density ----

plot_locations <- function(d, pitcher_id, stand, bucket = "All counts", max_types = 4) {
  groups <- utils::head(shown_groups(d, pitcher_id, stand), max_types)
  counts <- COUNT_BUCKETS[[bucket]]
  df <- d$locations |>
    dplyr::filter(pitcher == pitcher_id, stand == !!stand, pitch_group %in% groups) |>
    dplyr::mutate(count_str = paste0(balls, "-", strikes))
  if (!is.null(counts)) df <- dplyr::filter(df, count_str %in% counts)
  n_lab <- dplyr::count(df, pitch_group) |>
    dplyr::mutate(label = paste0(PITCH_GROUP_NAMES[pitch_group], " (", n, ")"))
  df <- dplyr::left_join(df, n_lab, by = "pitch_group") |>
    dplyr::mutate(label = factor(label, levels = n_lab$label[match(groups, n_lab$pitch_group)]))
  dense <- dplyr::group_by(df, label) |> dplyr::filter(dplyr::n() >= 15) |> dplyr::ungroup()
  zone <- data.frame(xmin = -PLATE_HALF_WIDTH, xmax = PLATE_HALF_WIDTH,
                     ymin = d$meta$sz_bot, ymax = d$meta$sz_top)

  ggplot2::ggplot(df, ggplot2::aes(plate_x, plate_z)) +
    ggplot2::stat_density_2d(data = dense, ggplot2::aes(fill = ggplot2::after_stat(level)),
                             geom = "polygon", alpha = 0.85, bins = 8, h = c(0.9, 0.9)) +
    ggplot2::geom_point(data = dplyr::anti_join(df, dense, by = names(df)), alpha = 0.5, size = 0.8) +
    ggplot2::geom_rect(data = zone, ggplot2::aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
                       inherit.aes = FALSE, fill = NA, colour = "black", linewidth = 0.6) +
    ggplot2::scale_fill_gradient(low = "#fde0dd", high = "#c51b8a", guide = "none") +
    ggplot2::facet_wrap(~ label, nrow = 1, drop = TRUE) +
    ggplot2::coord_equal(xlim = c(-2, 2), ylim = c(0.5, 4.5)) +
    ggplot2::labs(x = NULL, y = NULL,
                  caption = sprintf("Catcher's view, vs. %sHB, %s. Shading = where pitches cluster; it blends where he aims with how often he misses.",
                                    stand, tolower(bucket))) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(axis.text = ggplot2::element_blank(), panel.grid = ggplot2::element_blank(),
                   strip.text = ggplot2::element_text(face = "bold"),
                   plot.caption = ggplot2::element_text(colour = "grey45"))
}

# ---- arsenal and platoon ----

arsenal_table <- function(d, pitcher_id, stand) {
  groups <- shown_groups(d, pitcher_id, stand)
  d$arsenal |>
    dplyr::filter(pitcher == pitcher_id, stand == !!stand, pitch_group %in% groups) |>
    dplyr::mutate(usage = n / sum(n)) |>
    dplyr::arrange(dplyr::desc(usage)) |>
    dplyr::transmute(Pitch = PITCH_GROUP_NAMES[pitch_group], Usage = pct(usage), Velo = sprintf("%.1f", velo),
                     `H-brk"` = sprintf("%.0f", h_break_in), `V-brk"` = sprintf("%.0f", v_break_in),
                     `Whiff%` = pct(whiffs / swings), `Chase%` = pct(chases / out_zone), Pitches = n)
}

outcome_row <- function(d, side, id, hand, group = "ALL") {
  dplyr::filter(d$outcomes, side == !!side, player_id == id, opp_hand == hand, pitch_group == group)
}

platoon_table <- function(d, pitcher_id, batter_id) {
  rows <- function(side, id, label) {
    purrr::map_dfr(c("L", "R"), function(h) {
      r <- outcome_row(d, side, id, h)
      tibble::tibble(Player = label, Split = paste0("vs ", h, if (side == "pitcher") "HB" else "HP"),
                     PA = if (nrow(r)) r$pa else 0L,
                     xwOBA = if (nrow(r)) woba_fmt(r$xwoba) else "-",
                     `K%` = if (nrow(r)) pct(r$k_rate, 1) else "-",
                     `BB%` = if (nrow(r)) pct(r$bb_rate, 1) else "-")
    })
  }
  dplyr::bind_rows(
    rows("pitcher", pitcher_id, player_row(d, pitcher_id, "P")$full_name),
    rows("batter", batter_id, player_row(d, batter_id, "B")$full_name)
  )
}

# ---- expected outcomes by pitch type ----

xwoba_by_pitch <- function(d, pitcher_id, batter_id) {
  m <- matchup(d, pitcher_id, batter_id)
  groups <- shown_groups(d, pitcher_id, m$stand)
  get <- function(side, id, hand, who) {
    dplyr::filter(d$outcomes, side == !!side, player_id == id, opp_hand == hand, pitch_group %in% groups) |>
      dplyr::transmute(pitch_group, who = who, xwoba = xwoba_shrunk, pa, league_xwoba)
  }
  dplyr::bind_rows(
    get("batter", batter_id, m$p_throws, sprintf("%s vs. %sHP", m$batter$full_name, m$p_throws)),
    get("pitcher", pitcher_id, m$stand, sprintf("%s vs. %sHB", m$pitcher$full_name, m$stand))
  ) |>
    dplyr::mutate(pitch_group = factor(pitch_group, levels = rev(groups)))
}

plot_xwoba_by_pitch <- function(d, pitcher_id, batter_id) {
  df <- xwoba_by_pitch(d, pitcher_id, batter_id)
  league <- dplyr::distinct(df, pitch_group, league_xwoba) |> dplyr::group_by(pitch_group) |>
    dplyr::summarise(league_xwoba = mean(league_xwoba), .groups = "drop")
  ggplot2::ggplot(df, ggplot2::aes(xwoba, pitch_group, fill = who)) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.75), width = 0.7) +
    ggplot2::geom_text(ggplot2::aes(label = paste0(woba_fmt(xwoba), "  (", pa, " PA)")),
                       position = ggplot2::position_dodge(width = 0.75), hjust = -0.1, size = 3) +
    ggplot2::geom_point(data = league, ggplot2::aes(league_xwoba, pitch_group), inherit.aes = FALSE,
                        shape = 124, size = 6, colour = "grey30") +
    ggplot2::scale_y_discrete(labels = PITCH_GROUP_NAMES) +
    ggplot2::scale_x_continuous(limits = c(0, 0.7), breaks = seq(0, 0.5, 0.1), labels = woba_fmt, expand = c(0, 0)) +
    ggplot2::scale_fill_manual(values = c("#1b6ca8", "#d1495b")) +
    ggplot2::labs(x = "xwOBA (shrunk toward league)", y = NULL, fill = NULL,
                  caption = sprintf("%s. Black tick = league average for that pitch and matchup.",
                                    paste(range(unlist(d$meta$outcome_seasons)), collapse = "-"))) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(legend.position = "top", panel.grid.major.y = ggplot2::element_blank(),
                   plot.caption = ggplot2::element_text(colour = "grey45"))
}

# ---- head to head ----

head_to_head_summary <- function(d, pitcher_id, batter_id) {
  h <- dplyr::filter(d$h2h, pitcher == pitcher_id, batter == batter_id)
  if (!nrow(h)) return(NULL)
  tibble::tibble(Seasons = paste(unique(c(min(h$first_year), max(h$last_year))), collapse = "-"), Pitches = sum(h$pitches), PA = sum(h$pa),
                 H = sum(h$hits), HR = sum(h$hr), K = sum(h$k), BB = sum(h$bb),
                 xwOBA = woba_fmt(ifelse(sum(h$pa) > 0, sum(h$xwoba_sum, na.rm = TRUE) / sum(h$pa), NA)))
}

# ---- next-pitch prediction ----

DEFAULT_SITUATION <- list(count = "0-0", prev1 = "UNKNOWN", prev1_result = "UNKNOWN", prev2 = "UNKNOWN",
                          base_state = "___", outs = 0, inning = "1-3", score = "tied", tto = 1,
                          pitch_count = "1-25", starter = TRUE)

PITCH_COUNT_MIDPOINT <- c("1-25" = 12, "26-50" = 38, "51-75" = 63, "76-100" = 88, "100+" = 105)

situation_row <- function(d, pitcher_id, batter_id, s) {
  m <- matchup(d, pitcher_id, batter_id)
  mix <- dplyr::filter(d$mix_state, pitcher == pitcher_id, stand == m$stand)
  p3 <- stats::setNames(mix$p3, mix$pitch_group)[PITCH_GROUPS]
  b <- dplyr::filter(d$batter_state, batter == batter_id)
  badj <- if (nrow(b)) unlist(b[paste0("badj_", PITCH_GROUPS)]) else stats::setNames(rep(0, 8), paste0("badj_", PITCH_GROUPS))
  # Earlier in this game we assume his usual family mix (the app can't know today's pitches).
  fam <- tapply(p3, PITCH_FAMILY[PITCH_GROUPS], sum)
  gtd_n <- PITCH_COUNT_MIDPOINT[[s$pitch_count]] - 1
  f <- m$flags
  row <- tibble::tibble(
    count_str = s$count, same_hand = m$stand == m$p_throws,
    prev1_group = s$prev1, prev1_result = if (s$prev1 == "NONE") "none" else s$prev1_result,
    prev2_group = if (s$prev1 == "NONE") "NONE" else s$prev2,
    base_state = s$base_state, outs = as.integer(s$outs), inning_bkt = s$inning, score_bkt = s$score,
    tto = as.integer(s$tto), pitch_count_bkt = s$pitch_count, is_starter = isTRUE(s$starter),
    gtd_n = gtd_n, gtd_fb_share = fam[["FB"]], gtd_br_share = fam[["BR"]],
    mix_changed = isTRUE(f$mix_changed[1]), relabeled = isTRUE(f$relabeled[1]),
    mix_tvd = dplyr::coalesce(f$mix_tvd[1], 0),
    history_pitches = dplyr::coalesce(f$history_pitches[1], 0),
    season_pitches_before = dplyr::coalesce(f$season_pitches_before[1], 0),
    batter_pitches_seen = if (nrow(b)) b$batter_pitches_seen else 0,
    pitch_group = "FF"
  )
  for (k in PITCH_GROUPS) {
    row[[paste0("p3_", k)]] <- p3[[k]]
    row[[paste0("badj_", k)]] <- badj[[paste0("badj_", k)]]
  }
  prepare_factors(row)
}

# Which results of the previous pitch are possible given the current count.
# 0-2: the last pitch was a strike; 2-0: a ball; 1-1: anything.
possible_results <- function(count) {
  b <- as.integer(substr(count, 1, 1))
  s <- as.integer(substr(count, 3, 3))
  out <- character()
  if (b > 0) out <- c(out, "ball")
  if (s > 0) out <- c(out, "called", "whiff", "foul")
  out
}

# Every concrete situation consistent with the user's choices, with a weight.
# When the previous pitch (or its result) is left as "unknown", the prediction
# averages over his likely previous pitches (his mix) and the results that
# could have produced this count (league frequencies), instead of pretending
# there was no previous pitch.
expand_situation <- function(d, pitcher_id, batter_id, s) {
  if (s$count == "0-0") return(tibble::tibble(prev1 = "NONE", prev1_result = "none", prev2 = "NONE", w = 1))
  m <- matchup(d, pitcher_id, batter_id)
  mix <- dplyr::filter(d$mix_state, pitcher == pitcher_id, stand == m$stand, p3 >= 0.01)
  his <- stats::setNames(mix$p3 / sum(mix$p3), mix$pitch_group)
  pick <- function(choice, options) if (choice == "UNKNOWN") options else stats::setNames(1, choice)

  freq <- dplyr::filter(d$prev_result_freq, count_str == s$count, prev1_result %in% possible_results(s$count))
  results <- if (s$prev1_result == "UNKNOWN") stats::setNames(freq$share / sum(freq$share), freq$prev1_result)
             else stats::setNames(1, s$prev1_result)
  pitches_before <- sum(as.integer(strsplit(s$count, "-")[[1]]))
  p1 <- pick(s$prev1, his)
  p2 <- if (pitches_before < 2) stats::setNames(1, "NONE") else pick(s$prev2, his)

  tidyr::expand_grid(prev1 = names(p1), prev1_result = names(results), prev2 = names(p2)) |>
    dplyr::mutate(w = p1[prev1] * results[prev1_result] * p2[prev2])
}

predict_next_pitch <- function(d, model, pitcher_id, batter_id, situation = DEFAULT_SITUATION) {
  combos <- expand_situation(d, pitcher_id, batter_id, situation)
  rows <- purrr::pmap_dfr(combos, function(prev1, prev1_result, prev2, w) {
    situation_row(d, pitcher_id, batter_id,
                  utils::modifyList(situation, list(prev1 = prev1, prev1_result = prev1_result, prev2 = prev2)))
  })
  rows <- prepare_factors(rows)
  p3 <- as.matrix(rows[paste0("p3_", PITCH_GROUPS)])
  offset <- log(p3) + as.matrix(rows[paste0("badj_", PITCH_GROUPS)])
  p <- predict_boost(model, boost_dmatrix(rows, offset))
  w <- combos$w / sum(combos$w)
  tibble::tibble(pitch_group = PITCH_GROUPS, model = as.numeric(colSums(p * w)), usual = as.numeric(p3[1, ]))
}

plot_prediction <- function(pred, min_prob = 0.01) {
  df <- pred |>
    dplyr::filter(model >= min_prob | usual >= min_prob) |>
    dplyr::mutate(pitch_group = factor(pitch_group, levels = pitch_group[order(model)]))
  ggplot2::ggplot(df, ggplot2::aes(model, pitch_group, fill = pitch_group)) +
    ggplot2::geom_col(width = 0.65) +
    ggplot2::geom_point(ggplot2::aes(x = usual), shape = 124, size = 7, colour = "grey20") +
    ggplot2::geom_text(ggplot2::aes(label = pct(model)), hjust = -0.25, size = 3.6) +
    ggplot2::scale_fill_manual(values = PITCH_COLORS, guide = "none") +
    ggplot2::scale_y_discrete(labels = PITCH_GROUP_NAMES) +
    ggplot2::scale_x_continuous(labels = scales::percent, limits = c(0, max(1, max(df$model) + 0.12)),
                                expand = c(0, 0)) +
    ggplot2::labs(x = NULL, y = NULL, caption = "Bar = model's prediction for this situation. Tick = his usual mix vs. this hand.") +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank(),
                   plot.caption = ggplot2::element_text(colour = "grey45"))
}

family_summary <- function(pred) {
  pred |>
    dplyr::mutate(family = PITCH_FAMILY[pitch_group]) |>
    dplyr::group_by(family) |>
    dplyr::summarise(model = sum(model), usual = sum(usual), .groups = "drop") |>
    dplyr::mutate(family = factor(family, levels = PITCH_FAMILIES)) |>
    dplyr::arrange(family) |>
    dplyr::transmute(Family = PITCH_FAMILY_NAMES[as.character(family)], `This situation` = pct(model),
                     `His usual mix` = pct(usual))
}
