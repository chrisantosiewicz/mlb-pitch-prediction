# Phase 1 summary: data, cleaning, baseline

*Written 2026-10-07 for review.*

## What was built

- **Pull:** every regular-season game day of 2023-2026 from Baseball Savant, one day per request (2.95M pitches across all game types, 747 MB of parquet). Re-runnable; days already on disk are skipped.
- **Clean table:** 2,854,374 regular-season pitches, of which 2,841,447 are prediction targets in the 8 pitch groups. Every one of the 9,718 completed games on the MLB schedule is present. Details: [cleaning_log.md](cleaning_log.md).
- **Data dictionary:** all 120 Savant fields plus 15 derived fields, each tagged with *when it becomes known*. Details: [data_dictionary.md](data_dictionary.md).
- **Baseline:** each pitcher's prior-season mix, shrunk toward the league mix for his hand and role, tuned on 2025. Details: [baseline_results.md](baseline_results.md).

## Baseline numbers (2025, trained on 2023-24)

| Baseline | Log loss | Top-1 |
|---|---|---|
| League mix for his hand and role | 1.883 | 32.0% |
| His own past mix, no real shrinkage | 1.664 | 39.2% |
| **His own past mix, shrunk (the bar to beat)** | **1.561** | **39.1%** |

Shrinkage improves log loss by 0.10 while leaving top-1 unchanged. That is the point of shrinkage: it does not change the best guess, it stops the model from being overconfident about pitchers with thin or stale history. Tuned settings: kappa = 100 (each pitcher starts with 100 pitches of league mix) and decay = 0.25 (two seasons back counts a quarter as much as last season).

## Findings worth knowing before Phase 2

1. **Pitchers change their mix more than expected.** The tuning picked a steep recency decay: last season matters far more than two seasons ago. The worst-predicted pitchers are almost all pitchers whose mix changed.
2. **Savant relabels pitches, and it hurts.** Grant Anderson's sliders became sweepers in 2025 (0 sweepers in 2024, 438 in 2025), and Rafael Montero's changeup became a splitter. To the baseline these look like brand-new pitches, so his top-1 drops to 0%. The cleaning log lists 19 pitcher-seasons whose slider/sweeper share flipped by 50+ points. This is a label artifact, not a change in behavior, and it goes in the limitations.
3. **Debut seasons are hard.** Pitchers with no MLB history (79k pitches in 2025) can only get the league prior, so the baseline for them is near the league-mix floor.
4. **Relievers are easier than starters** (1.46 vs. 1.63 log loss) because most lean on two pitches.

## Leakage guards in place

- Every field is tagged before pitch / after pitch / after PA / future in the dictionary; only "before pitch" fields can become features. Savant's `pitcher_days_until_next_game` and `batter_days_until_next_game` are tagged **future** and never used.
- The baseline uses only seasons before the one it scores (unit-tested: changing 2025 pitches leaves 2025 predictions unchanged).
- **2026 has not been scored.** It gets scored once, in Phase 3, for the baseline and both models together.

## Proposed for Phase 2 (needs your OK)

Because mixes drift and get relabeled, I'd add the pitcher's **season-to-date mix through his previous game** as a model input, alongside the prior-season mix. It uses only games already played, so it's leakage-safe, and it's what an advance scout looks at. I'd also report it as a second, stronger baseline, so the context features (count, sequence, handedness) have to prove their value on top of it rather than getting credit for catching mix changes.
