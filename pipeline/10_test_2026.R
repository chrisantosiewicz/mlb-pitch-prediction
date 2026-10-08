# 10_test_2026.R --------------------------------------------------------------
# The one-time test: refit every context model on 2023-25 with settings fixed
# on 2025, score 2026 exactly as written in docs/preregistration.md.
# Writes docs/test_results.md, docs/figures/*.png, models/final_*.rds and
# data/predictions/pred_2026.parquet.

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})
source("R/constants.R")
source("R/cleaning_log.R")   # md_table()
source("R/features.R")
source("R/context_model.R")
source("R/boost_model.R")
source("R/model_data.R")
source("R/evaluation.R")

TRAIN_SEASONS <- 2023:2025
TEST_SEASON <- 2026

tuning <- jsonlite::read_json("models/tuning.json")
train <- load_model_data(TRAIN_SEASONS)
test <- load_model_data(TEST_SEASON)
y_train <- factor(train$pitch_group, levels = PITCH_GROUPS)
y_test <- factor(test$pitch_group, levels = PITCH_GROUPS)
x_train <- model_matrix(train)
x_test <- model_matrix(test)
message("Train ", format(nrow(train), big.mark = ","), " / test ", format(nrow(test), big.mark = ","))

# ---- refit (settings fixed on 2025) ----
fit8 <- fit_context_model(x_train, y_train, offset_matrix(train, FALSE), tuning$lambda_pitch)
p8 <- predict_context_model(fit8, x_test, offset_matrix(test, FALSE))[[1]]

yf_train <- factor(PITCH_FAMILY[as.character(y_train)], levels = PITCH_FAMILIES)
fitf <- fit_context_model(x_train, yf_train, log(family_matrix(mix_matrix(train))), tuning$lambda_family)
pf <- nested_to_pitch(predict_context_model(fitf, x_test, log(family_matrix(mix_matrix(test))))[[1]],
                      mix_matrix(test))

fit8b <- fit_context_model(x_train, y_train, offset_matrix(train, TRUE), tuning$lambda_pitch)
p8b <- predict_context_model(fit8b, x_test, offset_matrix(test, TRUE))[[1]]

use_b <- isTRUE(tuning$use_batter_layer)
d_train <- boost_dmatrix(train, offset_matrix(train, use_b))
d_test <- boost_dmatrix(test, offset_matrix(test, use_b))
boost <- xgboost::xgb.train(c(BOOST_PARAMS, list(nthread = parallel::detectCores())), d_train,
                            nrounds = tuning$boost_rounds, verbose = 0)
pb <- predict_boost(boost, d_test)
message("Refits done")

# Pre-registered rule: family version on relabel-repaired pitcher-games.
p_rule <- p8
p_rule[test$relabeled, ] <- pf[test$relabeled, ]

models <- list(
  "L1 prior mix (Phase 1 baseline)" = mix_matrix(test, "p1"),
  "L2 + current form" = mix_matrix(test, "p2"),
  "L3 + platoon tilt" = mix_matrix(test, "p3"),
  "Logistic, 8 pitches" = p8,
  "Logistic, family then pitch" = pf,
  "Logistic, 8 pitches + batter layer" = p8b,
  "xgboost" = pb,
  "Pre-registered rule (family on relabels)" = p_rule
)
scores <- purrr::imap_dfr(models, ~ score_probs8(.x, y_test) |> mutate(model = .y, .before = 1))
ll <- lapply(models, pitch_log_loss, y = y_test)

