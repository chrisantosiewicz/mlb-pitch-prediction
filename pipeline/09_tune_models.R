# 09_tune_models.R ------------------------------------------------------------
# On the 2025 tuning season: does the batter layer help the logistic model,
# and how many boosting rounds should xgboost use? Writes models/tuning.json.

suppressPackageStartupMessages(library(dplyr))
source("R/constants.R")
source("R/features.R")
source("R/context_model.R")
source("R/boost_model.R")
source("R/model_data.R")

TRAIN_SEASONS <- 2023:2024
TUNE_SEASON <- 2025
MAX_ROUNDS <- 2000
EARLY_STOP <- 30

logistic_meta <- jsonlite::read_json("models/logistic.json")
train <- load_model_data(TRAIN_SEASONS)
tune <- load_model_data(TUNE_SEASON)
y_train <- factor(train$pitch_group, levels = PITCH_GROUPS)
y_tune <- factor(tune$pitch_group, levels = PITCH_GROUPS)
x_train <- model_matrix(train)
x_tune <- model_matrix(tune)

# Logistic with and without the batter tilt in the offset (penalty from Phase 2).
lambda <- logistic_meta$lambda_pitch
fit_no_b <- fit_context_model(x_train, y_train, offset_matrix(train, FALSE), lambda)
fit_b <- fit_context_model(x_train, y_train, offset_matrix(train, TRUE), lambda)
p_no_b <- predict_context_model(fit_no_b, x_tune, offset_matrix(tune, FALSE))[[1]]
p_b <- predict_context_model(fit_b, x_tune, offset_matrix(tune, TRUE))[[1]]
logistic_scores <- bind_rows(
  score_probs8(p_no_b, y_tune) |> mutate(model = "logistic, 8 pitches"),
  score_probs8(p_b, y_tune) |> mutate(model = "logistic, 8 pitches + batter layer"))
print(logistic_scores)
use_batter <- logistic_scores$log_loss[2] < logistic_scores$log_loss[1]

# Boosting: early stopping on 2025 picks the number of rounds.
d_train <- boost_dmatrix(train, offset_matrix(train, use_batter))
d_tune <- boost_dmatrix(tune, offset_matrix(tune, use_batter))
params <- c(BOOST_PARAMS, list(nthread = parallel::detectCores()))
t0 <- Sys.time()
boost <- xgboost::xgb.train(params, d_train, nrounds = MAX_ROUNDS, evals = list(tune = d_tune),
                            early_stopping_rounds = EARLY_STOP, verbose = 1, print_every_n = 50)
minutes <- round(as.numeric(Sys.time() - t0, units = "mins"), 1)
best_rounds <- as.integer(xgboost::xgb.attributes(boost)$best_iteration)
p_boost <- predict_boost(boost, d_tune)
boost_score <- score_probs8(p_boost, y_tune) |> mutate(model = "xgboost")
message(sprintf("xgboost: %d rounds in %s min, log loss %.4f", best_rounds, minutes, boost_score$log_loss))

jsonlite::write_json(list(
  use_batter_layer = use_batter, lambda_pitch = lambda,
  lambda_family = logistic_meta$lambda_family,
  boost_params = BOOST_PARAMS, boost_rounds = best_rounds, boost_minutes = minutes,
  tune_scores = bind_rows(logistic_scores, boost_score),
  train = TRAIN_SEASONS, tuned_on = TUNE_SEASON, created = as.character(Sys.time())
), "models/tuning.json", auto_unbox = TRUE, pretty = TRUE, digits = 6)
message("Wrote models/tuning.json")
