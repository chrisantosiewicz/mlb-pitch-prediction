# Decisions log

Every modeling and data choice, with the plain-language reason. This doubles as interview prep: each entry answers "why did you do it that way?"

## Confirmed by Chris (2026-10-07)

| # | Decision | Why |
|---|---|---|
| 1 | All R: baseballr, DuckDB/arrow, nnet/glmnet, xgboost, Shiny, Quarto | Matches the NFL thesis stack; Shiny is R-native; one language to defend. |
| 2 | Public GitHub repo, one commit per phase | The repo is the portfolio artifact. |
| 3 | Model every pitcher with shrinkage; report per-pitcher results only at 500+ pitches in the scored season | Thin samples still get sensible predictions, but nobody gets judged on 80 pitches. |
| 4 | 8 Savant-style pitch groups; rare types are never targets | Specific enough to be useful to a coach; rare pitches are too sparse to learn. |
| 5 | Train 2023-24, tune 2025, refit 2023-25, score 2026 once; regular season only | A time split mirrors how the model is used (predicting the future). Scoring the test season once keeps the headline number honest. |
| 6 | Empirical Bayes shrinkage toward same-hand, same-role league mix | One-sentence explanation, no Stan, and it fixes the "zero probability for a pitch he hasn't thrown yet" problem. |
| 7 | Host the app on shinyapps.io | Simplest free option for a portfolio link. |
| 8 | Build the in-season refresh in the offseason, prove it by replaying 2026, switch on for 2027 | Shows the project is maintained, not a one-off notebook. |

## Phase 1 choices

| Choice | Why |
|---|---|
| Pull one game day per request | A full day is ~4,500 pitches, well under Savant's ~25k-row cap, so no day is ever silently truncated. A failed day can be re-pulled on its own, and the same function runs the in-season refresh. |
| Store raw data as text, type it in the cleaning step | A day where a column happens to be all-missing can't change the raw schema, and the raw store is an exact copy of what Savant sent. |
| Parquet + DuckDB | ~3M rows is too big for CSV or git. DuckDB runs SQL directly on the parquet files, so cleaning steps are readable SQL with a row count after each. |
| Keep non-target pitches in the clean table | An automatic ball or a knuckleball is still "the previous pitch" for the next one. Dropping them would corrupt sequence features. |
| Remove position players pitching, keep two-way players | Position-player mop-up innings are not real pitch selection. Primary position comes from the MLB Stats API, not a velocity guess. |
| Starter = threw his team's first pitch of the game | Known before the game starts, so it's a fair input for both the baseline prior and the model. |
| Use Savant's `n_thruorder_pitcher` for times through the order | It agrees with a version derived from the pitcher's own batter count 99.8% of the time, and it measures the right thing: how many times *this batter* has seen this pitcher. |
| Baseline: shrunken prior-season mix, kappa and recency decay tuned on 2025 | The model has to beat the strongest version of "just use his mix", not a strawman. Tuning the baseline gets the same care as tuning the models. |
| 2026 is not scored in Phase 1 | The test season is looked at once, in Phase 3, for the baseline and models together. |
| Completeness check against the MLB schedule | Every completed game on the schedule must appear in the data. The same check guards the daily refresh in Phase 6. |