# ---- bootstrap comparisons ----
cmp <- function(a, b, idx = seq_along(y_test)) {
  bootstrap_difference(ll[[a]][idx], ll[[b]][idx], test$game_pk[idx]) |>
    mutate(comparison = paste(a, "vs.", b), pitches = length(idx), .before = 1)
}
rel <- which(test$relabeled)
comparisons <- bind_rows(
  cmp("L3 + platoon tilt", "L1 prior mix (Phase 1 baseline)"),
  cmp("Logistic, 8 pitches", "L3 + platoon tilt"),
  cmp("Logistic, 8 pitches + batter layer", "Logistic, 8 pitches"),
  cmp("xgboost", "Logistic, 8 pitches"),
  cmp("xgboost", "Logistic, 8 pitches + batter layer"),
  cmp("xgboost", "L1 prior mix (Phase 1 baseline)"),
  cmp("Pre-registered rule (family on relabels)", "Logistic, 8 pitches"),
  cmp("Pre-registered rule (family on relabels)", "Logistic, 8 pitches", rel) |>
    mutate(comparison = paste(comparison, "(relabel-repaired pitches only)"))
)
beats <- function(a, b) {
  r <- filter(comparisons, comparison == paste(a, "vs.", b))
  nrow(r) == 1 && r$upper < 0
}

# ---- app model, per the pre-registered decision rule ----
contenders <- c("Logistic, 8 pitches", "Logistic, 8 pitches + batter layer", "xgboost")
best_name <- scores |> filter(model %in% contenders) |> slice_min(log_loss, n = 1) |> pull(model)
simplest_logistic <- scores |> filter(model %in% contenders[1:2]) |> slice_min(log_loss, n = 1) |> pull(model)
app_model <- if (best_name == "xgboost" && !beats("xgboost", simplest_logistic)) simplest_logistic else best_name
rule_kept <- beats("Pre-registered rule (family on relabels)", "Logistic, 8 pitches") ||
  (filter(comparisons, grepl("relabel-repaired", comparison))$upper < 0 &&
     filter(comparisons, comparison == "Pre-registered rule (family on relabels) vs. Logistic, 8 pitches")$lower <= 0)
p_app <- models[[app_model]]
message("App model: ", app_model)

# ---- calibration ----
dir.create("docs/figures", recursive = TRUE, showWarnings = FALSE)
cal <- bind_rows(calibration_table(p_app, y_test) |> mutate(model = app_model),
                 calibration_table(models[["L3 + platoon tilt"]], y_test) |> mutate(model = "L3 mix (no context)"))
ggsave("docs/figures/calibration_pitch.png",
       plot_calibration(cal, "Calibration by pitch type, 2026", PITCH_GROUP_NAMES),
       width = 10, height = 5.8, dpi = 150, bg = "white")
yf_test <- factor(PITCH_FAMILY[as.character(y_test)], levels = PITCH_FAMILIES)
cal_f <- bind_rows(calibration_table(family_matrix(p_app), yf_test) |> mutate(model = app_model),
                   calibration_table(family_matrix(models[["L3 + platoon tilt"]]), yf_test) |>
                     mutate(model = "L3 mix (no context)"))
ggsave("docs/figures/calibration_family.png",
       plot_calibration(cal_f, "Calibration by pitch family, 2026", PITCH_FAMILY_NAMES) +
         facet_wrap(~ class, nrow = 1),
       width = 10, height = 4.2, dpi = 150, bg = "white")
ece <- calibration_error(filter(cal, model == app_model)) |>
  mutate(class = PITCH_GROUP_NAMES[class], ece = sprintf("%.1f pts", 100 * ece))

# ---- per pitcher ----
per_pitcher <- tibble(pitcher = test$pitcher, pitcher_name = test$pitcher_name,
                      app = ll[[app_model]], l1 = ll[[1]], l3 = ll[[3]]) |>
  group_by(pitcher, pitcher_name) |>
  summarise(pitches = n(), app = mean(app), l1 = mean(l1), l3 = mean(l3), .groups = "drop") |>
  filter(pitches >= MIN_PITCHES_REPORTED) |>
  mutate(gain_vs_l1 = l1 - app, gain_vs_l3 = l3 - app)
