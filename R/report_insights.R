# report_insights.R -----------------------------------------------------------
# Fan-friendly pieces of the report: plain-language takeaways, three simple
# count situations, and a pitch-by-pitch "edge" strip. Every sentence is built
# from fixed rules and only appears when its sample is big enough.

KEY_COUNTS <- c("0-0", "1-0", "0-1", "2-0", "1-1", "0-2", "3-1", "2-2", "3-2")

SITUATIONS <- list(
  "First pitch" = "0-0",
  "Pitcher ahead" = c("0-1", "0-2", "1-2"),
  "Hitter ahead" = c("1-0", "2-0", "2-1", "3-0", "3-1")
)
TWO_STRIKE_COUNTS <- c("0-2", "1-2", "2-2", "3-2")

MIN_SITUATION_PITCHES <- 40   # below this a situation bar is labeled "small sample"
MIN_SHIFT_PITCHES <- 50       # two-strike pitches needed to describe a shift
MIN_SHIFT_POINTS <- 0.05      # a usage change under 5 points isn't worth a sentence
MIN_EDGE_PA <- 25             # PA ending on a pitch type before we call an edge
EDGE_THRESHOLD <- 0.025       # xwOBA gap vs. league that counts as an edge
MIN_BEST_WORST_GAP <- 0.030   # best and worst pitch types must differ this much to name them

hand_word <- function(stand) if (stand == "L") "lefties" else "righties"

# Model probabilities for each key count, previous pitches unknown (averaged).
key_count_probs <- function(d, model, pitcher_id, batter_id, situation = DEFAULT_SITUATION) {
  purrr::map_dfr(KEY_COUNTS, function(cnt) {
    s <- utils::modifyList(situation, list(count = cnt, prev1 = "UNKNOWN", prev1_result = "UNKNOWN",
                                           prev2 = "UNKNOWN"))
    predict_next_pitch(d, model, pitcher_id, batter_id, s) |> dplyr::mutate(count = cnt)
  })
}

# Table form used by the app.
key_count_table <- function(d, model, pitcher_id, batter_id, situation = DEFAULT_SITUATION, probs = NULL) {
  probs <- probs %||% key_count_probs(d, model, pitcher_id, batter_id, situation)
  probs |>
    dplyr::group_by(count) |>
    dplyr::summarise(
      fb = sum(model[PITCH_FAMILY[pitch_group] == "FB"]), br = sum(model[PITCH_FAMILY[pitch_group] == "BR"]),
      os = sum(model[PITCH_FAMILY[pitch_group] == "OS"]),
      top1 = pitch_group[order(-model)][1], p1 = sort(model, decreasing = TRUE)[1],
      top2 = pitch_group[order(-model)][2], p2 = sort(model, decreasing = TRUE)[2], .groups = "drop") |>
    dplyr::mutate(count = factor(count, levels = KEY_COUNTS)) |>
    dplyr::arrange(count) |>
    dplyr::transmute(Count = as.character(count), Fastball = pct(fb), Breaking = pct(br), Offspeed = pct(os),
                     `Most likely` = sprintf("%s %s", PITCH_GROUP_NAMES[top1], pct(p1)),
                     Next = sprintf("%s %s", PITCH_GROUP_NAMES[top2], pct(p2)))
}

# What he actually threw vs. this side in three simple situations.
situation_mix <- function(d, pitcher_id, stand) {
  base <- dplyr::filter(d$count_mix, pitcher == pitcher_id, stand == !!stand)
  purrr::imap_dfr(SITUATIONS, function(counts, name) {
    df <- dplyr::filter(base, count_str %in% counts)
    total <- sum(df$n)
    fam <- df |> dplyr::mutate(family = PITCH_FAMILY[pitch_group]) |> dplyr::count(family, wt = n)
    top <- df |> dplyr::count(pitch_group, wt = n) |> dplyr::slice_max(n, n = 1, with_ties = FALSE)
    top_pitch <- if (nrow(top)) top$pitch_group else NA_character_
    top_share <- if (nrow(top) && total > 0) top$n / total else NA_real_
    tibble::tibble(situation = name, family = PITCH_FAMILIES) |>
      dplyr::left_join(fam, by = "family") |>
      dplyr::mutate(n = dplyr::coalesce(n, 0), share = if (total > 0) n / total else NA_real_,
                    total = total, top_pitch = top_pitch, top_share = top_share)
  })
}

