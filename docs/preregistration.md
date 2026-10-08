# 2026 test plan (written before 2026 is scored)

*Committed 2026-10-08, before any model is scored on 2026. The git history shows this file existed before the 2026 results did.*

The 2026 regular season is the test season. It is scored **once**, with every setting fixed from the 2025 tuning season. Nothing below changes after seeing 2026 results; anything added later is labeled as exploratory.

## Final fits

All context models are refit on 2023-2025 with the settings chosen on 2025 (penalty, mix settings, boosting rounds), then score 2026.

## Models scored

1. L1 prior mix (Phase 1 baseline)
2. L2 + current form (second baseline)
3. L3 + platoon tilt
4. Logistic, all 8 pitches
5. Logistic, family then pitch
6. Logistic, 8 pitches + batter layer (if it beats #4 on 2025)
7. Gradient boosting (xgboost) with the same mix offset and features
8. **Pre-registered rule (Chris, 2026-10-08):** the family-then-pitch logistic for relabel-repaired pitcher-games, the 8-pitch logistic everywhere else. Compared with #4 on the relabel-repaired pitches and overall.

## Metrics

- Log loss (headline), top-1 accuracy, family log loss and family top-1
- Calibration: predicted vs. actual frequency, 10 bins per pitch type and per family
- Per pitcher (500+ pitches in 2026): log loss vs. L1 and vs. L3
- By count, by role, by flag (relabel repaired / mix changed / stable)
- Uncertainty: 95% intervals for log-loss differences from a bootstrap that resamples games (500 draws)

## Decision rules

- A model "beats" another only if the 95% bootstrap interval for the log-loss difference excludes zero.
- The model the app uses is the one with the best 2026 log loss among models that beat L3. If boosting and logistic are within each other's intervals, the app uses logistic, because it's simpler to explain.
- The pre-registered rule is kept only if it beats #4 on relabel-repaired pitches AND does not lose overall.
