# 08_batter.R -----------------------------------------------------------------
# Builds the batter layer, tunes its pseudo-count on 2025, and writes
# data/features/batter_adj.parquet and models/batter.json.

suppressPackageStartupMessages(library(dplyr))
source("R/constants.R")
source("R/clean.R")
source("R/batter.R")
source("R/context_model.R")

TUNE_SEASON <- 2025
TAU_GRID <- c(25, 50, 100, 200, 400, 800, 1600)

con <- connect_duckdb()
hist <- batter_history(con)
DBI::dbDisconnect(con, shutdown = TRUE)

tune <- arrow::read_parquet(sprintf("data/features/features_%d.parquet", TUNE_SEASON)) |>
  select(batter, game_pk, pitch_group, starts_with("p3_"))
y <- factor(tune$pitch_group, levels = PITCH_GROUPS)
p3 <- mix_matrix(tune)

scores <- tibble(tau = TAU_GRID, log_loss = sapply(TAU_GRID, function(tau) {
  adj <- batter_adjustments(filter(hist, game_year == TUNE_SEASON), tau)
  joined <- left_join(select(tune, batter, game_pk), adj, by = c("batter", "game_pk"))
  log_loss(apply_batter_tilt(p3, select(joined, starts_with("badj_"))), y)
}))
best <- slice_min(scores, log_loss, n = 1)
message(sprintf("L3 alone: %.4f | best tau = %s: %.4f", log_loss(p3, y), best$tau, best$log_loss))
print(scores)

adj <- batter_adjustments(hist, best$tau)
arrow::write_parquet(adj, "data/features/batter_adj.parquet")
jsonlite::write_json(list(tau = best$tau, tuned_on = TUNE_SEASON, l3_log_loss = log_loss(p3, y),
                          l3_plus_batter_log_loss = best$log_loss, grid = scores,
                          created = as.character(Sys.time())),
                     "models/batter.json", auto_unbox = TRUE, pretty = TRUE, digits = 6)