pp_summary <- tibble(
  pitchers = nrow(per_pitcher),
  `beat L1 (Phase 1 baseline)` = sprintf("%.0f%%", 100 * mean(per_pitcher$gain_vs_l1 > 0)),
  `beat L3 (best mix)` = sprintf("%.0f%%", 100 * mean(per_pitcher$gain_vs_l3 > 0)),
  `median gain vs L3` = sprintf("%.3f", median(per_pitcher$gain_vs_l3))
)
ggsave("docs/figures/per_pitcher_gain.png",
       ggplot(per_pitcher, aes(gain_vs_l3)) +
         geom_histogram(bins = 40, fill = "#1b6ca8", colour = "white") +
         geom_vline(xintercept = 0, linetype = "dashed") +
         labs(title = sprintf("Per-pitcher log-loss gain over the L3 mix, 2026 (%d pitchers, %d+ pitches)",
                              nrow(per_pitcher), MIN_PITCHES_REPORTED),
              x = "Gain (positive = context model better)", y = "Pitchers") +
         theme_minimal(base_size = 11),
       width = 8, height = 4.5, dpi = 150, bg = "white")

pp_cols <- function(df) df |> transmute(pitcher_name, pitches, `L3 log loss` = sprintf("%.3f", l3),
                                        `model log loss` = sprintf("%.3f", app),
                                        `gain` = sprintf("%+.3f", gain_vs_l3))

# ---- breakdowns ----
two <- models[c("L3 + platoon tilt", app_model)]
by_count <- score_by(two, y_test, test$count_str) |>
  select(group, model, log_loss) |>
  tidyr::pivot_wider(names_from = model, values_from = log_loss) |>
  rename(count = group) |>
  mutate(order = match(count, FACTOR_LEVELS$count_str)) |> arrange(order) |> select(-order)
names(by_count)[2:3] <- c("L3 mix", "model")
by_count <- mutate(by_count, gain = `L3 mix` - model)
flag_group <- case_when(test$relabeled ~ "relabel repaired", test$mix_changed ~ "mix changed", TRUE ~ "stable")
by_flag <- score_by(models[c(1, 3, 4, 5, 8)], y_test, flag_group) |>
  select(group, model, pitches, log_loss, top1, family_top1) |> arrange(group, log_loss)
by_role <- score_by(two, y_test, ifelse(test$is_starter, "SP", "RP")) |> select(group, model, pitches, log_loss, top1)

# ---- save ----
saveRDS(list(fit = fit8, lambda = tuning$lambda_pitch, columns = colnames(x_train)), "models/final_logistic_pitch.rds")
saveRDS(list(fit = fit8b, lambda = tuning$lambda_pitch, columns = colnames(x_train)), "models/final_logistic_batter.rds")
saveRDS(list(fit = fitf, lambda = tuning$lambda_family, columns = colnames(x_train)), "models/final_logistic_family.rds")
xgboost::xgb.save(boost, "models/final_xgboost.ubj")
dir.create("data/predictions", recursive = TRUE, showWarnings = FALSE)
arrow::write_parquet(bind_cols(select(test, game_pk, pa_id, pitch_number, pitcher, batter, pitch_group),
                               tibble::as_tibble(p_app, .name_repair = ~ paste0("prob_", .x))),
                     "data/predictions/pred_2026.parquet")
jsonlite::write_json(list(app_model = app_model, rule_kept = rule_kept, scores = scores,
                          comparisons = comparisons, created = as.character(Sys.time())),
                     "models/final.json", auto_unbox = TRUE, pretty = TRUE, digits = 6)
saveRDS(list(scores = scores, comparisons = comparisons, per_pitcher = per_pitcher, by_count = by_count,
             by_flag = by_flag, by_role = by_role, ece = ece, app_model = app_model, rule_kept = rule_kept),
        "data/predictions/test_eval.rds")

# ---- report ----
source("R/test_report.R")
write_test_report(readRDS("data/predictions/test_eval.rds"), "docs/test_results.md")
message("Wrote docs/test_results.md")
