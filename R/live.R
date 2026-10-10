# live.R ----------------------------------------------------------------------
# Live next-pitch tracking from the MLB Stats API game feed.
#
# Every pitch in the feed is turned into the state BEFORE it was thrown: count,
# earlier pitches in the at-bat and their results, runners, outs, score,
# inning, times through the order, the pitcher's pitch count. The model only
# ever sees that pre-pitch state, so a prediction made from it is the same
# whether it's made live or replayed after the game. Live mode also records
# the time each prediction was made, before the pitch appeared in the feed.

FEED_URL <- "https://statsapi.mlb.com/api/v1.1/game/%s/feed/live"

fetch_feed <- function(game_pk) jsonlite::fromJSON(sprintf(FEED_URL, game_pk), simplifyVector = FALSE)

# Pitch-call codes -> the previous-pitch result categories the model uses.
CALL_RESULT <- c(B = "ball", "*B" = "ball", V = "ball", I = "ball", P = "ball", H = "other",
                 C = "called", A = "called",
                 S = "whiff", W = "whiff", M = "whiff", Q = "whiff", T = "whiff", O = "whiff",
                 F = "foul", L = "foul", R = "foul",
                 X = "other", D = "other", E = "other")

pitch_group_of <- function(code) {
  g <- PITCH_GROUP_MAP$pitch_group[match(code, PITCH_GROUP_MAP$pitch_type)]
  ifelse(is.na(g), "OTHER", g)
}

base_state_of <- function(bases) {
  paste0(if ("1B" %in% bases) "1" else "_", if ("2B" %in% bases) "2" else "_", if ("3B" %in% bases) "3" else "_")
}

pitch_count_bucket <- function(n) {
  as.character(cut(n, c(0, 25, 50, 75, 100, Inf), labels = c("1-25", "26-50", "51-75", "76-100", "100+")))
}

score_bucket <- function(diff) {
  if (diff <= -4) "down4+" else if (diff <= -2) "down2-3" else if (diff == -1) "down1" else if (diff == 0) "tied"
  else if (diff == 1) "up1" else if (diff <= 3) "up2-3" else "up4+"
}

inning_bucket <- function(i) if (i <= 3) "1-3" else if (i <= 6) "4-6" else if (i <= 9) "7-9" else "10+"

# One row per pitch, in order, with the state before it and what was thrown.
# Runners and outs are carried from play to play (a runner who moves during an
# at-bat, e.g. a steal, is reflected from the next at-bat on).
game_pitches <- function(feed) {
  plays <- feed$liveData$plays$allPlays
  bases <- character(); outs <- 0L; half <- ""; away <- 0L; home <- 0L
  starters <- list(); pitcher_pitches <- list(); faced <- list()
  rows <- list()
  for (p in plays) {
    this_half <- paste(p$about$inning, p$about$halfInning)
    if (this_half != half) { bases <- character(); outs <- 0L; half <- this_half }
    top <- isTRUE(p$about$isTopInning)
    pid <- p$matchup$pitcher$id; bid <- p$matchup$batter$id
    team <- if (top) "home" else "away"
    if (is.null(starters[[team]])) starters[[team]] <- pid
    key <- paste(pid, bid)
    faced[[key]] <- (faced[[key]] %||% 0L) + 1L
    balls <- 0L; strikes <- 0L; prev <- list()
    for (ev in p$playEvents) {
      if (!isTRUE(ev$isPitch)) next
      n_before <- pitcher_pitches[[as.character(pid)]] %||% 0L
      code <- ev$details$type$code %||% NA_character_
      call <- ev$details$call$code %||% ev$details$code %||% NA_character_
      p1 <- if (length(prev) >= 1) prev[[length(prev)]] else NULL
      p2 <- if (length(prev) >= 2) prev[[length(prev) - 1]] else NULL
      rows[[length(rows) + 1]] <- tibble::tibble(
        at_bat = p$about$atBatIndex, pitch_index = ev$index, pitch_number = ev$pitchNumber %||% (length(prev) + 1),
        start_time = ev$startTime %||% NA_character_,
        inning = p$about$inning, half = p$about$halfInning, pitcher = pid, batter = bid,
        pitcher_name = p$matchup$pitcher$fullName, batter_name = p$matchup$batter$fullName,
        count = paste0(balls, "-", strikes), outs = outs, base_state = base_state_of(bases),
        score_diff = if (top) home - away else away - home,
        tto = min(faced[[key]], 3L), pitch_count = n_before + 1L,
        starter = identical(starters[[team]], pid),
        prev1 = if (is.null(p1)) "NONE" else p1$group, prev1_result = if (is.null(p1)) "none" else p1$result,
        prev2 = if (is.null(p2)) "NONE" else p2$group,
        actual_code = code, actual = if (is.na(code)) NA_character_ else pitch_group_of(code))
      pitcher_pitches[[as.character(pid)]] <- n_before + 1L
      prev[[length(prev) + 1]] <- list(group = if (is.na(code)) "OTHER" else pitch_group_of(code),
                                       result = unname(CALL_RESULT[call]) %||% "other")
      balls <- as.integer(ev$count$balls %||% balls); strikes <- as.integer(ev$count$strikes %||% strikes)
      balls <- min(balls, 3L); strikes <- min(strikes, 2L)
    }
    # carry the state forward to the next at-bat
    if (isTRUE(p$about$isComplete)) {
      for (r in p$runners) {
        start <- r$movement$start; end <- r$movement$end
        if (!is.null(start)) bases <- setdiff(bases, start)
        if (!is.null(end) && end %in% c("1B", "2B", "3B")) bases <- union(bases, end)
      }
      outs <- as.integer(p$count$outs %||% outs)
      away <- as.integer(p$result$awayScore %||% away); home <- as.integer(p$result$homeScore %||% home)
    }
  }
  dplyr::bind_rows(rows)
}

