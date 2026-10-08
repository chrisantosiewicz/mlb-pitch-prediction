# 07_logistic.R ---------------------------------------------------------------
# Fits the multinomial logistic context model on 2023-24, tunes the ridge
# penalty on 2025, and compares it with the mix baselines.
# Writes models/logistic_*.rds, models/logistic.json, docs/logistic_results.md.

suppressPackageStartupMessages(library(dplyr))
source("R/constants.R")
source("R/cleaning_log.R")   # md_table()
source("R/features.R")
source("R/context_model.R")

TRAIN_SEASONS <- 2023:2024
TUNE_SEASON <- 2025
LAMBDA_GRID <- c(3e-3, 1e-3, 3e-4, 1e-4, 3e-5)

load_features <- function(seasons) {
  bind_rows(lapply(seasons, function(s) arrow::read_parquet(sprintf("data/features/features_%d.parquet", s)))) |>
    prepare_factors()
}

train <- load_features(TRAIN_SEASONS)
tune <- load_features(TUNE_SEASON)
message("Train ", format(nrow(train), big.mark = ","), " / tune ", format(nrow(tune), big.mark = ","))

x_train <- model_matrix(train)
x_tune <- model_matrix(tune)
stopifnot(identical(colnames(x_train), colnames(x_tune)))
y_train <- factor(train$pitch_group, levels = PITCH_GROUPS)
y_tune <- factor(tune$pitch_group, levels = PITCH_GROUPS)
mix_train <- mix_matrix(train)
mix_tune <- mix_matrix(tune)

# ---- 8-pitch model ----
t0 <- Sys.time()
fit8 <- fit_context_model(x_train, y_train, log(mix_train), LAMBDA_GRID)
message("8-pitch fit: ", round(as.numeric(Sys.time() - t0, units = "mins"), 1), " min")
p8_by_lambda <- predict_context_model(fit8, x_tune, log(mix_tune))
lambda_scores8 <- tibble(lambda = fit8$lambda, log_loss = sapply(p8_by_lambda, log_loss, y = y_tune))
best8 <- which.min(lambda_scores8$log_loss)
p8 <- p8_by_lambda[[best8]]

# ---- family-then-pitch model ----
yf_train <- factor(PITCH_FAMILY[as.character(y_train)], levels = PITCH_FAMILIES)
t0 <- Sys.time()
fitf <- fit_context_model(x_train, yf_train, log(family_matrix(mix_train)), LAMBDA_GRID)
message("Family fit: ", round(as.numeric(Sys.time() - t0, units = "mins"), 1), " min")
pf_by_lambda <- predict_context_model(fitf, x_tune, log(family_matrix(mix_tune)))
pn_by_lambda <- lapply(pf_by_lambda, nested_to_pitch, p8_mix = mix_tune)
lambda_scoresf <- tibble(lambda = fitf$lambda, log_loss = sapply(pn_by_lambda, log_loss, y = y_tune))
bestf <- which.min(lambda_scoresf$log_loss)
pn <- pn_by_lambda[[bestf]]

# ---- comparison ----
candidates <- list(
  "L1 prior mix (Phase 1 baseline, relabel-repaired)" = mix_matrix(tune, "p1"),
  "L2 + current form (proposed second baseline)" = mix_matrix(tune, "p2"),
  "L3 + platoon tilt" = mix_tune,
  "Context model: family, then pitch from his mix" = pn,
  "Context model: all 8 pitches" = p8
)
comparison <- purrr::imap_dfr(candidates, ~ score_probs8(.x, y_tune) |> mutate(model = .y, .before = 1))

by_count <- score_by(candidates[c(3, 5)], y_tune, tune$count_str) |>
  select(model, group, pitches, log_loss) |>
  tidyr::pivot_wider(names_from = model, values_from = log_loss) |>
  rename(count = group)
names(by_count)[3:4] <- c("L3 mix", "context model")
by_count <- by_count |>
  mutate(gain = `L3 mix` - `context model`,
         group_order = match(count, FACTOR_LEVELS$count_str)) |>
  arrange(group_order) |> select(-group_order)

flag_group <- case_when(tune$relabeled ~ "relabel repaired",
                        tune$mix_changed ~ "mix changed",
                        TRUE ~ "stable")
by_flag <- score_by(candidates[c(1, 3, 4, 5)], y_tune, flag_group) |>
  select(group, model, pitches, log_loss, top1, family_top1)

by_role <- score_by(candidates[c(3, 5)], y_tune, ifelse(tune$is_starter, "SP", "RP")) |>
  select(group, model, pitches, log_loss, top1)

