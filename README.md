# MLB Next-Pitch Model and Matchup Report

Predicting a pitcher's next pitch type from game context, and turning it into a one-page pitcher-vs-batter advance report.

**Status:** Phase 1 (data, cleaning, baseline) complete and in review. See [PLAN.md](PLAN.md) for the full roadmap.

## What's here so far

| | |
|---|---|
| [docs/data_dictionary.md](docs/data_dictionary.md) | Every Statcast field: meaning, missing rate, and whether it's known before the pitch (the leakage guard) |
| [docs/cleaning_log.md](docs/cleaning_log.md) | Row counts after every cleaning step, completeness against the MLB schedule, data checks |
| [docs/baseline_results.md](docs/baseline_results.md) | The shrunken pitch-mix baseline every model has to beat |
| [docs/decisions.md](docs/decisions.md) | Every choice and the reason for it |

## Reproduce

Requires R 4.5 (Rtools not needed; all packages install as binaries on Windows).

```r
renv::restore()            # exact package versions from renv.lock
source("run_all.R")        # pull -> clean -> dictionary -> baseline -> tests
```

The first pull downloads about 3M pitches (2023-2026 regular seasons) from Baseball Savant one game day at a time and takes a while; later runs skip days already on disk. Data files live in `data/` and are not committed.

## Layout

```
R/           shared functions (pull, clean, baseline, players, schedule)
pipeline/    numbered steps, each reading only what the previous one wrote
docs/        dictionary, cleaning log, results, decisions
models/      saved model settings and metadata
tests/       unit tests (testthat)
```

## Data

Statcast pitch-level data from [Baseball Savant](https://baseballsavant.mlb.com), via [baseballr](https://billpetti.github.io/baseballr/). Player names and positions, and the schedule used for the completeness check, come from the MLB Stats API. This is a non-commercial portfolio project.
