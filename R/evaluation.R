# evaluation.R ----------------------------------------------------------------
# Test-season evaluation helpers: per-pitch log loss, game bootstrap,
# calibration tables and plots.

pitch_log_loss <- function(p, y) {
  idx <- cbind(seq_along(y), match(as.character(y), colnames(p)))
  -log(pmax(p[idx], 1e-15))
}

# Bootstrap over games: 95% interval for the mean log-loss difference
# (model minus reference). Negative = model is better.
bootstrap_difference <- function(ll_model, ll_ref, game, draws = 500, seed = 2026) {
  g <- as.integer(factor(game))
  diff_sum <- tapply(ll_model - ll_ref, g, sum)
  n_per_game <- tapply(rep(1, length(g)), g, sum)
  set.seed(seed)
  n_games <- length(diff_sum)
  boots <- replicate(draws, {
    w <- tabulate(sample.int(n_games, n_games, replace = TRUE), nbins = n_games)
    sum(w * diff_sum) / sum(w * n_per_game)
  })
  tibble::tibble(difference = mean(ll_model - ll_ref),
                 lower = stats::quantile(boots, 0.025, names = FALSE),
                 upper = stats::quantile(boots, 0.975, names = FALSE))
}

calibration_table <- function(p, y, bins = 10) {
  purrr::map_dfr(colnames(p), function(k) {
    tibble::tibble(class = k, predicted = p[, k], actual = as.numeric(as.character(y) == k)) |>
      dplyr::mutate(bin = cut(predicted, breaks = seq(0, 1, length.out = bins + 1), include.lowest = TRUE)) |>
      dplyr::group_by(class, bin) |>
      dplyr::summarise(predicted = mean(predicted), actual = mean(actual), n = dplyr::n(), .groups = "drop")
  })
}

# Expected calibration error: average |predicted - actual| weighted by bin size.
calibration_error <- function(cal) {
  cal |>
    dplyr::group_by(class) |>
    dplyr::summarise(ece = sum(n * abs(predicted - actual)) / sum(n), .groups = "drop")
}

plot_calibration <- function(cal, title, labels = NULL) {
  if (!is.null(labels)) cal$class <- factor(labels[cal$class], levels = labels)
  ggplot2::ggplot(dplyr::filter(cal, n >= 200), ggplot2::aes(predicted, actual, colour = model)) +
    ggplot2::geom_abline(linetype = "dashed", colour = "grey60") +
    ggplot2::geom_line() +
    ggplot2::geom_point(ggplot2::aes(size = n), alpha = 0.7) +
    ggplot2::facet_wrap(~ class, nrow = 2) +
    ggplot2::scale_x_continuous(labels = scales::percent, limits = c(0, 1)) +
    ggplot2::scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
    ggplot2::scale_size_area(max_size = 3, guide = "none") +
    ggplot2::scale_colour_manual(values = c("#1b6ca8", "#d1495b")) +
    ggplot2::coord_equal() +
    ggplot2::labs(title = title, x = "Predicted probability", y = "Actual frequency", colour = NULL,
                  caption = "Dashed line = perfect calibration. Bins with fewer than 200 pitches hidden.") +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(legend.position = "bottom")
}