# Pitch-by-pitch edge. Both sides count: how the hitter does against this pitch
# type from pitchers of this hand, and how this pitcher's version of it does
# against hitters of this side, each relative to league (shrunk xwOBA):
#   projected = league + (hitter - league) + (pitcher allowed - league)
# An elite hitter can still lose a pitch to an elite version of it.
pitch_edges <- function(d, pitcher_id, batter_id) {
  m <- matchup(d, pitcher_id, batter_id)
  groups <- shown_groups(d, pitcher_id, m$stand)
  usage <- d$arsenal |>
    dplyr::filter(pitcher == pitcher_id, stand == m$stand, pitch_group %in% groups) |>
    dplyr::mutate(usage = n / sum(n)) |>
    dplyr::select(pitch_group, usage, velo)
  hitter <- d$outcomes |>
    dplyr::filter(side == "batter", player_id == batter_id, opp_hand == m$p_throws, pitch_group %in% groups) |>
    dplyr::select(pitch_group, pa, xwoba = xwoba_shrunk, league_xwoba)
  pitcher <- d$outcomes |>
    dplyr::filter(side == "pitcher", player_id == pitcher_id, opp_hand == m$stand, pitch_group %in% groups) |>
    dplyr::select(pitch_group, p_pa = pa, p_xwoba = xwoba_shrunk)
  usage |>
    dplyr::left_join(hitter, by = "pitch_group") |>
    dplyr::left_join(pitcher, by = "pitch_group") |>
    dplyr::mutate(pa = dplyr::coalesce(pa, 0L), p_pa = dplyr::coalesce(p_pa, 0L),
                  projected = league_xwoba + (xwoba - league_xwoba) + (p_xwoba - league_xwoba),
                  gap = projected - league_xwoba,
                  edge = dplyr::case_when(pa < MIN_EDGE_PA | p_pa < MIN_EDGE_PA | is.na(gap) ~ "Not enough data",
                                          gap >= EDGE_THRESHOLD ~ "Hitter edge",
                                          gap <= -EDGE_THRESHOLD ~ "Pitcher edge",
                                          TRUE ~ "Even")) |>
    dplyr::arrange(dplyr::desc(usage))
}

# Three plain-language takeaways, each with its number and sample.
key_takeaways <- function(d, pitcher_id, batter_id, first_pitch_probs) {
  m <- matchup(d, pitcher_id, batter_id)
  pname <- sub(".* ", "", m$pitcher$full_name)
  bname <- sub(".* ", "", m$batter$full_name)
  out <- character()

  # 1. His main pitch to this side, and what changes with two strikes.
  mix <- dplyr::filter(d$count_mix, pitcher == pitcher_id, stand == m$stand)
  overall <- mix |> dplyr::count(pitch_group, wt = n) |> dplyr::mutate(share = n / sum(n))
  top <- dplyr::slice_max(overall, share, n = 1, with_ties = FALSE)
  s1 <- sprintf("%s throws his %s %s of the time to %s", pname, tolower(PITCH_GROUP_NAMES[top$pitch_group]),
                pct(top$share), hand_word(m$stand))
  two <- mix |> dplyr::filter(count_str %in% TWO_STRIKE_COUNTS) |> dplyr::count(pitch_group, wt = n)
  if (sum(two$n) >= MIN_SHIFT_PITCHES) {
    shift <- two |>
      dplyr::mutate(share2 = n / sum(n)) |>
      dplyr::left_join(dplyr::select(overall, pitch_group, share), by = "pitch_group") |>
      dplyr::mutate(change = share2 - share) |>
      dplyr::slice_max(change, n = 1, with_ties = FALSE)
    if (shift$change >= MIN_SHIFT_POINTS)
      s1 <- sprintf("%s, and leans on his %s with two strikes (%s overall, %s with two strikes)", s1,
                    tolower(PITCH_GROUP_NAMES[shift$pitch_group]), pct(shift$share), pct(shift$share2))
  }
  out <- c(out, paste0(s1, "."))

  # 2. Where the hitter does damage and where he struggles, against this pitcher's pitches.
  edges <- dplyr::filter(pitch_edges(d, pitcher_id, batter_id), pa >= MIN_EDGE_PA)
  best <- dplyr::slice_max(edges, xwoba, n = 1, with_ties = FALSE)
  worst <- dplyr::slice_min(edges, xwoba, n = 1, with_ties = FALSE)
  if (nrow(edges) >= 2 && best$xwoba - worst$xwoba < MIN_BEST_WORST_GAP) {
    out <- c(out, sprintf("%s has hit this pitcher's pitch types about equally well (xwOBA %s to %s).",
                          bname, woba_fmt(worst$xwoba), woba_fmt(best$xwoba)))
  } else if (nrow(edges) >= 2) {
    out <- c(out, sprintf(
      "%s does his best damage against %ss (xwOBA %s in %d PA; league %s) and struggles most against %ss (%s in %d PA).",
      bname, tolower(PITCH_GROUP_NAMES[best$pitch_group]), woba_fmt(best$xwoba), best$pa,
      woba_fmt(best$league_xwoba), tolower(PITCH_GROUP_NAMES[worst$pitch_group]), woba_fmt(worst$xwoba), worst$pa))
  }

  # 3. The first-pitch call.
  fp <- first_pitch_probs
  fam <- tapply(fp$model, PITCH_FAMILY[fp$pitch_group], sum)
  topfam <- names(which.max(fam))
  toppitch <- fp$pitch_group[which.max(fp$model)]
  out <- c(out, sprintf("First pitch: the model expects a %s %s of the time, most likely his %s (%s).",
                        tolower(PITCH_FAMILY_NAMES[topfam]), pct(max(fam)),
                        tolower(PITCH_GROUP_NAMES[toppitch]), pct(max(fp$model))))
  out
}
