# MLB Next-Pitch Model and Matchup Report

Predicting a pitcher's next pitch type from game context, and turning it into a one-page pitcher-vs-batter advance report.

**Status:** Phase 3 (gradient boosting and the 2026 test) complete and in review. See [docs/phase3_summary.md](docs/phase3_summary.md) and [PLAN.md](PLAN.md).

## What's here so far

| | |
|---|---|
| [docs/data_dictionary.md](docs/data_dictionary.md) | Every Statcast field: meaning, missing rate, and whether it's known before the pitch (the leakage guard) |
| [docs/cleaning_log.md](docs/cleaning_log.md) | Row counts after every cleaning step, completeness against the MLB schedule, data checks |
| [docs/baseline_results.md](docs/baseline_results.md) | The shrunken pitch-mix baseline every model has to beat |
| [docs/mix_results.md](docs/mix_results.md) | Pitcher-mix layers: prior, current form, platoon tilt, relabel repair, mix-change flag |
| [docs/logistic_results.md](docs/logistic_results.md) | The multinomial logistic context model vs. every baseline |
| [docs/preregistration.md](docs/preregistration.md) | The 2026 test plan, committed before scoring |
| [docs/test_results.md](docs/test_results.md) | The one-time 2026 test: every model, bootstrap intervals, calibration, per pitcher |
| [docs/decisions.md](docs/decisions.md) | Every choice and the reason for it |

## Reproduce

Requires R 4.5 (Rtools not needed; all packages install as binaries on Windows).

```r
renv::restore()            # exact package versions from renv.lock
source("run_all.R")        # pull -> clean -> baseline -> mixes -> features -> model -> tests
```

The first pull downloads about 3.6M pitches (2022-2026 regular seasons; 2022 is history only) from Baseball Savant one game day at a time and takes a while; later runs skip days already on disk. Data files live in `data/` and are not committed.

## Layout

```
R/           shared functions (pull, clean, baseline, mixes, features, models)
pipeline/    numbered steps, each reading only what the previous one wrote
docs/        dictionary, cleaning log, results, decisions
models/      saved model settings and metadata
tests/       unit tests (testthat)
```

## Data

Statcast pitch-level data from [Baseball Savant](https://baseballsavant.mlb.com), via [baseballr](https://billpetti.github.io/baseballr/). Player names and positions, and the schedule used for the completeness check, come from the MLB Stats API. This is a non-commercial portfolio project.
