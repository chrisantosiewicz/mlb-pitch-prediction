# context_model.R -------------------------------------------------------------
# Multinomial logistic regression that starts from each pitcher's own mix and
# learns how the situation shifts him away from it.
#
#   log-odds(pitch k) = log(his mix for k)  +  context effects for k
#
# His mix (layer L3: prior + current form + platoon) enters as a fixed offset,
# so the model never has to learn who throws what. The coefficients are then
# league-wide answers to questions like "how much more often do pitchers go
# to their breaking ball 0-2 than 0-0, relative to their usual mix?"
#
# Two versions:
#   pitch  : 8 classes directly
#   family : context picks fastball / breaking / offspeed; within a family the
#            pitch comes from his mix. Tests whether count and sequence mainly
#            decide the family rather than the specific pitch.

mix_matrix <- function(df, layer = "p3") {
  m <- as.matrix(df[paste0(layer, "_", PITCH_GROUPS)])
  colnames(m) <- PITCH_GROUPS
  m
}

family_matrix <- function(p8) {
  sapply(PITCH_FAMILIES, function(f) rowSums(p8[, PITCH_FAMILY == f, drop = FALSE]))
}

fit_context_model <- function(x, y, offset, lambda) {
  glmnet::glmnet(x, y, family = "multinomial", offset = offset, alpha = 0,
                 lambda = lambda, standardize = TRUE, type.multinomial = "ungrouped")
}

# n x K probabilities for each lambda: a list of matrices.
predict_context_model <- function(fit, x, offset) {
  arr <- stats::predict(fit, newx = x, newoffset = offset, type = "response")
  lapply(seq_len(dim(arr)[3]), function(i) {
    m <- arr[, , i]
    colnames(m) <- dimnames(arr)[[2]]
    m
  })
}

# Family version -> 8-pitch probabilities: P(family) x P(pitch | family, his mix).
nested_to_pitch <- function(p_family, p8_mix) {
  fam_mix <- family_matrix(p8_mix)
  out <- p8_mix
  for (k in seq_along(PITCH_GROUPS)) {
    f <- PITCH_FAMILY[[PITCH_GROUPS[k]]]
    out[, k] <- p_family[, f] * p8_mix[, k] / fam_mix[, f]
  }
  out
}

log_loss <- function(p, y) {
  idx <- cbind(seq_along(y), match(as.character(y), colnames(p)))
  -mean(log(pmax(p[idx], 1e-15)))
}

top1 <- function(p, y) mean(colnames(p)[max.col(p, ties.method = "first")] == as.character(y))

score_probs8 <- function(p8, y) {
  yf <- factor(PITCH_FAMILY[as.character(y)], levels = PITCH_FAMILIES)
  pf <- family_matrix(p8)
  tibble::tibble(log_loss = log_loss(p8, y), top1 = top1(p8, y),
                 family_log_loss = log_loss(pf, yf), family_top1 = top1(pf, yf))
}

score_by <- function(p8_list, y, group) {
  purrr::imap_dfr(p8_list, function(p8, name) {
    purrr::map_dfr(split(seq_along(y), group), function(idx) {
      score_probs8(p8[idx, , drop = FALSE], y[idx]) |> dplyr::mutate(pitches = length(idx))
    }, .id = "group") |> dplyr::mutate(model = name)
  })
}
