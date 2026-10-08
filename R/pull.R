# pull.R ----------------------------------------------------------------------
# Download Statcast pitch-level data one game day at a time.
#
# Raw files are stored exactly as Savant returns them, with every column kept as
# text. Typing happens in the cleaning step, so a day where a column happens to
# be all-missing can never change the schema of the raw store.

RAW_DIR <- "data/raw"

# Regular-season windows are padded on both sides; spring training and
# postseason rows are removed in cleaning using game_type, not by date.
SEASON_WINDOWS <- list(
  "2022" = c("2022-04-05", "2022-10-06"),   # history only: priors for 2023 pitches
  "2023" = c("2023-03-25", "2023-10-03"),
  "2024" = c("2024-03-18", "2024-10-01"),
  "2025" = c("2025-03-16", "2025-09-30"),
  "2026" = c("2026-03-22", "2026-10-01")
)

raw_path <- function(date) {
  file.path(RAW_DIR, paste0("season=", format(date, "%Y")),
            paste0(format(date, "%Y-%m-%d"), ".parquet"))
}

# Marker for days Savant returned no pitches (off days), so they aren't re-pulled.
empty_marker_path <- function(date) sub("[.]parquet$", ".empty", raw_path(date))

already_pulled <- function(date) {
  file.exists(raw_path(date)) || file.exists(empty_marker_path(date))
}

fetch_statcast_day <- function(date, max_tries = 4) {
  for (attempt in seq_len(max_tries)) {
    result <- tryCatch(
      suppressMessages(suppressWarnings(baseballr::statcast_search(
        start_date = format(date), end_date = format(date), player_type = "batter"
      ))),
      error = function(e) e
    )
    if (!inherits(result, "error")) return(result)
    message(sprintf("  %s attempt %d failed: %s", date, attempt, conditionMessage(result)))
    Sys.sleep(2^attempt)
  }
  stop(sprintf("Giving up on %s after %d attempts", date, max_tries))
}

# Pull one day and write it. `overwrite = TRUE` is used for the trailing
# re-pull window during the season, when Savant may still be revising data.
pull_day <- function(date, overwrite = FALSE) {
  date <- as.Date(date)
  if (!overwrite && already_pulled(date)) return(invisible("skipped"))

  day <- fetch_statcast_day(date)
  dir.create(dirname(raw_path(date)), recursive = TRUE, showWarnings = FALSE)

  if (is.null(day) || nrow(day) == 0) {
    file.create(empty_marker_path(date))
    return(invisible("empty"))
  }
  # Savant caps a single request; a full slate is ~4,500 pitches, far below it,
  # but a truncated day would silently lose data, so check.
  if (nrow(day) >= 25000) stop(sprintf("%s hit the row cap; split the request", date))

  day <- dplyr::mutate(as.data.frame(day), dplyr::across(dplyr::everything(), as.character))
  day$pulled_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
  # Write to a temp file and rename, so a reader never sees a half-written file.
  tmp <- paste0(raw_path(date), ".tmp")
  arrow::write_parquet(day, tmp)
  file.rename(tmp, raw_path(date))
  if (file.exists(empty_marker_path(date))) file.remove(empty_marker_path(date))
  invisible(nrow(day))
}

pull_range <- function(start, end, overwrite = FALSE, pause = 1) {
  dates <- seq(as.Date(start), as.Date(end), by = "day")
  for (d in as.list(dates)) {
    t0 <- Sys.time()
    status <- pull_day(d, overwrite = overwrite)
    if (!identical(status, "skipped")) {
      message(sprintf("%s  %s  (%.1fs)", d, status, as.numeric(Sys.time() - t0, units = "secs")))
      Sys.sleep(pause)
    }
  }
}
