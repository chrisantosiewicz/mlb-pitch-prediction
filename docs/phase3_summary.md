# Phase 3 summary: batter layer, gradient boosting, the 2026 test

*Written 2026-10-08 for review. Full tables: [test_results.md](test_results.md). The test plan was committed before 2026 was scored: [preregistration.md](preregistration.md).*

## Headline (2026, scored once)

| Model | Log loss | Top-1 | Family top-1 |
|---|---|---|---|
| L1 prior mix (Phase 1 baseline) | 1.580 | 37.2% | 56.2% |
| L3 best mix (current form + platoon) | 1.390 | 40.1% | 56.8% |
| Logistic, 8 pitches | 1.327 | 43.3% | 58.4% |
| Logistic + batter layer | 1.324 | 43.6% | 58.7% |
| **xgboost (app model)** | **1.283** | **44.7%** | **59.7%** |

Every step in that ladder is a real improvement: in all 500 bootstrap resamples of 2026 games, the interval for each difference excludes zero. The 2026 numbers are a little worse than 2025 for every model, baselines included. That's what an honest held-out season looks like, and the size of each gain held up.

## What each piece adds

| Step | Log-loss gain | 95% interval |
|---|---|---|
| Knowing the pitcher better (L1 → L3) | 0.190 | 0.186 to 0.194 |
| Situation, logistic (L3 → logistic) | 0.064 | 0.062 to 0.065 |
| Batter layer | 0.003 | 0.003 to 0.004 |
| Trees vs. logistic (xgboost → logistic + batter) | 0.041 | 0.039 to 0.042 |

- **xgboost beats logistic by a clear margin**, so per the pre-registered rule the app uses xgboost. The logistic model stays as the explainer: its coefficients answer "what does a 0-2 count do?", and xgboost then shows interactions add as much again.
- **The batter layer is real but small.** How pitchers have attacked a hitter adds about 0.3 points of top-1. Most of what decides a pitch is the pitcher and the count, not the hitter.

## Your family-on-relabels rule: not kept

On 2025, the family-then-pitch model looked better on relabel-repaired games. On 2026 it was **worse** on those games (1.275 vs. 1.253 log loss, interval +0.012 to +0.032). The 2025 edge came from about 2,000 pitches and didn't replicate. This is why we wrote the rule down before scoring: it's a clean, defensible story for an interview. The family **view** stays in the report.

## Calibration

When xgboost says 40% slider, sliders come about 40% of the time. The average gap between predicted and actual frequency is 0.4 percentage points or less for every pitch type. See `figures/calibration_pitch.png` and `figures/calibration_family.png`. The pitcher's mix alone (L3) drifts below the diagonal at high probabilities, meaning it's overconfident for one-pitch-heavy situations. The context model fixes that.

## Per pitcher (468 pitchers, 500+ pitches in 2026)

- Better than the Phase 1 baseline for **100%** of them, and better than the best mix (L3) for **98%**. The median gain vs. L3 is 0.10 log loss.
- **Biggest gains:** Ryan Rolison, Yusei Kikuchi, Shane Baz. These are deep repertoires where count and sequence matter a lot.
- **Where it doesn't help:** John King, Josh Hader, Pete Fairbanks. Mostly two-pitch relievers whose mix already says nearly everything (Hader's L3 log loss is 0.66). The model loses a little by being pulled toward league-wide count habits that don't apply to them.

## By count

The gains are largest in 3-0 (0.52), 3-1 (0.22), 0-2 (0.16) and 2-0 (0.16), and smallest in 2-2 and 3-2. The model is most useful exactly where pitchers move furthest from their usual mix.

## Limitations

- **Pitch type only, not location.** Location density maps go in the report (Phase 4). A coarse-region location model is a stretch phase.
- **Public data only.** No catcher targets, game plans or scouting reports. The batter layer only sees how hitters were attacked, not why.
- **Savant labels.** Relabels are only partly repaired, and pitch types come from Savant's classifier.
- **Explaining xgboost.** Interactions are not directly readable. A SHAP view can be added for the write-up if useful.

## Next: Phase 4

The Shiny matchup app: pitch mix by count, zone/location density maps, platoon splits, xwOBA by pitch type, the family view, and the model's next-pitch prediction for a chosen count, built on the 2026 data and the final xgboost model.
