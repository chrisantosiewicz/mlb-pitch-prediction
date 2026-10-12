# 17_ingame_model.R -----------------------------------------------------------
# Does adapting to the pitcher's in-game mix help? Tunes the in-game layer on
# 2025, retrains xgboost (train 2023-24, early stopping on 2025) and compares
# with the current model. Writes models/ingame_tuning.json and
# models/xgboost_ingame_tune.ubj.

suppressPackageStartupMessages(library(dplyr))
for (f in c("constants", "features", "context_model", "boost_model", "model_data", "ingame")) {
  source(file.path("R", paste0(f, ".R")))
}

TAU_GAME_GRID <- c(10, 15, 25, 35, 50, Inf)
MAX_ROUNDS <- 2000
EARLY_STOP <- 30

with_ingame <- function(seasons) {
  load_model_data(seasons) |> left_join(load_ingame(seasons), by = c("pa_id", "pitch_number"))
}
train <- with_ingame(2023:2024)
tune <- with_ingame(2025)
y_tune <- factor(tune$pitch_group, levels = PITCH_GROUPS)
stopifnot(!anyNA(tune$gtd_FF), !anyNA(train$gtd_FF))

# 1. Tune the in-game layer alone (no context model), with the batter tilt.
layer_scores <- tibble(tau_game = TAU_GAME_GRID, log_loss = sapply(TAU_GAME_GRID, function(tau) {
  p <- ingame_mix(tune, tau) * exp(batter_matrix(tune))
  log_loss(p / rowSums(p), y_tune)
}))
print(layer_scores)
tau_best <- layer_scores$tau_game[which.min(layer_scores$log_loss)]
message("Best tau_game: ", tau_best)

# 2. Retrain xgboost with the in-game offset and tilt features.
offset_for <- function(df) log(pmax(ingame_mix(df, tau_best), 1e-6)) + batter_matrix(df)
dmat <- function(df) {
  x <- cbind(boost_matrix(df), Matrix::Matrix(ingame_features(df), sparse = TRUE))
  xgboost::xgb.DMatrix(x, label = as.integer(factor(df$pitch_group, levels = PITCH_GROUPS)) - 1,
                       base_margin = offset_for(df))
}
d_train <- dmat(train); d_tune <- dmat(tune)
t0 <- Sys.time()
fit <- xgboost::xgb.train(c(BOOST_PARAMS, list(nthread = parallel::detectCores())), d_train,
                          nrounds = MAX_ROUNDS, evals = list(tune = d_tune),
                          early_stopping_rounds = EARLY_STOP, verbose = 1, print_every_n = 50)
minutes <- round(as.numeric(Sys.time() - t0, units = "mins"), 1)
rounds <- as.integer(xgboost::xgb.attributes(fit)$best_iteration)
p_new <- predict_boost(fit, d_tune)

# 3. Compare with the current model on the same 2025 pitches.
tuning <- jsonlite::read_json("models/tuning.json")
old_2025 <- dplyr::bind_rows(tuning$tune_scores) |> dplyr::filter(model == "xgboost")

starter <- tune$is_starter
tto <- pmin(as.integer(as.character(tune$tto)), 3)
seg <- function(idx, label) tibble(segment = label, pitches = sum(idx),
                                   log_loss = log_loss(p_new[idx, , drop = FALSE], y_tune[idx]),
                                   top1 = top1(p_new[idx, , drop = FALSE], y_tune[idx]))
new_scores <- bind_rows(seg(rep(TRUE, nrow(tune)), "all"), seg(starter, "starters"),
                        seg(starter & tto >= 2, "starters, 2nd+ time through"), seg(!starter, "relievers"))
print(new_scores)
message(sprintf("Current xgboost on 2025: log loss %.4f, top-1 %.4f | new: %.4f, %.4f (%d rounds, %s min)",
                old_2025$log_loss, old_2025$top1, new_scores$log_loss[1], new_scores$top1[1], rounds, minutes))

xgboost::xgb.save(fit, "models/xgboost_ingame_tune.ubj")
saveRDS(list(p_new = p_new, idx = tune[c("pa_id", "pitch_number")]), "data/features/ingame_tune_preds.rds")
jsonlite::write_json(list(tau_game = tau_best, layer_scores = layer_scores, boost_rounds = rounds,
                          new_2025 = new_scores, old_2025 = old_2025, minutes = minutes,
                          created = as.character(Sys.time())),
                     "models/ingame_tuning.json", auto_unbox = TRUE, pretty = TRUE, digits = 6)
