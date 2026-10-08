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

## Phase 2 choices

| Choice | Why |
|---|---|
| Pull 2022 as history only | So 2023 training pitches have a prior season to build the pitcher's mix from, like every later season. 2022 is never trained on or scored. |
| Season-to-date mix as a second baseline (Chris approved 2026-10-08) | Mixes drift during a season. Updating each pitcher's mix with his games so far, through his previous game, is leakage-safe and is what an advance scout looks at. It also stops the context model from getting credit for catching mix changes. |
| Platoon tilt vs. batter hand in the mix | A pitcher's sweeper usage against same-side hitters is part of who he is, not context the model should have to rediscover. |
| Relabel repair using pitch physics (Chris's idea) | Savant relabels (slider to sweeper, four-seam to sinker) made the worst baseline misses. If a pitch vanishes and a new one with the same velocity and movement appears, his history of the old label is credited to the new one. Only earlier games are used. |
| Mix-change flag needs an established history and a 20%+ shift | With hundreds of pitches almost any drift is statistically significant, and pitchers with little history are compared mostly against the league mix. The flag should mean "this pitcher changed", not "we don't know him yet". |
| Pitch families: fastball (FF, SI, FC), breaking (SL, ST, CU), offspeed (CH, FS) | Relabels almost always stay inside a family, so family tendencies are the stable fallback Chris asked for. Cutters follow Savant's fastball convention. |
| His mix enters the logistic model as a fixed offset | The model starts from what he throws and only learns how situations shift him. That keeps coefficients league-wide and readable ("0-2 counts tilt toward breaking balls by X") and means a pitch he has never thrown gets almost no probability without hard masking. |
| Ridge (L2) penalty, tuned on 2025 | Many correlated dummy variables (count x hand, previous pitch x result). Ridge keeps all of them but shrinks noisy ones; the penalty is chosen on the tuning season, never on 2026. |
| Previous pitch result as a feature | Whether the last pitch was a whiff, foul, called strike or ball is known before the next pitch and is exactly what drives "go back to it" sequencing. |
| Two versions: all 8 pitches, and family-then-pitch | Tests Chris's question directly: does the situation mainly decide fastball vs. breaking vs. offspeed, with the specific pitch coming from his mix? |

## Phase 3 choices

| Choice | Why |
|---|---|
| Pre-register the 2026 test (committed before scoring) | The test season is looked at once. Writing the models, metrics and decision rules down first means the headline numbers can't be shaped by the results. |
| Batter layer as an offset tilt, shrunk with tau = 200 | How pitchers have attacked a hitter (observed vs. expected from their mixes, earlier games only). Shrinkage keeps hitters with little history near zero. |
| xgboost with the same mix offset as base margin | Same starting point as the logistic model, so the comparison isolates what trees add: interactions. Rounds picked by early stopping on 2025. |
| Bootstrap over games, not pitches | Pitches in the same game are correlated; resampling games gives honest intervals. |
| App uses xgboost | Pre-registered rule: best 2026 log loss among models that beat L3, unless within the logistic model's interval. xgboost beat it clearly (0.041, interval 0.039 to 0.042). |
| Family-on-relabels rule dropped | It was worse on 2026 relabel-repaired games (interval +0.012 to +0.032). The 2025 edge didn't replicate. |