# What the model learned, in plain terms: average fastball / breaking / offspeed
# share by count, his mix vs. the model vs. what actually happened.
fam_actual <- factor(PITCH_FAMILY[tune$pitch_group], levels = PITCH_FAMILIES)
count_shift <- tibble(count = tune$count_str,
                      mix_fb = family_matrix(mix_tune)[, "FB"], model_fb = family_matrix(p8)[, "FB"],
                      actual_fb = fam_actual == "FB",
                      mix_br = family_matrix(mix_tune)[, "BR"], model_br = family_matrix(p8)[, "BR"],
                      actual_br = fam_actual == "BR") |>
  group_by(count) |>
  summarise(across(everything(), mean), .groups = "drop") |>
  mutate(order = match(count, FACTOR_LEVELS$count_str)) |>
  arrange(order) |>
  transmute(count,
            `fastball: his mix` = sprintf("%.0f%%", 100 * mix_fb),
            `fastball: model` = sprintf("%.0f%%", 100 * model_fb),
            `fastball: actual` = sprintf("%.0f%%", 100 * actual_fb),
            `breaking: his mix` = sprintf("%.0f%%", 100 * mix_br),
            `breaking: model` = sprintf("%.0f%%", 100 * model_br),
            `breaking: actual` = sprintf("%.0f%%", 100 * actual_br))

# Sequencing: after a whiff, how often is the same pitch repeated? (model vs actual)
after_whiff <- tune$prev1_result == "whiff" & tune$prev1_group %in% PITCH_GROUPS
repeat_idx <- cbind(which(after_whiff), match(as.character(tune$prev1_group[after_whiff]), PITCH_GROUPS))
repeat_table <- tibble(
  `pitches after a whiff` = sum(after_whiff),
  `his mix says repeat` = sprintf("%.1f%%", 100 * mean(mix_tune[repeat_idx])),
  `model says repeat` = sprintf("%.1f%%", 100 * mean(p8[repeat_idx])),
  `actually repeated` = sprintf("%.1f%%", 100 * mean(as.character(tune$pitch_group[after_whiff]) ==
                                                     as.character(tune$prev1_group[after_whiff])))
)

saveRDS(list(fit = fit8, lambda = fit8$lambda[best8], columns = colnames(x_train)), "models/logistic_pitch.rds")
saveRDS(list(fit = fitf, lambda = fitf$lambda[bestf], columns = colnames(x_train)), "models/logistic_family.rds")
jsonlite::write_json(list(
  model = "multinomial logistic (ridge) with pitcher-mix offset",
  offset_layer = "L3", formula = paste(deparse(FEATURE_FORMULA), collapse = ""),
  n_features = ncol(x_train), train = TRAIN_SEASONS, tuned_on = TUNE_SEASON,
  lambda_pitch = fit8$lambda[best8], lambda_family = fitf$lambda[bestf],
  tune_scores = comparison, created = as.character(Sys.time())
), "models/logistic.json", auto_unbox = TRUE, pretty = TRUE, digits = 6)
saveRDS(list(comparison = comparison, by_count = by_count, by_flag = by_flag, by_role = by_role,
             count_shift = count_shift, repeat_table = repeat_table,
             lambda8 = lambda_scores8, lambdaf = lambda_scoresf), "data/features/logistic_eval.rds")

fmt <- function(df) mutate(df,
  across(any_of(c("log_loss", "family_log_loss", "L3 mix", "context model", "gain")), ~ sprintf("%.3f", .x)),
  across(any_of(c("top1", "family_top1")), ~ sprintf("%.1f%%", 100 * .x)))

writeLines(c(
  "# Multinomial logistic results (tuning season)",
  "",
  sprintf("*Generated by `pipeline/07_logistic.R` on %s. Trained on %s, scored on %s. 2026 is still untouched.*",
          Sys.Date(), paste(range(TRAIN_SEASONS), collapse = "-"), TUNE_SEASON),
  "",
  "## Headline",
  "",
  md_table(fmt(comparison)),
  "",
  "*Family columns collapse the 8 pitches to fastball / breaking / offspeed.*",
  "",
  "## What the model learned: count",
  "",
  "Average share of fastballs and breaking balls by count, across all 2025 pitches: what the pitchers' own mixes say, what the model says, and what happened.",
  "",
  md_table(count_shift),
  "",
  "Gain over the L3 mix by count (log loss, lower is better):",
  "",
  md_table(fmt(by_count)),
  "",
  "## What the model learned: sequencing",
  "",
  md_table(repeat_table),
  "",
  "## Pitchers whose mix changed",
  "",
  "Pitches grouped by the flags available before the game: a repaired relabel, a flagged mix change, or neither.",
  "",
  md_table(fmt(by_flag)),
  "",
  "## By role",
  "",
  md_table(fmt(by_role)),
  "",
  "## Penalty tuning",
  "",
  "Ridge penalty (lambda) chosen by 2025 log loss.",
  "",
  md_table(mutate(lambda_scores8, log_loss = sprintf("%.4f", log_loss), model = "8 pitches") |>
             bind_rows(mutate(lambda_scoresf, log_loss = sprintf("%.4f", log_loss), model = "family"))),
  ""
), "docs/logistic_results.md")
message("Wrote docs/logistic_results.md")
