# Phase 2 summary: features and multinomial logistic regression

*Written 2026-10-08 for review. All numbers are on the 2025 tuning season; 2026 is still untouched.*

## Headline

| Model | Log loss | Top-1 | Family top-1 |
|---|---|---|---|
| L1 prior mix (Phase 1 baseline) | 1.558 | 39.2% | 55.8% |
| L2 + current form (second baseline) | 1.368 | 41.1% | 56.6% |
| L3 + platoon tilt vs. batter hand | 1.344 | 42.0% | 56.6% |
| **Context model (multinomial logistic)** | **1.279** | **44.9%** | **58.2%** |

*Lower log loss is better. Family top-1 = right call on fastball / breaking / offspeed.*

Two things carry the improvement, and they're worth keeping apart in an interview:

1. **Knowing the pitcher better** (L1 → L3, 1.558 → 1.344). Most of this is *current form*: his mix so far this season, through his previous game. Pitch mixes change a lot from year to year, and a pitcher's first few outings already tell you how.
2. **Knowing the situation** (L3 → context model, 1.344 → 1.279). This is the part the brief asked for: count, sequence, handedness, game state. It is a real gain on top of a strong baseline, not on top of a strawman.

## What the context model learned (and it's calibrated)

The model's average fastball share by count lines up with what actually happened almost exactly:

| Count | His mix | Model | Actual |
|---|---|---|---|
| 0-2 | 55% | 44% | 42% |
| 2-0 | 55% | 71% | 71% |
| 3-0 | 55% | 95% | 94% |
| 3-1 | 55% | 77% | 77% |

The biggest gains are in hitter's counts (3-0, 3-1, 2-0) and two-strike counts (0-2, 1-2), where pitchers move furthest from their usual mix. Even counts like 1-1 and 2-2 gain the least.

**Sequencing:** after a swing-and-miss, pitchers threw the same pitch again 49.3% of the time. His mix alone would say 31.7%; the model says 49.7%.

**Relievers are easier than starters** (top-1 49.3% vs. 41.8%), because most relievers lean on two pitches.

## Your questions: relabels, mix changes, family fallback

- **Relabel repair works where it fires, but it fires rarely.** It found 42 pitcher-games in 2025 (Dylan Dodd's four-seam relabeled as a sinker, Chris Paddack's slider relabeled as a cutter). On those games, the prior-mix log loss improves from 2.02 to 1.58. It's rare because most relabels show up as a mix that's merely *different*, not one pitch vanishing cleanly, and current form handles those anyway.
- **The mix-change flag marks a real group.** 17% of 2025 pitches came from pitcher-games flagged as "mix changed". For them, the prior-season mix is badly off (1.87 log loss), and current form fixes most of it (1.45). The context model then gets to 1.36.
- **Family-then-pitch vs. all 8 pitches.** Both versions are equally good at fastball / breaking / offspeed (58.3% vs. 58.2%). But predicting all 8 pitches directly is better overall (1.279 vs. 1.303), which means the situation also shapes the *specific* pitch: sweeper vs. curveball with two strikes, for example. The family version did better only on the relabel-repaired games, which are too few (2,027 pitches) to justify a switching rule tuned on 2025.

**Recommendation:** use the 8-pitch model as the main model. Show the family view in the report, because it's what a hitter prepares for. Before scoring 2026, register one rule in writing: "use the family version for flagged pitcher-games". Then test it on 2026 in Phase 3 instead of tuning it now.

## Leakage guards

- Pitcher mixes use earlier seasons plus this season **through his previous game only**. Game-to-date features use pitches **before** the current one. The previous-pitch result (whiff, foul, ball) is known before the next pitch.
- Relabel detection uses only earlier games, and unit tests check that a new pitch with different velocity is *not* treated as a relabel.
- The ridge penalty and every mix setting were tuned on 2025. The penalty barely matters at this sample size (log loss moves in the fourth decimal), which is reassuring: the result isn't a tuning artifact.
- 2022 was pulled only as history for 2023 mixes. It's never trained on or scored.

## Limitations to state

- The model predicts pitch **type**, not location, and location is half of a pitcher's decision.
- It doesn't know the catcher, the game plan, or the scouting report on this hitter. The only batter information it uses is handedness. A batter-specific layer (how pitchers attack *this* hitter) is a possible Phase 3 extension.
- Labels come from Savant's classifier, and relabels are only partly repaired.

## Next: Phase 3

Gradient boosting on the same features and offsets. Then one scoring of 2026 for every model, with calibration plots, per-pitcher results (500+ pitches), bootstrap confidence intervals, and the pre-registered family-fallback test.