# The state of the next pitch of the at-bat in progress (NULL if none).
upcoming_pitch <- function(feed) {
  cur <- feed$liveData$plays$currentPlay
  if (is.null(cur) || isTRUE(cur$about$isComplete)) return(NULL)
  # Re-use game_pitches on a copy where the current at-bat gets one placeholder pitch.
  placeholder <- list(isPitch = TRUE, index = 999L, pitchNumber = NULL, startTime = NULL,
                      details = list(type = list(code = NA_character_), call = list(code = NA_character_)),
                      count = list(balls = NULL, strikes = NULL))
  plays <- feed$liveData$plays$allPlays
  plays[[length(plays)]]$playEvents <- c(plays[[length(plays)]]$playEvents, list(placeholder))
  feed$liveData$plays$allPlays <- plays
  rows <- game_pitches(feed)
  utils::tail(rows, 1)
}

situation_from_row <- function(r) {
  list(count = r$count, prev1 = r$prev1, prev1_result = r$prev1_result, prev2 = r$prev2,
       base_state = r$base_state, outs = r$outs, inning = inning_bucket(r$inning),
       score = score_bucket(r$score_diff), tto = r$tto, pitch_count = pitch_count_bucket(r$pitch_count),
       starter = r$starter)
}

# Model and usual-mix probabilities for one pre-pitch row (NULL if a player
# has no 2026 data in the app tables).
predict_row <- function(d, model, r) {
  known <- r$pitcher %in% d$players$player_id[d$players$role == "P"] &&
    r$batter %in% d$players$player_id[d$players$role == "B"]
  if (!known) return(NULL)
  predict_next_pitch(d, model, r$pitcher, r$batter, situation_from_row(r), restrict = FALSE)
}

score_prediction <- function(pred, actual) {
  if (is.null(pred) || is.na(actual) || actual == "OTHER") return(NULL)
  fam <- function(p) tapply(p, PITCH_FAMILY[pred$pitch_group], sum)
  floor_p <- function(x) max(x, 1e-4)
  top_model <- pred$pitch_group[which.max(pred$model)]
  top_usual <- pred$pitch_group[which.max(pred$usual)]
  fm <- fam(pred$model); fu <- fam(pred$usual)
  af <- PITCH_FAMILY[[actual]]
  tibble::tibble(
    predicted = top_model, predicted_prob = max(pred$model),
    p_actual = pred$model[pred$pitch_group == actual], p_actual_usual = pred$usual[pred$pitch_group == actual],
    hit = top_model == actual, hit_usual = top_usual == actual,
    family_hit = names(which.max(fm)) == af, family_hit_usual = names(which.max(fu)) == af,
    log_loss = -log(floor_p(pred$model[pred$pitch_group == actual])),
    log_loss_usual = -log(floor_p(pred$usual[pred$pitch_group == actual])))
}
