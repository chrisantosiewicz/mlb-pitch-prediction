# 14_live_game.R --------------------------------------------------------------
# Predicts every pitch of one game and scores the predictions.
#   Rscript pipeline/14_live_game.R <gamePk>            # live: poll until the game is final
#   Rscript pipeline/14_live_game.R <gamePk> --replay   # finished game, all at once
# Writes data/live/<gamePk>_predictions.csv and docs/live/<gamePk>.md (+ chart).

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})
for (f in c("constants", "features", "boost_model", "report", "live", "cleaning_log")) source(file.path("R", paste0(f, ".R")))

POLL_SECONDS <- 8

args <- commandArgs(trailingOnly = TRUE)
game_pk <- args[1]
replay <- "--replay" %in% args
out_csv <- sprintf("data/live/%s_predictions.csv", game_pk)
dir.create("data/live", recursive = TRUE, showWarnings = FALSE)

d <- load_report_data("app/data")
model <- xgboost::xgb.load("models/final_xgboost.ubj")

pitch_key <- function(at_bat, pitch_number) paste(at_bat, pitch_number, sep = "-")

# Predictions made so far, keyed by at-bat and pitch number.
log_tbl <- if (file.exists(out_csv)) readr::read_csv(out_csv, show_col_types = FALSE,
                                                    col_types = readr::cols(.default = "c")) else tibble::tibble()
logged_keys <- if (nrow(log_tbl)) log_tbl$key else character()

predict_and_log <- function(r, mode) {
  key <- pitch_key(r$at_bat, r$pitch_number)
  if (key %in% logged_keys) return(invisible(NULL))
  pred <- predict_row(d, model, r)
  if (is.null(pred)) return(invisible(NULL))
  probs <- stats::setNames(as.list(round(pred$model, 4)), paste0("p_", pred$pitch_group))
  usual <- stats::setNames(as.list(round(pred$usual, 4)), paste0("u_", pred$pitch_group))
  row <- dplyr::bind_cols(
    tibble::tibble(key = key, predicted_at = format(Sys.time(), tz = "UTC", usetz = TRUE), mode = mode),
    dplyr::select(r, at_bat, pitch_number, inning, half, pitcher_name, batter_name, count, base_state, outs,
                  prev1, prev1_result),
    tibble::as_tibble(probs), tibble::as_tibble(usual))
  row <- dplyr::mutate(row, dplyr::across(dplyr::everything(), as.character))
  log_tbl <<- dplyr::bind_rows(log_tbl, row)
  logged_keys <<- c(logged_keys, key)
  readr::write_csv(log_tbl, out_csv)
}

if (replay) {
  feed <- fetch_feed(game_pk)
  pitches <- game_pitches(feed)
  for (i in seq_len(nrow(pitches))) predict_and_log(pitches[i, ], "replay")
} else {
  message("Tracking game ", game_pk, " live. Predictions go to ", out_csv)
  repeat {
    feed <- tryCatch(fetch_feed(game_pk), error = function(e) { message("feed error: ", conditionMessage(e)); NULL })
    if (!is.null(feed)) {
      state <- feed$gameData$status$abstractGameState
      pitches <- game_pitches(feed)
      # Any pitch we missed (late start, lag) is predicted from its pre-pitch state and marked as backfill.
      if (nrow(pitches)) for (i in seq_len(nrow(pitches))) predict_and_log(pitches[i, ], "backfill")
      nxt <- upcoming_pitch(feed)
      if (!is.null(nxt)) predict_and_log(nxt, "live")
      if (identical(state, "Final")) break
    }
    Sys.sleep(POLL_SECONDS)
  }
  feed <- fetch_feed(game_pk)
  pitches <- game_pitches(feed)
}

# ---- score ----
source("R/live_report.R")
write_live_report(game_pk, feed, pitches, log_tbl)
