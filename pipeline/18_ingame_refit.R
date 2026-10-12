# 18_ingame_refit.R -----------------------------------------------------------
# Refits the in-game xgboost on 2023-25 with the rounds and tau_game chosen on
# 2025 (same procedure as the final model), for live use and the postseason
# replays. Writes models/final_xgboost_ingame.ubj.

suppressPackageStartupMessages(library(dplyr))
for (f in c("constants", "features", "context_model", "boost_model", "model_data", "ingame")) {
  source(file.path("R", paste0(f, ".R")))
}
cfg <- jsonlite::read_json("models/ingame_tuning.json")
train <- load_model_data(2023:2025) |> left_join(load_ingame(2023:2025), by = c("pa_id", "pitch_number"))
x <- cbind(boost_matrix(train), Matrix::Matrix(ingame_features(train), sparse = TRUE))
d <- xgboost::xgb.DMatrix(x, label = as.integer(factor(train$pitch_group, levels = PITCH_GROUPS)) - 1,
                          base_margin = log(pmax(ingame_mix(train, cfg$tau_game), 1e-6)) + batter_matrix(train))
fit <- xgboost::xgb.train(c(BOOST_PARAMS, list(nthread = parallel::detectCores())), d,
                          nrounds = cfg$boost_rounds, verbose = 0)
xgboost::xgb.save(fit, "models/final_xgboost_ingame.ubj")
message("Wrote models/final_xgboost_ingame.ubj")
