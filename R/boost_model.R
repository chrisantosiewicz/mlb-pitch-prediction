# boost_model.R ---------------------------------------------------------------
# Gradient boosting (xgboost) with the same starting point as the logistic
# model: the pitcher's mix (plus the batter tilt) enters as a base margin, so
# the trees only learn how the situation moves him away from it. Trees can
# find interactions the logistic model would need written by hand, e.g.
# two strikes x same-handed hitter x previous pitch was a slider that missed.

BOOST_PARAMS <- list(
  objective = "multi:softprob", num_class = length(PITCH_GROUPS),
  eta = 0.1, max_depth = 6, min_child_weight = 50,
  subsample = 0.8, colsample_bytree = 0.8,
  tree_method = "hist", eval_metric = "mlogloss"
)

# Extra numeric inputs trees can use directly (the logistic model gets these
# only through the offset or buckets).
boost_extra_columns <- function(df) {
  cbind(
    as.matrix(df[paste0("p3_", PITCH_GROUPS)]),
    as.matrix(df[paste0("badj_", PITCH_GROUPS)]),
    history_pitches = df$history_pitches,
    season_pitches_before = df$season_pitches_before,
    mix_tvd = df$mix_tvd,
    gtd_n = df$gtd_n,
    batter_pitches_seen = df$batter_pitches_seen
  )
}

boost_matrix <- function(df) {
  x <- cbind(model_matrix(df), Matrix::Matrix(boost_extra_columns(df), sparse = TRUE))
  x
}

boost_dmatrix <- function(df, offset) {
  xgboost::xgb.DMatrix(boost_matrix(df),
                       label = as.integer(factor(df$pitch_group, levels = PITCH_GROUPS)) - 1,
                       base_margin = offset)
}

predict_boost <- function(fit, dmat) {
  p <- stats::predict(fit, dmat)
  if (is.null(dim(p))) p <- matrix(p, ncol = length(PITCH_GROUPS), byrow = TRUE)
  colnames(p) <- PITCH_GROUPS
  p
}
