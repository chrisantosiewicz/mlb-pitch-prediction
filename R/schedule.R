# schedule.R ------------------------------------------------------------------
# Completeness check: every completed regular-season game on the MLB schedule
# should have pitches in the clean table. Also used by the in-season refresh.

SCHEDULE_URL <- "https://statsapi.mlb.com/api/v1/schedule?sportId=1&gameType=R&startDate=%s&endDate=%s"

fetch_completed_games <- function(start_date, end_date) {
  sched <- jsonlite::fromJSON(sprintf(SCHEDULE_URL, start_date, end_date), simplifyVector = FALSE)
  games <- unlist(lapply(sched$dates, function(d) d$games), recursive = FALSE)
  purrr::map_dfr(games, function(g) {
    tibble::tibble(
      game_pk = as.integer(g$gamePk),
      game_date = as.Date(g$officialDate),
      status = g$status$detailedState %||% NA_character_
    )
  }) |>
    dplyr::filter(status %in% c("Final", "Completed Early", "Game Over")) |>
    dplyr::distinct(game_pk, .keep_all = TRUE)
}

# Returns scheduled games missing from `have_game_pks`, per season window.
missing_games <- function(season_windows, have_game_pks) {
  purrr::imap_dfr(season_windows, function(win, season) {
    fetch_completed_games(win[1], win[2]) |>
      dplyr::mutate(season = as.integer(season))
  }) |>
    dplyr::mutate(in_data = game_pk %in% have_game_pks)
}
