# model_data.R ----------------------------------------------------------------
# Loads feature tables joined with the batter layer, ready for modeling.

load_model_data <- function(seasons) {
  badj <- arrow::read_parquet("data/features/batter_adj.parquet") |>
    dplyr::select(-game_year)
  dplyr::bind_rows(lapply(seasons, function(s)
    arrow::read_parquet(sprintf("data/features/features_%d.parquet", s)))) |>
    dplyr::left_join(badj, by = c("batter", "game_pk")) |>
    dplyr::mutate(dplyr::across(dplyr::starts_with("badj_"), ~ dplyr::coalesce(.x, 0)),
                  batter_pitches_seen = dplyr::coalesce(batter_pitches_seen, 0)) |>
    prepare_factors()
}

batter_matrix <- function(df) as.matrix(df[paste0("badj_", PITCH_GROUPS)])

# Offsets: log of the pitcher's mix, optionally tilted by the batter layer.
offset_matrix <- function(df, batter = TRUE) {
  o <- log(mix_matrix(df))
  if (batter) o <- o + batter_matrix(df)
  o
}
