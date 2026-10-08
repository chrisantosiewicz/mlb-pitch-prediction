# players.R -------------------------------------------------------------------
# Player names, handedness and primary position from the MLB Stats API.
# Statcast's `player_name` is the batter's name only, so pitcher names come
# from here. Primary position is also how position players pitching are found.

PLAYERS_PATH <- "data/reference/players.parquet"
PEOPLE_URL <- "https://statsapi.mlb.com/api/v1/people?personIds="
PEOPLE_BATCH_SIZE <- 100

fetch_people_batch <- function(ids) {
  url <- paste0(PEOPLE_URL, paste(ids, collapse = ","))
  people <- jsonlite::fromJSON(url, simplifyVector = FALSE)$people
  purrr::map_dfr(people, function(p) {
    tibble::tibble(
      player_id = as.integer(p$id),
      full_name = p$fullName %||% NA_character_,
      last_first = p$lastFirstName %||% NA_character_,
      primary_position = p$primaryPosition$abbreviation %||% NA_character_,
      position_type = p$primaryPosition$type %||% NA_character_,
      bat_side = p$batSide$code %||% NA_character_,
      pitch_hand = p$pitchHand$code %||% NA_character_
    )
  })
}

# Returns the player table, fetching only ids not already cached.
get_players <- function(ids) {
  ids <- unique(as.integer(ids[!is.na(ids)]))
  cached <- if (file.exists(PLAYERS_PATH)) arrow::read_parquet(PLAYERS_PATH) else NULL
  missing <- setdiff(ids, cached$player_id)

  if (length(missing)) {
    batches <- split(missing, ceiling(seq_along(missing) / PEOPLE_BATCH_SIZE))
    fetched <- purrr::map_dfr(batches, function(b) {
      Sys.sleep(0.25)
      fetch_people_batch(b)
    })
    cached <- dplyr::bind_rows(cached, fetched)
    dir.create(dirname(PLAYERS_PATH), recursive = TRUE, showWarnings = FALSE)
    arrow::write_parquet(cached, PLAYERS_PATH)
  }
  dplyr::filter(cached, player_id %in% ids)
}
